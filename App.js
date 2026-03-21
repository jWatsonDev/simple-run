import { useState, useEffect, useRef } from 'react';
import { StyleSheet, Text, View, TouchableOpacity, SafeAreaView, FlatList, Alert, TextInput, KeyboardAvoidingView, Platform, ScrollView } from 'react-native';
import Svg, { Path, Defs, LinearGradient, Stop, Line, Text as SvgText } from 'react-native-svg';
import { StatusBar } from 'expo-status-bar';
import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import * as Notifications from 'expo-notifications';
import * as Sharing from 'expo-sharing';
import { captureRef } from 'react-native-view-shot';
import MapView, { Polyline } from 'react-native-maps';
import AsyncStorage from '@react-native-async-storage/async-storage';
let AppleHealthKit = null;
try { AppleHealthKit = require('react-native-health').default; } catch (_) {}

const HK_ACTIVITY = { Run: 'Running', Walk: 'Walking', Ruck: 'Hiking' };

const STORAGE_KEY = 'simple_run_history';
const RUN_STATE_KEY = 'simple_run_active';
const LOCATION_TASK = 'background-location';
const NOTIFICATION_ID = 'run-active';
const ACTIVITY_TYPES = ['Run', 'Ruck', 'Walk'];
const PERCEIVED = [
  { label: 'Easy', value: 2 },
  { label: 'Moderate', value: 5 },
  { label: 'Hard', value: 7 },
  { label: 'All Out', value: 10 },
];

// --- Utilities ---

