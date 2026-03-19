import { useState, useEffect, useRef } from 'react';
import { StyleSheet, Text, View, TouchableOpacity, SafeAreaView, FlatList, Alert, TextInput, KeyboardAvoidingView, Platform } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as Location from 'expo-location';
import MapView, { Polyline } from 'react-native-maps';
import AsyncStorage from '@react-native-async-storage/async-storage';
let AppleHealthKit = null;
try { AppleHealthKit = require('react-native-health').default; } catch (_) {}

const HK_ACTIVITY = { Run: 'Running', Walk: 'Walking', Ruck: 'Hiking' };

const STORAGE_KEY = 'simple_run_history';
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
  return Math.round(meters * 3.28084); // to feet
}

function activityLabel(type, ruckWeight) {
  if (type === 'Ruck' && ruckWeight) return `Ruck (${ruckWeight} lbs)`;
  return type || 'Run';
}

function calcEffortScore(perceivedValue, distance, elapsed, elevGain, ruckWeight) {
  let score = perceivedValue;

  // Pace bonus/penalty (minutes per mile)
  if (distance > 10 && elapsed > 0) {
    const miles = distance / 1609.34;
    const pace = elapsed / 60 / miles;
    if (pace < 9) score += 1;
    else if (pace > 14) score -= 1;
  }

  // Elevation bonus (+1 per 200ft gain)
  const elevFt = elevGain * 3.28084;
  score += Math.floor(elevFt / 200);

  // Ruck weight bonus (+1 per 20 lbs)
  if (ruckWeight) score += Math.floor(parseFloat(ruckWeight) / 20);

  return Math.min(10, Math.max(1, Math.round(score)));
}

// --- Screens ---

function RunScreen({ onViewHistory }) {
  const [status, setStatus] = useState('idle'); // idle | running | rating | done
  const [activity, setActivity] = useState('Run');
  const [ruckWeight, setRuckWeight] = useState('');
  const [coords, setCoords] = useState([]);
  const [distance, setDistance] = useState(0);
  const [elapsed, setElapsed] = useState(0);
  const [elevGain, setElevGain] = useState(0);
  const [lastAlt, setLastAlt] = useState(null);
  const [runs, setRuns] = useState([]);
  const [pendingRun, setPendingRun] = useState(null);

  const locationSub = useRef(null);
  const timerRef = useRef(null);
  const mapRef = useRef(null);
  const startTimeRef = useRef(null);

  useEffect(() => {
    loadRuns();
    centerOnUser();
    try {
      AppleHealthKit?.initHealthKit({
        permissions: {
          read: [AppleHealthKit.Constants.Permissions.Workout],
          write: [AppleHealthKit.Constants.Permissions.Workout],
        },
      }, () => {});
    } catch (_) {}
    return () => stopTracking();
  }, []);

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
    const { status: permStatus } = await Location.requestForegroundPermissionsAsync();
    if (permStatus !== 'granted') {
      Alert.alert('Location Required', 'Enable location access to track your activity.');
      return;
    }
    setCoords([]);
    setDistance(0);
    setElapsed(0);
    setElevGain(0);
    setLastAlt(null);
    setStatus('running');
    startTimeRef.current = Date.now();
    timerRef.current = setInterval(() => {
      setElapsed(Math.floor((Date.now() - startTimeRef.current) / 1000));
    }, 1000);
    locationSub.current = await Location.watchPositionAsync(
      { accuracy: Location.Accuracy.BestForNavigation, distanceInterval: 5 },
      (loc) => {
        const point = { latitude: loc.coords.latitude, longitude: loc.coords.longitude };
        const alt = loc.coords.altitude;
        setCoords((prev) => {
          const next = [...prev, point];
          if (prev.length > 0) {
            setDistance((d) => d + haversineDistance(prev[prev.length - 1], point));
          }
          mapRef.current?.animateCamera({
            center: point,
            heading: loc.coords.heading ?? 0,
            pitch: 0,
            zoom: 17,
          }, { duration: 500 });
          return next;
        });
        if (alt != null) {
          setLastAlt((prev) => {
            if (prev != null && alt > prev + 0.5) {
              setElevGain((g) => g + (alt - prev));
            }
            return alt;
          });
        }
      }
    );
  }

  function stopTracking() {
    locationSub.current?.remove();
    locationSub.current = null;
    clearInterval(timerRef.current);
  }

  function finishRun() {
    stopTracking();
    if (coords.length > 1) {
      mapRef.current?.fitToCoordinates(coords, {
        edgePadding: { top: 40, right: 40, bottom: 40, left: 40 },
        animated: true,
      });
    }
    setPendingRun({
      id: Date.now(),
      date: new Date().toLocaleDateString(),
      activity,
      ruckWeight: activity === 'Ruck' ? ruckWeight : null,
      distance,
      elapsed,
      elevGain,
      coords,
      startTime: startTimeRef.current,
      endTime: Date.now(),
    });
    setStatus('rating');
  }

  async function submitRating(perceivedValue, label) {
    const score = calcEffortScore(perceivedValue, pendingRun.distance, pendingRun.elapsed, pendingRun.elevGain, pendingRun.ruckWeight);
    const run = { ...pendingRun, perceived: label, effortScore: score };
    await saveRun(run);
    try {
      AppleHealthKit?.saveWorkout({
        type: HK_ACTIVITY[run.activity] ?? 'Running',
        startDate: new Date(run.startTime).toISOString(),
        endDate: new Date(run.endTime).toISOString(),
        distance: run.distance / 1609.34,
        distanceUnit: 'mile',
      }, (err, result) => {
        if (err) console.log('[HealthKit] saveWorkout error:', err);
        else console.log('[HealthKit] saveWorkout success:', result);
      });
    } catch (_) {}
    setStatus('done');
  }

  function resetRun() {
    setStatus('idle');
    setCoords([]);
    setDistance(0);
    setElapsed(0);
    setElevGain(0);
    setLastAlt(null);
    setRuckWeight('');
    setPendingRun(null);
  }

  const initialRegion = {
    latitude: coords[0]?.latitude ?? 37.78825,
    longitude: coords[0]?.longitude ?? -122.4324,
    latitudeDelta: 0.01,
    longitudeDelta: 0.01,
  };

  // Rating screen
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
          <View style={styles.row}>
            <TouchableOpacity style={[styles.btn, styles.btnSecondary]} onPress={resetRun}>
              <Text style={styles.btnText}>New Activity</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.btn, styles.btnPrimary, { flex: 1 }]} onPress={onViewHistory}>
              <Text style={styles.btnText}>History</Text>
            </TouchableOpacity>
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
    </SafeAreaView>
  );
}

function HistoryScreen({ onBack }) {
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
            <View style={styles.runCard}>
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
                </View>
              )}
            </View>
          )}
        />
      )}
    </SafeAreaView>
  );
}

// --- Root ---

export default function App() {
  const [screen, setScreen] = useState('run');
  return screen === 'run'
    ? <RunScreen onViewHistory={() => setScreen('history')} />
    : <HistoryScreen onBack={() => setScreen('run')} />;
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
});
