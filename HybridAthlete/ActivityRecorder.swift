import Foundation
import CoreLocation
import CoreMotion
import ActivityKit

/// Records one activity: GPS distance + route, barometric elevation gain, and moving time with pause/resume.
@MainActor
final class ActivityRecorder: ObservableObject {
    enum State { case idle, recording, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elevationGainMeters: Double = 0
    @Published private(set) var route: [RoutePoint] = []
    @Published private(set) var movingSeconds: TimeInterval = 0
    @Published private(set) var locationDenied = false

    private(set) var type: ActivityType = .run
    private(set) var ruckWeightLbs: Double?
    private var startDate = Date()

    private let locationManager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?
    private var lastLocation: CLLocation?

    private let altimeter = CMAltimeter()
    private let useBarometer = CMAltimeter.isRelativeAltitudeAvailable()
    private var altitudeAnchor: Double?
    private var latestRelativeAltitude: Double?

    private var accumulatedSeconds: TimeInterval = 0
    private var segmentStart: Date?
    private var ticker: Timer?

    private let announcer = Announcer()
    private var announceEveryMeters: Double = 0
    private var nextAnnouncementMeters: Double = .infinity

    private var liveActivity: ActivityKit.Activity<RunActivityAttributes>?
    private var lastLiveUpdate = Date.distantPast

    func requestPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func start(type: ActivityType, ruckWeightLbs: Double?) {
        self.type = type
        self.ruckWeightLbs = type == .ruck ? ruckWeightLbs : nil
        distanceMeters = 0
        elevationGainMeters = 0
        route = []
        latestRelativeAltitude = nil
        accumulatedSeconds = 0
        movingSeconds = 0
        startDate = Date()
        locationDenied = false

        announceEveryMeters = Announcer.interval * Format.metersPerMile
        nextAnnouncementMeters = announceEveryMeters > 0 ? announceEveryMeters : .infinity

        requestPermission()
        backgroundSession = CLBackgroundActivitySession()
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self else { return }
                    if let location = update.location { self.handle(location) }
                }
            } catch {}
        }
        if useBarometer {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let altitude = data?.relativeAltitude.doubleValue else { return }
                MainActor.assumeIsolated {
                    self?.latestRelativeAltitude = altitude
                    self?.handleAltitude(altitude, threshold: 1)
                }
            }
        }
        resume()
        startLiveActivity()
    }

    func pause() {
        guard state == .recording else { return }
        if let segmentStart { accumulatedSeconds += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        ticker?.invalidate()
        movingSeconds = accumulatedSeconds
        state = .paused
        updateLiveActivity(force: true)
    }

    func resume() {
        // Don't count the distance covered while paused.
        lastLocation = nil
        altitudeAnchor = nil
        segmentStart = Date()
        state = .recording
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        updateLiveActivity(force: true)
    }

    /// Stops recording and returns the finished activity.
    func finish() -> Activity {
        pause()
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        if useBarometer { altimeter.stopRelativeAltitudeUpdates() }
        state = .idle
        endLiveActivity()

        return Activity(
            id: UUID(),
            type: type,
            start: startDate,
            end: Date(),
            movingSeconds: accumulatedSeconds,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            ruckWeightLbs: ruckWeightLbs,
            route: route
        )
    }

    func discard() {
        _ = finish()
    }

    private func tick() {
        let status = locationManager.authorizationStatus
        locationDenied = status == .denied || status == .restricted
        guard let segmentStart else { return }
        movingSeconds = accumulatedSeconds + Date().timeIntervalSince(segmentStart)
    }

    private func handle(_ location: CLLocation) {
        guard state == .recording,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 25,
              location.timestamp >= startDate else { return }

        if let last = lastLocation {
            let delta = location.distance(from: last)
            let seconds = location.timestamp.timeIntervalSince(last.timestamp)
            // Ignore GPS jumps faster than a sprinter.
            guard seconds > 0, delta / seconds < 12 else { return }
            distanceMeters += delta
            announceIfNeeded()
            updateLiveActivity()
        }
        lastLocation = location
        route.append(RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                altitude: location.altitude, timestamp: location.timestamp,
                                relativeAltitude: latestRelativeAltitude))

        if !useBarometer, location.verticalAccuracy >= 0, location.verticalAccuracy <= 15 {
            handleAltitude(location.altitude, threshold: 3)
        }
    }

    private func announceIfNeeded() {
        guard distanceMeters >= nextAnnouncementMeters else { return }
        let miles = (nextAnnouncementMeters / Format.metersPerMile * 100).rounded() / 100
        tick()
        announcer.split(miles: miles, seconds: movingSeconds)
        while nextAnnouncementMeters <= distanceMeters { nextAnnouncementMeters += announceEveryMeters }
    }

    // MARK: - Live Activity (Lock Screen + Dynamic Island)

    private var liveState: RunActivityAttributes.ContentState {
        .init(distanceMeters: distanceMeters, movingSeconds: accumulatedSeconds, segmentStart: segmentStart)
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RunActivityAttributes(title: type.title, symbol: type.symbol)
        liveActivity = try? ActivityKit.Activity.request(attributes: attributes, content: .init(state: liveState, staleDate: nil))
    }

    /// The timer ticks on its own; distance/pace refresh at most every 5s to stay well inside the update budget.
    private func updateLiveActivity(force: Bool = false) {
        guard let liveActivity, force || Date().timeIntervalSince(lastLiveUpdate) >= 5 else { return }
        lastLiveUpdate = Date()
        let content = ActivityContent(state: liveState, staleDate: nil)
        Task { await liveActivity.update(content) }
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        let content = ActivityContent(state: liveState, staleDate: nil)
        Task { await liveActivity.end(content, dismissalPolicy: .immediate) }
        self.liveActivity = nil
    }

    /// Counts climbing with hysteresis so sensor noise doesn't add up to fake hills.
    private func handleAltitude(_ altitude: Double, threshold: Double) {
        guard state == .recording else { return }
        guard let anchor = altitudeAnchor else { altitudeAnchor = altitude; return }
        if altitude >= anchor + threshold {
            elevationGainMeters += altitude - anchor
            altitudeAnchor = altitude
        } else if altitude <= anchor - threshold {
            altitudeAnchor = altitude
        }
    }
}