function haversineDistance(a, b) {
  const R = 6371e3;
  const toRad = (x) => (x * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const sinLat = Math.sin(dLat / 2);
  const sinLon = Math.sin(dLon / 2);
  const c = 2 * Math.asin(Math.sqrt(sinLat * sinLat + Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * sinLon * sinLon));
  return R * c;
}

function formatTime(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

function formatPace(meters, seconds) {
  if (meters < 10) return '--:--';
  const miles = meters / 1609.34;
  const minutesPerMile = seconds / 60 / miles;
  const m = Math.floor(minutesPerMile);
  const s = Math.round((minutesPerMile - m) * 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

function formatDistance(meters) {
  return (meters / 1609.34).toFixed(2);
}

function formatElevation(meters) {
  return Math.round(meters * 3.28084);
}

function activityLabel(type, ruckWeight) {
  if (type === 'Ruck' && ruckWeight) return `Ruck (${ruckWeight} lbs)`;
  return type || 'Run';
}

function calcEffortScore(perceivedValue, distance, elapsed, elevGain, ruckWeight, avgHR) {
  let score = perceivedValue;
  if (distance > 10 && elapsed > 0) {
    const miles = distance / 1609.34;
    const pace = elapsed / 60 / miles;
    if (pace < 9) score += 1;
    else if (pace > 14) score -= 1;
  }
  const elevFt = elevGain * 3.28084;
  score += Math.floor(elevFt / 200);
  if (ruckWeight) score += Math.floor(parseFloat(ruckWeight) / 20);
  if (avgHR) {
    if (avgHR > 170) score += 2;
    else if (avgHR > 155) score += 1;
    else if (avgHR < 130) score -= 1;
  }
  return Math.min(10, Math.max(1, Math.round(score)));
}

// --- Notification ---

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: false,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

async function updateNotification(distance, elapsed) {
  try {
    await Notifications.scheduleNotificationAsync({
      identifier: NOTIFICATION_ID,
      content: {
        title: 'Ruck & Run · Active',
        body: `${formatDistance(distance)} mi · ${formatTime(elapsed)} · ${formatPace(distance, elapsed)} /mi`,
        sound: false,
        sticky: true,
      },
      trigger: null,
    });
  } catch (_) {}
}

// --- Background location task ---

TaskManager.defineTask(LOCATION_TASK, async ({ data, error }) => {
  if (error) { console.log('[BG] location error:', error.message); return; }
  if (!data?.locations?.length) return;

  try {
    const raw = await AsyncStorage.getItem(RUN_STATE_KEY);
    if (!raw) return;
    const state = JSON.parse(raw);

    for (const loc of data.locations) {
      const alt = loc.coords.altitude ?? null;
      const point = {
        latitude: loc.coords.latitude,
        longitude: loc.coords.longitude,
        altitude: alt,
        timestamp: loc.timestamp,
      };
      if (state.coords.length > 0) {
        state.distance += haversineDistance(state.coords[state.coords.length - 1], point);
      }
      state.coords.push(point);
      if (alt != null) {
        if (state.lastAlt != null && alt > state.lastAlt + 0.5) {
          state.elevGain += alt - state.lastAlt;
        }
        state.lastAlt = alt;
      }
    }

    await AsyncStorage.setItem(RUN_STATE_KEY, JSON.stringify(state));

    const elapsed = Math.floor((Date.now() - state.startTime) / 1000);
    await updateNotification(state.distance, elapsed);
  } catch (e) {
    console.log('[BG] task error:', e);
  }
});

// --- Charts ---

const CHART_W = 340;
const CHART_H = 90;
const CHART_PAD = { top: 8, bottom: 24, left: 36, right: 8 };

function buildPath(points, xScale, yScale) {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${xScale(i)} ${yScale(p)}`).join(' ');
}

function ElevationChart({ coords }) {
  const altPoints = coords.filter((c) => c.altitude != null).map((c) => c.altitude);
  if (altPoints.length < 2) return null;

  const w = CHART_W - CHART_PAD.left - CHART_PAD.right;
  const h = CHART_H - CHART_PAD.top - CHART_PAD.bottom;
  const minAlt = Math.min(...altPoints);
  const maxAlt = Math.max(...altPoints);
  const range = maxAlt - minAlt || 1;

  // Downsample to max 80 points for perf
  const step = Math.max(1, Math.floor(altPoints.length / 80));
  const sampled = altPoints.filter((_, i) => i % step === 0);

  const xScale = (i) => CHART_PAD.left + (i / (sampled.length - 1)) * w;
  const yScale = (v) => CHART_PAD.top + h - ((v - minAlt) / range) * h;

  const linePath = buildPath(sampled, xScale, yScale);
  const areaPath = `${linePath} L ${xScale(sampled.length - 1)} ${CHART_PAD.top + h} L ${xScale(0)} ${CHART_PAD.top + h} Z`;

  const minFt = formatElevation(minAlt);
  const maxFt = formatElevation(maxAlt);

  return (
    <View style={chartStyles.container}>
      <Text style={chartStyles.label}>Elevation</Text>
      <Svg width={CHART_W} height={CHART_H}>
        <Defs>
          <LinearGradient id="elevGrad" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor="#1a6b3c" stopOpacity="0.6" />
            <Stop offset="1" stopColor="#1a6b3c" stopOpacity="0.05" />
          </LinearGradient>
        </Defs>
        {/* Y axis labels */}
        <SvgText x={CHART_PAD.left - 4} y={CHART_PAD.top + 4} fontSize="9" fill="#aaa" textAnchor="end">{maxFt}ft</SvgText>
        <SvgText x={CHART_PAD.left - 4} y={CHART_PAD.top + h + 1} fontSize="9" fill="#aaa" textAnchor="end">{minFt}ft</SvgText>
        {/* Baseline */}
        <Line x1={CHART_PAD.left} y1={CHART_PAD.top + h} x2={CHART_PAD.left + w} y2={CHART_PAD.top + h} stroke="#eee" strokeWidth="1" />
        {/* Area fill */}
        <Path d={areaPath} fill="url(#elevGrad)" />
        {/* Line */}
        <Path d={linePath} fill="none" stroke="#1a6b3c" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      </Svg>
    </View>
  );
}

function PaceChart({ coords }) {
  // Build per-0.25mi pace segments using timestamp + haversine
  if (coords.length < 2 || !coords[0].timestamp) return null;

  const SEGMENT_M = 402; // 0.25 miles in meters
  const segments = [];
  let segDist = 0;
  let segStart = coords[0];

  for (let i = 1; i < coords.length; i++) {
    const d = haversineDistance(coords[i - 1], coords[i]);
    segDist += d;
    if (segDist >= SEGMENT_M) {
      const elapsed = (coords[i].timestamp - segStart.timestamp) / 1000;
      const pace = elapsed / 60 / (segDist / 1609.34); // min/mile
      if (pace > 3 && pace < 30) segments.push(pace); // filter GPS noise
      segDist = 0;
      segStart = coords[i];
    }
  }

  if (segments.length < 2) return null;

  const w = CHART_W - CHART_PAD.left - CHART_PAD.right;
  const h = CHART_H - CHART_PAD.top - CHART_PAD.bottom;
  const minPace = Math.min(...segments);
  const maxPace = Math.max(...segments);
  const range = maxPace - minPace || 1;

  // Pace: lower is faster, so invert y axis
  const xScale = (i) => CHART_PAD.left + (i / (segments.length - 1)) * w;
  const yScale = (v) => CHART_PAD.top + ((v - minPace) / range) * h; // inverted

  const linePath = buildPath(segments, xScale, yScale);
  const areaPath = `${linePath} L ${xScale(segments.length - 1)} ${CHART_PAD.top + h} L ${xScale(0)} ${CHART_PAD.top + h} Z`;

  const fmtPace = (p) => { const m = Math.floor(p); const s = Math.round((p - m) * 60); return `${m}:${String(s).padStart(2, '0')}`; };

  return (
    <View style={chartStyles.container}>
      <Text style={chartStyles.label}>Pace / mile  <Text style={chartStyles.labelSub}>by ¼ mi</Text></Text>
      <Svg width={CHART_W} height={CHART_H}>
        <Defs>
          <LinearGradient id="paceGrad" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor="#111" stopOpacity="0.15" />
            <Stop offset="1" stopColor="#111" stopOpacity="0.02" />
          </LinearGradient>
        </Defs>
        <SvgText x={CHART_PAD.left - 4} y={CHART_PAD.top + 4} fontSize="9" fill="#aaa" textAnchor="end">{fmtPace(minPace)}</SvgText>
        <SvgText x={CHART_PAD.left - 4} y={CHART_PAD.top + h + 1} fontSize="9" fill="#aaa" textAnchor="end">{fmtPace(maxPace)}</SvgText>
        <Line x1={CHART_PAD.left} y1={CHART_PAD.top + h} x2={CHART_PAD.left + w} y2={CHART_PAD.top + h} stroke="#eee" strokeWidth="1" />
        <Path d={areaPath} fill="url(#paceGrad)" />
        <Path d={linePath} fill="none" stroke="#111" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
      </Svg>
    </View>
  );
}

// --- Share Card ---

function ShareCard({ run, cardRef }) {
  const coords = run?.coords ?? [];
  const region = coords.length > 0 ? {
    latitude: coords.reduce((s, c) => s + c.latitude, 0) / coords.length,
    longitude: coords.reduce((s, c) => s + c.longitude, 0) / coords.length,
    latitudeDelta: 0.02,
    longitudeDelta: 0.02,
  } : { latitude: 37.78825, longitude: -122.4324, latitudeDelta: 0.02, longitudeDelta: 0.02 };

  return (
    <View ref={cardRef} style={shareStyles.card} collapsable={false}>
      <View style={shareStyles.topBar} />
      <MapView
        style={shareStyles.map}
        region={region}
        scrollEnabled={false}
        zoomEnabled={false}
        rotateEnabled={false}
        pitchEnabled={false}
        liteMode
      >
        {coords.length > 1 && <Polyline coordinates={coords} strokeColor="#fff" strokeWidth={4} />}
      </MapView>
      <View style={shareStyles.statsBlock}>
        <View style={shareStyles.statRow}>
          <View style={shareStyles.stat}>
            <Text style={shareStyles.statValue}>{formatDistance(run?.distance ?? 0)}</Text>
            <Text style={shareStyles.statLabel}>Miles</Text>
          </View>
          <View style={shareStyles.stat}>
            <Text style={shareStyles.statValue}>{formatTime(run?.elapsed ?? 0)}</Text>
            <Text style={shareStyles.statLabel}>Time</Text>
          </View>
          <View style={shareStyles.stat}>
            <Text style={shareStyles.statValue}>{formatPace(run?.distance ?? 0, run?.elapsed ?? 0)}</Text>
            <Text style={shareStyles.statLabel}>Pace /mi</Text>
          </View>
          {run?.effortScore != null && (
            <View style={shareStyles.stat}>
              <Text style={shareStyles.statValue}>{run.effortScore}/10</Text>
              <Text style={shareStyles.statLabel}>Effort</Text>
            </View>
          )}
        </View>
        <View style={shareStyles.divider} />
        <View style={shareStyles.footer}>
          <Text style={shareStyles.appName}>Ruck & Run</Text>
          <Text style={shareStyles.brand}>A DadHabit.dad app</Text>
        </View>
      </View>
      <View style={shareStyles.bottomBar} />
    </View>
  );
}

// --- Screens ---

function RunScreen({ onViewHistory }) {
  const [status, setStatus] = useState('idle');
  const [activity, setActivity] = useState('Run');
  const [ruckWeight, setRuckWeight] = useState('');
  const [coords, setCoords] = useState([]);
  const [distance, setDistance] = useState(0);
  const [elapsed, setElapsed] = useState(0);
  const [elevGain, setElevGain] = useState(0);
  const [runs, setRuns] = useState([]);
  const [pendingRun, setPendingRun] = useState(null);

  const timerRef = useRef(null);
  const mapRef = useRef(null);
  const startTimeRef = useRef(null);
  const shareCardRef = useRef(null);

  useEffect(() => {
    loadRuns();
    centerOnUser();
    // Resume if a run was already in progress (e.g. app crash/restart)
    Location.hasStartedLocationUpdatesAsync(LOCATION_TASK).then((active) => {
      if (active) {
        setStatus('running');
        AsyncStorage.getItem(RUN_STATE_KEY).then((raw) => {
          if (!raw) return;
          const state = JSON.parse(raw);
          startTimeRef.current = state.startTime;
          startSyncTimer();
        });
      }
    }).catch(() => {});
    try {
      AppleHealthKit?.initHealthKit({
        permissions: {
          read: [AppleHealthKit.Constants.Permissions.Workout, AppleHealthKit.Constants.Permissions.HeartRate],
          write: [AppleHealthKit.Constants.Permissions.Workout],
        },
      }, (err) => {
        if (err) Alert.alert('[DEBUG] HealthKit init failed', JSON.stringify(err));
        else console.log('[HealthKit] init success');
      });
    } catch (_) {}
    return () => {
      clearInterval(timerRef.current);
    };
  }, []);

  function startSyncTimer() {
    clearInterval(timerRef.current);
    timerRef.current = setInterval(async () => {
      const raw = await AsyncStorage.getItem(RUN_STATE_KEY);
      if (!raw) return;
      const state = JSON.parse(raw);
      setCoords([...state.coords]);
      setDistance(state.distance);
      setElevGain(state.elevGain);
      setElapsed(Math.floor((Date.now() - state.startTime) / 1000));
      if (state.coords.length > 0) {
        const last = state.coords[state.coords.length - 1];
        mapRef.current?.animateCamera({ center: last, zoom: 17 }, { duration: 500 });
      }
    }, 1000);
  }

  async function centerOnUser() {
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') return;
    const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
    mapRef.current?.animateToRegion({
      latitude: loc.coords.latitude,
      longitude: loc.coords.longitude,
      latitudeDelta: 0.01,
      longitudeDelta: 0.01,
    }, 500);
  }

  async function loadRuns() {
    const raw = await AsyncStorage.getItem(STORAGE_KEY);
    if (raw) setRuns(JSON.parse(raw));
  }

  async function saveRun(run) {
    const updated = [run, ...runs];
    setRuns(updated);
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
  }

  async function startRun() {
    if (activity === 'Ruck' && !ruckWeight.trim()) {
      Alert.alert('Pack Weight Required', 'Enter your pack weight in lbs to start a ruck.');
      return;
    }
    const { status: fgStatus } = await Location.requestForegroundPermissionsAsync();
    if (fgStatus !== 'granted') {
      Alert.alert('Location Required', 'Enable location access to track your activity.');
      return;
    }
    // Request background permission — best effort, don't block if denied
    await Location.requestBackgroundPermissionsAsync().catch(() => {});
    await Notifications.requestPermissionsAsync().catch(() => {});

    const startTime = Date.now();
    startTimeRef.current = startTime;

    await AsyncStorage.setItem(RUN_STATE_KEY, JSON.stringify({
      coords: [],
      distance: 0,
      elevGain: 0,
      lastAlt: null,
      startTime,
      activity,
      ruckWeight: activity === 'Ruck' ? ruckWeight : null,
    }));

    setCoords([]);
    setDistance(0);
    setElapsed(0);
    setElevGain(0);
    setStatus('running');

    await Location.startLocationUpdatesAsync(LOCATION_TASK, {
      accuracy: Location.Accuracy.BestForNavigation,
      distanceInterval: 5,
      showsBackgroundLocationIndicator: true, // iOS blue status bar indicator
      foregroundService: {
        // Android: required for background location, also shows as notification
        notificationTitle: 'Ruck & Run',
        notificationBody: 'Tracking your activity...',
        notificationColor: '#111111',
      },
    });

    await updateNotification(0, 0);
    startSyncTimer();
  }

  async function finishRun() {
    clearInterval(timerRef.current);
    try {
      const active = await Location.hasStartedLocationUpdatesAsync(LOCATION_TASK);
      if (active) await Location.stopLocationUpdatesAsync(LOCATION_TASK);
    } catch (_) {}
    await Notifications.dismissAllNotificationsAsync().catch(() => {});

    // Read final state from AsyncStorage (captures any points collected while screen was locked)
    const raw = await AsyncStorage.getItem(RUN_STATE_KEY);
    const state = raw ? JSON.parse(raw) : { coords, distance, elevGain, startTime: startTimeRef.current };

    if (state.coords.length > 1) {
      mapRef.current?.fitToCoordinates(state.coords, {
        edgePadding: { top: 40, right: 40, bottom: 40, left: 40 },
        animated: true,
      });
    }

    setPendingRun({
      id: Date.now(),
      date: new Date().toLocaleDateString(),
      activity,
      ruckWeight: activity === 'Ruck' ? ruckWeight : null,
      distance: state.distance,
      elapsed: Math.floor((Date.now() - state.startTime) / 1000),
      elevGain: state.elevGain,
      coords: state.coords,
      startTime: state.startTime,
      endTime: Date.now(),
    });
    setStatus('rating');
  }

  async function submitRating(perceivedValue, label) {
    // Query heart rate samples for the run window
    let avgHR = null;
    let maxHR = null;
    await new Promise((resolve) => {
      // Safety timeout — never hang longer than 3s waiting for HealthKit
      const timeout = setTimeout(resolve, 3000);
      try {
        if (!AppleHealthKit) { clearTimeout(timeout); resolve(); return; }
        AppleHealthKit.getHeartRateSamples({
          startDate: new Date(pendingRun.startTime).toISOString(),
          endDate: new Date(pendingRun.endTime).toISOString(),
          ascending: true,
          limit: 0,
        }, (err, results) => {
          clearTimeout(timeout);
          if (!err && results?.length > 0) {
            const values = results.map((r) => r.value);
            avgHR = Math.round(values.reduce((s, v) => s + v, 0) / values.length);
            maxHR = Math.round(Math.max(...values));
            console.log(`[HealthKit] HR samples: ${results.length}, avg: ${avgHR}, max: ${maxHR}`);
          } else if (err) {
            console.log('[HealthKit] getHeartRateSamples error:', err);
          }
          resolve();
        });
      } catch (_) { clearTimeout(timeout); resolve(); }
    });

    const score = calcEffortScore(perceivedValue, pendingRun.distance, pendingRun.elapsed, pendingRun.elevGain, pendingRun.ruckWeight, avgHR);
    const run = { ...pendingRun, perceived: label, effortScore: score, avgHR, maxHR };
    await saveRun(run);
    try {
      AppleHealthKit?.saveWorkout({
        type: HK_ACTIVITY[run.activity] ?? 'Running',
        startDate: new Date(run.startTime).toISOString(),
        endDate: new Date(run.endTime).toISOString(),
        distance: run.distance / 1609.34,
        distanceUnit: 'mile',
      }, (err, result) => {
        if (err) Alert.alert('[DEBUG] HealthKit saveWorkout failed', JSON.stringify(err));
        else Alert.alert('[DEBUG] HealthKit saveWorkout OK', JSON.stringify(result));
      });
    } catch (_) {}
    setStatus('done');
  }

  async function shareRun() {
    try {
      const uri = await captureRef(shareCardRef, { format: 'png', quality: 1 });
      await Sharing.shareAsync(uri, { mimeType: 'image/png', dialogTitle: 'Share your run' });
    } catch (e) {
      console.log('[Share] error:', e);
    }
  }

  function resetRun() {
    setStatus('idle');
    setCoords([]);
    setDistance(0);
    setElapsed(0);
    setElevGain(0);
    setRuckWeight('');
    setPendingRun(null);
  }

  const initialRegion = {
    latitude: coords[0]?.latitude ?? 37.78825,
    longitude: coords[0]?.longitude ?? -122.4324,
    latitudeDelta: 0.01,
    longitudeDelta: 0.01,
  };

  if (status === 'rating') {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar style="dark" />
        <Text style={styles.appTitle}>Ruck & Run</Text>
        <View style={styles.ratingContainer}>
          <Text style={styles.ratingTitle}>How did that feel?</Text>
          <Text style={styles.ratingSubtitle}>
            {formatDistance(pendingRun.distance)} mi · {formatTime(pendingRun.elapsed)} · {formatElevation(pendingRun.elevGain)} ft gain
          </Text>
          {PERCEIVED.map((p) => (
            <TouchableOpacity
              key={p.label}
              style={styles.ratingBtn}
              onPress={() => submitRating(p.value, p.label)}
            >
              <Text style={styles.ratingBtnText}>{p.label}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="dark" />
      <Text style={styles.appTitle}>Ruck & Run</Text>

      {status === 'idle' && (
        <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <View style={styles.activitySelector}>
            {ACTIVITY_TYPES.map((type) => (
              <TouchableOpacity
                key={type}
                style={[styles.activityBtn, activity === type && styles.activityBtnActive]}
                onPress={() => setActivity(type)}
              >
                <Text style={[styles.activityBtnText, activity === type && styles.activityBtnTextActive]}>
                  {type}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
          {activity === 'Ruck' && (
            <View style={styles.weightRow}>
              <Text style={styles.weightLabel}>Pack weight (lbs)</Text>
              <TextInput
                style={styles.weightInput}
                value={ruckWeight}
                onChangeText={setRuckWeight}
                keyboardType="numeric"
                placeholder="e.g. 35"
                placeholderTextColor="#bbb"
                maxLength={3}
              />
            </View>
          )}
        </KeyboardAvoidingView>
      )}

      {status === 'running' && (
        <View style={styles.activityBadgeRow}>
          <Text style={styles.activityBadge}>{activityLabel(activity, ruckWeight)}</Text>
        </View>
      )}

      <MapView ref={mapRef} style={styles.map} initialRegion={initialRegion} showsUserLocation>
        {coords.length > 1 && <Polyline coordinates={coords} strokeColor="#111111" strokeWidth={4} />}
      </MapView>

      <View style={styles.stats}>
        <View style={styles.statBlock}>
          <Text style={styles.statValue}>{formatDistance(distance)}</Text>
          <Text style={styles.statLabel}>Miles</Text>
        </View>
        <View style={styles.statBlock}>
          <Text style={styles.statValue}>{formatTime(elapsed)}</Text>
          <Text style={styles.statLabel}>Time</Text>
        </View>
        <View style={styles.statBlock}>
          <Text style={styles.statValue}>{formatPace(distance, elapsed)}</Text>
          <Text style={styles.statLabel}>Pace /mi</Text>
        </View>
        {status === 'running' && (
          <View style={styles.statBlock}>
            <Text style={styles.statValue}>{formatElevation(elevGain)}</Text>
            <Text style={styles.statLabel}>Ft Gain</Text>
          </View>
        )}
      </View>

      <View style={styles.controls}>
        {status === 'idle' && (
          <TouchableOpacity style={[styles.btn, styles.btnPrimary]} onPress={startRun}>
            <Text style={styles.btnText}>Start {activity}</Text>
          </TouchableOpacity>
        )}
        {status === 'running' && (
          <TouchableOpacity style={[styles.btn, styles.btnStop]} onPress={finishRun}>
            <Text style={styles.btnText}>Finish {activity}</Text>
          </TouchableOpacity>
        )}
        {status === 'done' && (
          <View>
            <TouchableOpacity style={[styles.btn, styles.btnShare]} onPress={shareRun}>
              <Text style={styles.btnText}>Share {activity}</Text>
            </TouchableOpacity>
            <View style={styles.row}>
              <TouchableOpacity style={[styles.btn, styles.btnSecondary]} onPress={resetRun}>
                <Text style={styles.btnText}>New Activity</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[styles.btn, styles.btnPrimary, { flex: 1 }]} onPress={onViewHistory}>
                <Text style={styles.btnText}>History</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
      </View>

      {status === 'idle' && (
        <TouchableOpacity onPress={onViewHistory} style={styles.historyLink}>
          <Text style={styles.historyLinkText}>View past activities</Text>
        </TouchableOpacity>
      )}

      {status === 'idle' && (
        <Text style={styles.dadhabitFooter}>A DadHabit.dad app</Text>
      )}

      {/* Off-screen share card — captured by view-shot, never visible to user */}
      <View style={shareStyles.offscreen}>
        <ShareCard run={pendingRun} cardRef={shareCardRef} />
      </View>
    </SafeAreaView>
  );
}

function HistoryScreen({ onBack, onSelectRun }) {
  const [runs, setRuns] = useState([]);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY).then((raw) => {
      if (raw) setRuns(JSON.parse(raw));
    });
  }, []);

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="dark" />
      <View style={styles.historyHeader}>
        <TouchableOpacity onPress={onBack}>
          <Text style={styles.backBtn}>← Back</Text>
        </TouchableOpacity>
        <Text style={styles.appTitle}>History</Text>
      </View>

      {runs.length === 0 ? (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>No activities yet. Get moving!</Text>
        </View>
      ) : (
        <FlatList
          data={runs}
          keyExtractor={(item) => String(item.id)}
          contentContainerStyle={{ padding: 20 }}
          renderItem={({ item }) => (
            <TouchableOpacity style={styles.runCard} onPress={() => onSelectRun(item)}>
              <View style={styles.row}>
                <Text style={styles.activityTag}>{activityLabel(item.activity, item.ruckWeight)}</Text>
                <Text style={styles.runDate}>{item.date}</Text>
              </View>
              <View style={[styles.row, { marginTop: 6, flexWrap: 'wrap' }]}>
                <Text style={styles.runStat}>{formatDistance(item.distance)} mi</Text>
                <Text style={styles.runStat}>{formatTime(item.elapsed)}</Text>
                <Text style={styles.runStat}>{formatPace(item.distance, item.elapsed)} /mi</Text>
                {item.elevGain != null && (
                  <Text style={styles.runStat}>{formatElevation(item.elevGain)} ft</Text>
                )}
              </View>
              {item.effortScore != null && (
                <View style={styles.effortRow}>
                  <Text style={styles.effortLabel}>Effort</Text>
                  <Text style={styles.effortScore}>{item.effortScore}/10</Text>
                  {item.perceived && <Text style={styles.effortPerceived}>· {item.perceived}</Text>}
                  {item.avgHR != null && (
                    <Text style={styles.effortPerceived}>· {item.avgHR} avg bpm</Text>
                  )}
                  {item.maxHR != null && (
                    <Text style={styles.effortPerceived}>· {item.maxHR} max</Text>
                  )}
                </View>
              )}
            </TouchableOpacity>
          )}
        />
      )}
    </SafeAreaView>
  );
}

function DetailScreen({ run, onBack }) {
  const cardRef = useRef(null);
  const coords = run.coords ?? [];
  const region = coords.length > 0 ? {
    latitude: coords.reduce((s, c) => s + c.latitude, 0) / coords.length,
    longitude: coords.reduce((s, c) => s + c.longitude, 0) / coords.length,
    latitudeDelta: 0.02,
    longitudeDelta: 0.02,
  } : { latitude: 37.78825, longitude: -122.4324, latitudeDelta: 0.02, longitudeDelta: 0.02 };

  async function share() {
    try {
      const uri = await captureRef(cardRef, { format: 'png', quality: 1 });
      await Sharing.shareAsync(uri, { mimeType: 'image/png', dialogTitle: 'Share your run' });
    } catch (e) {
      console.log('[Share] error:', e);
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="dark" />
      <View style={styles.historyHeader}>
        <TouchableOpacity onPress={onBack}>
          <Text style={styles.backBtn}>← Back</Text>
        </TouchableOpacity>
        <Text style={styles.appTitle}>{activityLabel(run.activity, run.ruckWeight)}</Text>
      </View>

      <MapView style={detailStyles.map} region={region} scrollEnabled zoomEnabled>
        {coords.length > 1 && <Polyline coordinates={coords} strokeColor="#111111" strokeWidth={4} />}
      </MapView>

      <ScrollView contentContainerStyle={detailStyles.scroll}>
        <View style={styles.stats}>
          <View style={styles.statBlock}>
            <Text style={styles.statValue}>{formatDistance(run.distance)}</Text>
            <Text style={styles.statLabel}>Miles</Text>
          </View>
          <View style={styles.statBlock}>
            <Text style={styles.statValue}>{formatTime(run.elapsed)}</Text>
            <Text style={styles.statLabel}>Time</Text>
          </View>
          <View style={styles.statBlock}>
            <Text style={styles.statValue}>{formatPace(run.distance, run.elapsed)}</Text>
            <Text style={styles.statLabel}>Pace /mi</Text>
          </View>
          <View style={styles.statBlock}>
            <Text style={styles.statValue}>{formatElevation(run.elevGain)}</Text>
            <Text style={styles.statLabel}>Ft Gain</Text>
          </View>
        </View>

        {(run.effortScore != null || run.avgHR != null) && (
          <View style={styles.detailMeta}>
            {run.effortScore != null && (
              <Text style={styles.detailMetaText}>Effort {run.effortScore}/10 · {run.perceived}</Text>
            )}
            {run.avgHR != null && (
              <Text style={styles.detailMetaText}>{run.avgHR} avg bpm · {run.maxHR} max bpm</Text>
            )}
            <Text style={styles.detailMetaText}>{run.date}</Text>
          </View>
        )}

        <ElevationChart coords={coords} />
        <PaceChart coords={coords} />

        <View style={[styles.controls, { paddingTop: 8 }]}>
          <TouchableOpacity style={[styles.btn, styles.btnShare]} onPress={share}>
            <Text style={styles.btnText}>Share {run.activity}</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>

      {/* Off-screen share card */}
      <View style={shareStyles.offscreen}>
        <ShareCard run={run} cardRef={cardRef} />
      </View>
    </SafeAreaView>
  );
}

// --- Root ---

export default function App() {
  const [screen, setScreen] = useState('run');
  const [selectedRun, setSelectedRun] = useState(null);

  if (screen === 'run') return <RunScreen onViewHistory={() => setScreen('history')} />;
  if (screen === 'detail') return <DetailScreen run={selectedRun} onBack={() => setScreen('history')} />;
  return (
    <HistoryScreen
      onBack={() => setScreen('run')}
      onSelectRun={(run) => { setSelectedRun(run); setScreen('detail'); }}
    />
  );
}

// --- Styles ---

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  appTitle: { fontSize: 22, fontWeight: '700', textAlign: 'center', paddingVertical: 12, color: '#111' },
  activitySelector: { flexDirection: 'row', justifyContent: 'center', paddingHorizontal: 24, gap: 8, paddingBottom: 8 },
  activityBtn: { flex: 1, borderRadius: 10, paddingVertical: 10, alignItems: 'center', backgroundColor: '#F2F2F2' },
  activityBtnActive: { backgroundColor: '#111' },
  activityBtnText: { fontSize: 15, fontWeight: '600', color: '#888' },
  activityBtnTextActive: { color: '#fff' },
  weightRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingBottom: 8, gap: 12 },
  weightLabel: { fontSize: 14, color: '#555' },
  weightInput: { borderWidth: 1, borderColor: '#ddd', borderRadius: 8, paddingHorizontal: 12, paddingVertical: 6, fontSize: 16, width: 80, textAlign: 'center', color: '#111' },
  activityBadgeRow: { alignItems: 'center', paddingBottom: 4 },
  activityBadge: { fontSize: 14, fontWeight: '700', color: '#111' },
  map: { flex: 1 },
  stats: { flexDirection: 'row', justifyContent: 'space-around', paddingVertical: 20, borderTopWidth: 1, borderColor: '#eee' },
  statBlock: { alignItems: 'center' },
  statValue: { fontSize: 26, fontWeight: '700', color: '#111' },
  statLabel: { fontSize: 11, color: '#888', marginTop: 2 },
  controls: { paddingHorizontal: 24, paddingBottom: 12 },
  btn: { borderRadius: 12, paddingVertical: 16, alignItems: 'center', marginVertical: 4 },
  btnPrimary: { backgroundColor: '#111' },
  btnStop: { backgroundColor: '#555' },
  btnShare: { backgroundColor: '#1a6b3c' },
  btnSecondary: { backgroundColor: '#888', flex: 1, marginRight: 8 },
  btnText: { color: '#fff', fontSize: 18, fontWeight: '700' },
  row: { flexDirection: 'row', alignItems: 'center' },
  historyLink: { alignItems: 'center', paddingBottom: 16 },
  historyLinkText: { color: '#888', fontSize: 14 },
  dadhabitFooter: { textAlign: 'center', color: '#ccc', fontSize: 11, paddingBottom: 12 },
  historyHeader: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, paddingTop: 8 },
  backBtn: { fontSize: 16, color: '#111', marginRight: 12 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: '#aaa', fontSize: 16 },
  runCard: { backgroundColor: '#F9F9F9', borderRadius: 10, padding: 16, marginBottom: 12, borderLeftWidth: 3, borderLeftColor: '#111' },
  runDate: { fontSize: 13, color: '#888', marginLeft: 'auto' },
  activityTag: { fontSize: 13, fontWeight: '700', color: '#111' },
  runStat: { fontSize: 15, fontWeight: '600', color: '#111', marginRight: 12 },
  effortRow: { flexDirection: 'row', alignItems: 'center', marginTop: 8, paddingTop: 8, borderTopWidth: 1, borderTopColor: '#eee' },
  effortLabel: { fontSize: 12, color: '#888', marginRight: 6 },
  effortScore: { fontSize: 15, fontWeight: '800', color: '#111' },
  effortPerceived: { fontSize: 12, color: '#888', marginLeft: 4 },
  ratingContainer: { flex: 1, paddingHorizontal: 24, justifyContent: 'center' },
  ratingTitle: { fontSize: 24, fontWeight: '700', color: '#111', textAlign: 'center', marginBottom: 8 },
  ratingSubtitle: { fontSize: 14, color: '#888', textAlign: 'center', marginBottom: 32 },
  ratingBtn: { backgroundColor: '#F2F2F2', borderRadius: 12, paddingVertical: 18, alignItems: 'center', marginBottom: 12 },
  ratingBtnText: { fontSize: 18, fontWeight: '700', color: '#111' },
  detailMeta: { paddingHorizontal: 24, paddingBottom: 8, gap: 2 },
  detailMetaText: { fontSize: 13, color: '#888' },
});

const detailStyles = StyleSheet.create({
  map: { height: 220 },
  scroll: { paddingBottom: 32 },
});

const chartStyles = StyleSheet.create({
  container: { paddingHorizontal: 16, paddingTop: 16 },
  label: { fontSize: 12, fontWeight: '700', color: '#555', marginBottom: 4, textTransform: 'uppercase', letterSpacing: 0.5 },
  labelSub: { fontSize: 11, fontWeight: '400', color: '#aaa', textTransform: 'none', letterSpacing: 0 },
});

const shareStyles = StyleSheet.create({
  offscreen: { position: 'absolute', top: -2000, left: 0, opacity: 0 },
  card: { width: 375, backgroundColor: '#0d1f0d', overflow: 'hidden' },
  topBar: { height: 8, backgroundColor: '#1a6b3c' },
  map: { width: 375, height: 280 },
  statsBlock: { paddingHorizontal: 24, paddingTop: 20, paddingBottom: 16 },
  statRow: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 16 },
  stat: { alignItems: 'center' },
  statValue: { fontSize: 22, fontWeight: '800', color: '#fff' },
  statLabel: { fontSize: 11, color: '#aaa', marginTop: 2 },
  divider: { height: 1, backgroundColor: 'rgba(255,255,255,0.15)', marginBottom: 14 },
  footer: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  appName: { fontSize: 15, fontWeight: '800', color: '#fff' },
  brand: { fontSize: 11, color: '#1a6b3c', fontWeight: '600' },
  bottomBar: { height: 8, backgroundColor: '#1a6b3c' },
});
