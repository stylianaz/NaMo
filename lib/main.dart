import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const NaMoApp());
}

class NaMoApp extends StatelessWidget {
  const NaMoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NaMo Study Prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Enums and data classes
// ---------------------------------------------------------------------------

enum FeedbackCondition {
  visualAudio,
  visualHaptic,
}

class VirtualPoint {
  final double x;
  final double y;

  const VirtualPoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class SegmentProjection {
  final double t;
  final double distanceToSegment;
  final VirtualPoint closestPoint;

  const SegmentProjection({
    required this.t,
    required this.distanceToSegment,
    required this.closestPoint,
  });
}

class RouteStep {
  final VirtualPoint point;
  final String instruction;
  final String maneuver;

  const RouteStep({
    required this.point,
    required this.instruction,
    required this.maneuver,
  });

  Map<String, dynamic> toJson() => {
        'point': point.toJson(),
        'instruction': instruction,
        'maneuver': maneuver,
      };
}

class StudyRoute {
  final String id;
  final List<RouteStep> steps;

  const StudyRoute({required this.id, required this.steps});

  List<VirtualPoint> get points => steps.map((s) => s.point).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

class StudyEvent {
  final String type;
  final DateTime timestamp;
  final int stepIndex;

  StudyEvent({
    required this.type,
    required this.timestamp,
    required this.stepIndex,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'stepIndex': stepIndex,
      };
}

class RouteSession {
  final String participantId;
  final String routeId;
  final String condition;
  final DateTime startTime;
  DateTime? endTime;
  bool completed;
  int currentStep;
  final List<StudyEvent> events;

  RouteSession({
    required this.participantId,
    required this.routeId,
    required this.condition,
    required this.startTime,
    this.endTime,
    this.completed = false,
    this.currentStep = 0,
    required this.events,
  });

  int? get completionTimeSeconds {
    if (endTime == null) return null;
    return endTime!.difference(startTime).inSeconds;
  }

  Map<String, dynamic> toJson() => {
        'participantId': participantId,
        'routeId': routeId,
        'condition': condition,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'completionTimeSeconds': completionTimeSeconds,
        'completed': completed,
        'currentStep': currentStep,
        'events': events.map((e) => e.toJson()).toList(),
      };
}

// ---------------------------------------------------------------------------
// Routes
// Coordinates are virtual metres east (x) and north (y) from origin (0,0).
// Segments are intentionally varied with realistic street-block proportions
// (~15–40 m per leg), avoiding pure straight lines.
// ---------------------------------------------------------------------------

const routeA = StudyRoute(
  id: 'Route A',
  steps: [
    RouteStep(
      point: VirtualPoint(0, 0),
      instruction: 'Start – walk straight ahead',
      maneuver: 'straight',
    ),
    RouteStep(
      point: VirtualPoint(0, 35),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(30, 35),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(30, 60),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(55, 60),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(55, 85),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(80, 85),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(80, 60),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(105, 60),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(105, 35),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(70, 35),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(70, 10),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(40, 10),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(40, 40),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(15, 40),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(15, 70),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(0, 70),
      instruction: 'Arrive at destination',
      maneuver: 'arrive',
    ),
  ],
);

const routeB = StudyRoute(
  id: 'Route B',
  steps: [
    RouteStep(
      point: VirtualPoint(0, 0),
      instruction: 'Start – walk straight ahead',
      maneuver: 'straight',
    ),
    RouteStep(
      point: VirtualPoint(30, 0),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(30, 30),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(60, 30),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(60, 60),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(90, 60),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(90, 85),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(60, 85),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(60, 110),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(90, 110),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(90, 80),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(110, 80),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(110, 50),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(80, 50),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(80, 20),
      instruction: 'Turn right',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(50, 20),
      instruction: 'Turn left',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(50, 0),
      instruction: 'Arrive at destination',
      maneuver: 'arrive',
    ),
  ],
);

// ---------------------------------------------------------------------------
// Home screen
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String participantId = '';
  int selectedOrder = 0;

  @override
  void initState() {
    super.initState();
    participantId = _generateParticipantId();
  }

  String _generateParticipantId() {
    final now = DateTime.now();
    return 'P${now.millisecondsSinceEpoch.toString().substring(7)}';
  }

  void _generateNewId() {
    setState(() {
      participantId = _generateParticipantId();
    });
  }

  void _startStudy() {
    final routeOrder =
        selectedOrder == 0 ? [routeA, routeB] : [routeB, routeA];
    final conditionOrder = selectedOrder == 0
        ? [FeedbackCondition.visualAudio, FeedbackCondition.visualHaptic]
        : [FeedbackCondition.visualHaptic, FeedbackCondition.visualAudio];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyMapScreen(
          participantId: participantId,
          routeOrder: routeOrder,
          conditionOrder: conditionOrder,
          routeIndex: 0,
          allSessionLogs: const [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeOrderText =
        selectedOrder == 0 ? 'Route A → Route B' : 'Route B → Route A';
    final conditionOrderText = selectedOrder == 0
        ? 'Visual + Audio → Visual + Haptic'
        : 'Visual + Haptic → Visual + Audio';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('NaMo Study Setup'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Generated Participant ID',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      participantId,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _generateNewId,
                      child: const Text('Generate New ID'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              elevation: 2,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Counterbalancing Order',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedOrder,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Study order',
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Order 1')),
                        DropdownMenuItem(value: 1, child: Text('Order 2')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedOrder = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Route order: $routeOrderText'),
                    Text('Condition order: $conditionOrderText'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _startStudy,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Start Study',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Study map screen
// ---------------------------------------------------------------------------

class StudyMapScreen extends StatefulWidget {
  final String participantId;
  final List<StudyRoute> routeOrder;
  final List<FeedbackCondition> conditionOrder;
  final int routeIndex;
  final List<Map<String, dynamic>> allSessionLogs;

  const StudyMapScreen({
    super.key,
    required this.participantId,
    required this.routeOrder,
    required this.conditionOrder,
    required this.routeIndex,
    required this.allSessionLogs,
  });

  @override
  State<StudyMapScreen> createState() => _StudyMapScreenState();
}

class _StudyMapScreenState extends State<StudyMapScreen> {
  // ── Services ──────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Location _locationService = Location();

  StreamSubscription<LocationData>? _locationSubscription;

  // ── Study setup ───────────────────────────────────────────────────────────
  late StudyRoute currentRoute;
  late FeedbackCondition currentCondition;
  late RouteSession session;

  // ── Navigation constants (spec §13) ───────────────────────────────────────
  static const double waypointReachRadius = 6.0;
  static const double offRouteThreshold = 10.0;
  static const double turnCueDistance = 12.0;
  static const double missedTurnDistance = 10.0;
  static const double continueCueMinSeconds = 4.0;
  static const double sameCueCooldownSeconds = 4.0;
  static const double wrongCueCooldownSeconds = 4.0;

  // ── Map / GPS state ───────────────────────────────────────────────────────
  final LatLng fallbackCenter = const LatLng(52.0907, 5.1214);

  LatLng? origin;
  LatLng? currentLocation;
  LatLng? _mapCenter;

  List<LatLng> studyBoundary = [];
  List<LatLng> fakeRoutePoints = [];
  List<LatLng> userPath = [];

  double userX = 0.0;
  double userY = 0.0;
  double currentSpeedKmh = 0.0;
  double? currentHeadingDegrees;
  double? currentAccuracyMeters;
  double _currentZoom = 19.5;

  // ── Route progress state ──────────────────────────────────────────────────
  int currentStep = 0;

  bool routeStarted = false;
  bool gpsTrackingActive = false;
  bool simulatedMode = false;
  bool studyAreaCreated = false;
  bool waitingForGps = false;
  bool realtimeCuesEnabled = true;

  String gpsStatus = 'Stand at the start point, then set origin.';

  // ── Cue cooldowns ─────────────────────────────────────────────────────────
  // Global interlock: prevents any two cues overlapping within ~900 ms.
  DateTime? _lastAnyCueTime;
  // Per-type cooldowns.
  DateTime? _lastStraightCueTime;
  DateTime? _lastTurnCueTime;
  DateTime? _lastWrongCueTime;
  // Tracks which waypoint index the last turn cue was for.
  int? _lastTurnCueWaypointIndex;

  // ── Logging ───────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> pathFollowed = [];

  // ── Researcher controls visibility ────────────────────────────────────────
  bool _controlsVisible = true;

  // ── Study boundary size in metres ─────────────────────────────────────────
  static const double studySizeMeters = 130.0;

  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    currentRoute = widget.routeOrder[widget.routeIndex];
    currentCondition = widget.conditionOrder[widget.routeIndex];
    session = RouteSession(
      participantId: widget.participantId,
      routeId: currentRoute.id,
      condition: _conditionToText(currentCondition),
      startTime: DateTime.now(),
      events: [],
    );
    _logEvent('route_screen_opened');
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _conditionToText(FeedbackCondition c) {
    switch (c) {
      case FeedbackCondition.visualAudio:
        return 'Visual + Audio';
      case FeedbackCondition.visualHaptic:
        return 'Visual + Haptic';
    }
  }

  String _currentInstruction() {
    if (!routeStarted) {
      return waitingForGps ? 'Waiting for GPS' : 'Set study origin';
    }
    if (currentStep >= currentRoute.steps.length) {
      return 'Arrive at destination';
    }
    return currentRoute.steps[currentStep].instruction;
  }

  IconData _currentIcon() {
    if (!routeStarted) {
      return waitingForGps ? Icons.gps_not_fixed : Icons.gps_fixed;
    }
    if (currentStep >= currentRoute.steps.length) return Icons.flag;
    switch (currentRoute.steps[currentStep].maneuver) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'straight':
        return Icons.straight;
      case 'arrive':
        return Icons.flag;
      default:
        return Icons.navigation;
    }
  }

  void _logEvent(String type) {
    session.events.add(StudyEvent(
      type: type,
      timestamp: DateTime.now(),
      stepIndex: currentStep,
    ));
  }

  // ---------------------------------------------------------------------------
  // GPS / location setup
  // ---------------------------------------------------------------------------

  Future<void> _startRouteAndSetOrigin() async {
    setState(() {
      gpsStatus = 'Checking location permission…';
      routeStarted = false;
      waitingForGps = true;
    });

    final canUse = await _checkAndRequestLocationPermission();
    if (!canUse) {
      setState(() {
        waitingForGps = false;
        gpsStatus = 'Location permission denied or service disabled.';
      });
      _logEvent('location_permission_or_service_failed');
      return;
    }

    setState(() {
      gpsStatus = 'Waiting for first GPS update… Keep this tab active.';
    });

    await _waitForFirstLocationFromStream();
  }

  Future<bool> _checkAndRequestLocationPermission() async {
    try {
      if (kIsWeb) {
        await _locationService.changeSettings(
          accuracy: LocationAccuracy.high,
          interval: 1000,
          distanceFilter: 1,
        );
        return true;
      }

      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        if (!serviceEnabled) {
          _logEvent('gps_service_disabled');
          return false;
        }
      }

      PermissionStatus permission = await _locationService.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _locationService.requestPermission();
      }
      if (permission != PermissionStatus.granted &&
          permission != PermissionStatus.grantedLimited) {
        _logEvent('gps_permission_denied');
        return false;
      }

      await _locationService.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 1000,
        distanceFilter: 1,
      );
      return true;
    } catch (e) {
      debugPrint('LOCATION: permission check failed: $e');
      _logEvent('gps_permission_check_failed');
      return false;
    }
  }

  Future<void> _waitForFirstLocationFromStream() async {
    await _locationSubscription?.cancel();
    bool firstReceived = false;

    _locationSubscription = _locationService.onLocationChanged.listen(
      (LocationData data) {
        if (data.latitude == null || data.longitude == null) {
          if (mounted) {
            setState(() => gpsStatus = 'GPS update: lat/lng is null.');
          }
          return;
        }
        final pos = LatLng(data.latitude!, data.longitude!);
        if (!firstReceived) {
          firstReceived = true;
          _startGpsMode(pos, data);
        } else {
          _handleLocationUpdate(data);
        }
      },
      onError: (e) {
        debugPrint('LOCATION: stream error: $e');
        if (!mounted) return;
        setState(() {
          waitingForGps = false;
          gpsTrackingActive = false;
          gpsStatus = 'GPS stream error: $e';
        });
        _logEvent('location_stream_error');
      },
    );

    Future.delayed(const Duration(seconds: 30), () {
      if (!mounted || firstReceived) return;
      setState(() {
        waitingForGps = false;
        gpsStatus = 'Still waiting for GPS. Check browser permission or test on phone.';
      });
      _logEvent('gps_first_location_timeout_30s');
    });
  }

  void _startGpsMode(LatLng start, LocationData initialData) {
    origin = start;
    currentLocation = start;
    _mapCenter = start;
    studyBoundary = _createStudyBoundary(start);
    fakeRoutePoints = _createFakeRoute(start, currentRoute.points);

    setState(() {
      routeStarted = true;
      studyAreaCreated = true;
      gpsTrackingActive = true;
      simulatedMode = false;
      waitingForGps = false;
      currentStep = 0;
      session.currentStep = 0;
      userX = 0.0;
      userY = 0.0;
      currentSpeedKmh = (initialData.speed ?? 0.0) * 3.6;
      currentHeadingDegrees = initialData.heading;
      currentAccuracyMeters = initialData.accuracy;
      userPath = [start];
      pathFollowed.add({
        'timestamp': DateTime.now().toIso8601String(),
        'mode': 'gps_origin',
        'lat': start.latitude,
        'lng': start.longitude,
        'virtualX': 0.0,
        'virtualY': 0.0,
        'speedKmh': currentSpeedKmh,
        'accuracy': initialData.accuracy,
        'heading': initialData.heading,
        'stepIndex': currentStep,
      });
      gpsStatus =
          'GPS active. Accuracy: ±${(initialData.accuracy ?? 0).toStringAsFixed(1)} m';
    });

    _logEvent('gps_origin_set');
    _logEvent('study_area_created');
    _logEvent('gps_mode_started');
    _currentZoom = 19.5;
    _mapController.move(start, _currentZoom);
  }

  void _handleLocationUpdate(LocationData data) {
    if (origin == null) return;
    if (data.latitude == null || data.longitude == null) return;

    final pos = LatLng(data.latitude!, data.longitude!);
    final virtual = _latLngToVirtual(origin!, pos);
    final accuracy = data.accuracy ?? 0.0;

    setState(() {
      currentLocation = pos;
      userX = virtual.x;
      userY = virtual.y;
      currentSpeedKmh = (data.speed ?? 0.0) * 3.6;
      currentHeadingDegrees = data.heading;
      currentAccuracyMeters = accuracy;
      userPath.add(pos);
      pathFollowed.add({
        'timestamp': DateTime.now().toIso8601String(),
        'mode': 'gps',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'virtualX': userX,
        'virtualY': userY,
        'speedKmh': currentSpeedKmh,
        'accuracy': accuracy,
        'heading': data.heading,
        'stepIndex': currentStep,
      });
      gpsStatus =
          'GPS: x=${userX.toStringAsFixed(1)}, y=${userY.toStringAsFixed(1)}'
          ', ±${accuracy.toStringAsFixed(1)} m'
          ', hdg=${data.heading?.toStringAsFixed(0) ?? '-'}°';
    });

    // Real-time cue engine runs on every location update (spec §1).
    if (realtimeCuesEnabled) {
      _evaluateRealtimeNavigationCues();
    }
  }

  void _startSimulatedMode({required String reason}) {
    _locationSubscription?.cancel();
    origin = fallbackCenter;
    currentLocation = _offsetMetersToLatLng(fallbackCenter, 0, 0);
    _mapCenter = currentLocation;
    studyBoundary = _createStudyBoundary(fallbackCenter);
    fakeRoutePoints = _createFakeRoute(fallbackCenter, currentRoute.points);

    setState(() {
      routeStarted = true;
      studyAreaCreated = true;
      gpsTrackingActive = false;
      simulatedMode = true;
      waitingForGps = false;
      currentStep = 0;
      session.currentStep = 0;
      userX = 0.0;
      userY = 0.0;
      currentSpeedKmh = 0.0;
      currentHeadingDegrees = null;
      currentAccuracyMeters = null;
      userPath = [currentLocation!];
      gpsStatus = reason;
    });

    _logEvent('simulated_mode_started');
    _logEvent('study_area_created_fallback');
    _currentZoom = 19.5;
    _mapController.move(fallbackCenter, _currentZoom);
  }

  // ---------------------------------------------------------------------------
  // Coordinate utilities
  // ---------------------------------------------------------------------------

  LatLng _offsetMetersToLatLng(
    LatLng orig,
    double eastMeters,
    double northMeters,
  ) {
    const earthRadius = 6378137.0;
    final dLat = northMeters / earthRadius;
    final dLng =
        eastMeters / (earthRadius * math.cos(math.pi * orig.latitude / 180.0));
    return LatLng(
      orig.latitude + dLat * 180.0 / math.pi,
      orig.longitude + dLng * 180.0 / math.pi,
    );
  }

  VirtualPoint _latLngToVirtual(LatLng orig, LatLng current) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        111320.0 * math.cos(orig.latitude * math.pi / 180.0);
    final x = (current.longitude - orig.longitude) * metersPerDegreeLng;
    final y = (current.latitude - orig.latitude) * metersPerDegreeLat;
    return VirtualPoint(x, y);
  }

  List<LatLng> _createStudyBoundary(LatLng orig) => [
        _offsetMetersToLatLng(orig, 0, 0),
        _offsetMetersToLatLng(orig, studySizeMeters, 0),
        _offsetMetersToLatLng(orig, studySizeMeters, studySizeMeters),
        _offsetMetersToLatLng(orig, 0, studySizeMeters),
      ];

  List<LatLng> _createFakeRoute(LatLng orig, List<VirtualPoint> pts) =>
      pts.map((p) => _offsetMetersToLatLng(orig, p.x, p.y)).toList();

  // ---------------------------------------------------------------------------
  // Map controls
  // ---------------------------------------------------------------------------

  void _goToCurrentLocation() {
    if (currentLocation == null) return;
    _mapCenter = currentLocation;
    _currentZoom = 20.5;
    _mapController.move(currentLocation!, _currentZoom);
  }

  void _zoomIn() {
    final center = _mapCenter ?? currentLocation ?? origin ?? fallbackCenter;
    _currentZoom = (_currentZoom + 0.75).clamp(3.0, 22.0);
    _mapCenter = center;
    _mapController.move(center, _currentZoom);
  }

  void _zoomOut() {
    final center = _mapCenter ?? currentLocation ?? origin ?? fallbackCenter;
    _currentZoom = (_currentZoom - 0.75).clamp(3.0, 22.0);
    _mapCenter = center;
    _mapController.move(center, _currentZoom);
  }

  void _recalculateStudyAreaFromCurrentLocation() {
    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No current GPS point available yet.')),
      );
      return;
    }
    final newOrigin = currentLocation!;
    origin = newOrigin;
    studyBoundary = _createStudyBoundary(newOrigin);
    fakeRoutePoints = _createFakeRoute(newOrigin, currentRoute.points);

    setState(() {
      currentStep = 0;
      session.currentStep = 0;
      userX = 0.0;
      userY = 0.0;
      userPath = [newOrigin];
      _resetCueCooldowns();
      gpsStatus = 'Study area recalculated. Current GPS point is now (0, 0).';
    });

    pathFollowed.add({
      'timestamp': DateTime.now().toIso8601String(),
      'mode': simulatedMode
          ? 'simulated_recalculated_origin'
          : 'gps_recalculated_origin',
      'lat': newOrigin.latitude,
      'lng': newOrigin.longitude,
      'virtualX': 0.0,
      'virtualY': 0.0,
      'accuracy': currentAccuracyMeters,
      'heading': currentHeadingDegrees,
      'stepIndex': 0,
    });

    _logEvent('study_area_recalculated_from_current_location');
    _mapCenter = newOrigin;
    _currentZoom = 19.5;
    _mapController.move(newOrigin, _currentZoom);
  }

  // ---------------------------------------------------------------------------
  // Real-time cue toggle
  // ---------------------------------------------------------------------------

  void _toggleRealtimeCues() {
    setState(() {
      realtimeCuesEnabled = !realtimeCuesEnabled;
      if (!realtimeCuesEnabled) _resetCueCooldowns();
    });
    _logEvent(
      realtimeCuesEnabled ? 'realtime_cues_enabled' : 'realtime_cues_disabled',
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        realtimeCuesEnabled
            ? 'Real-time cues enabled'
            : 'Real-time cues disabled. Manual controls still work.',
      ),
    ));
  }

  void _resetCueCooldowns() {
    _lastStraightCueTime = null;
    _lastTurnCueTime = null;
    _lastWrongCueTime = null;
    _lastTurnCueWaypointIndex = null;
  }

  // ---------------------------------------------------------------------------
  // Geometry helpers
  // ---------------------------------------------------------------------------

  double _distanceBetweenVirtual(VirtualPoint a, VirtualPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  SegmentProjection _projectPointToSegment(
    VirtualPoint p,
    VirtualPoint a,
    VirtualPoint b,
  ) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;

    if (dx == 0 && dy == 0) {
      return SegmentProjection(
        t: 0.0,
        distanceToSegment: _distanceBetweenVirtual(p, a),
        closestPoint: a,
      );
    }

    final rawT =
        ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy);
    final t = rawT.clamp(0.0, 1.0).toDouble();

    final cx = a.x + t * dx;
    final cy = a.y + t * dy;
    final distX = p.x - cx;
    final distY = p.y - cy;

    return SegmentProjection(
      t: rawT,
      distanceToSegment: math.sqrt(distX * distX + distY * distY),
      closestPoint: VirtualPoint(cx, cy),
    );
  }

  bool _cooldownReady(DateTime? last, double seconds) {
    if (last == null) return true;
    return DateTime.now().difference(last).inMilliseconds / 1000.0 >= seconds;
  }

  String _nextManeuver() {
    if (currentStep + 1 >= currentRoute.steps.length) return 'arrive';
    return currentRoute.steps[currentStep + 1].maneuver;
  }

  // ---------------------------------------------------------------------------
  // ═══ REAL-TIME CUE ENGINE (spec §10–§14) ════════════════════════════════
  //
  // Called from _handleLocationUpdate() on every GPS fix while enabled.
  // This is the single authoritative source of automatic cues.
  // ---------------------------------------------------------------------------

  void _evaluateRealtimeNavigationCues() {
    if (!routeStarted) return;

    // Already at or past the final waypoint.
    if (currentStep >= currentRoute.points.length - 1) return;

    // Skip if GPS accuracy is too poor to be useful.
    if (currentAccuracyMeters != null && currentAccuracyMeters! > 25.0) {
      _logEvent('gps_accuracy_too_low_for_realtime_cues');
      return;
    }

    final user = VirtualPoint(userX, userY);
    final segStart = currentRoute.points[currentStep];
    final segEnd = currentRoute.points[currentStep + 1];

    final proj = _projectPointToSegment(user, segStart, segEnd);
    final distToSeg = proj.distanceToSegment;
    final distToNext = _distanceBetweenVirtual(user, segEnd);

    final now = DateTime.now();

    // ── 1. Off-route / wrong path ─────────────────────────────────────────
    if (distToSeg > offRouteThreshold) {
      if (_cooldownReady(_lastWrongCueTime, wrongCueCooldownSeconds)) {
        _lastWrongCueTime = now;
        _logEvent('off_route_wrong_path_detected');
        _playCue('wrong');
      }
      return;
    }

    // ── 2. Missed turn (user shot past the waypoint without turning) ───────
    // proj.t > 1.15 means the user is clearly beyond the segment end.
    if (proj.t > 1.15 && distToNext > missedTurnDistance) {
      if (_cooldownReady(_lastWrongCueTime, wrongCueCooldownSeconds)) {
        _lastWrongCueTime = now;
        _logEvent('missed_turn_detected');
        _playCue('wrong');
      }
      return;
    }

    // ── 3. Waypoint reached → advance step ───────────────────────────────
    if (distToNext <= waypointReachRadius) {
      setState(() {
        currentStep++;
        session.currentStep = currentStep;
        _lastTurnCueWaypointIndex = null;
      });
      _logEvent('realtime_reached_waypoint');

      if (currentStep >= currentRoute.points.length - 1) {
        _playCue('arrive');
        _logEvent('realtime_route_arrived');
      }
      return;
    }

    // ── 4. Turn-approach cue ──────────────────────────────────────────────
    final nextMan = _nextManeuver();
    final approachingTurn = distToNext <= turnCueDistance &&
        (nextMan == 'left' || nextMan == 'right');

    if (approachingTurn) {
      final targetWaypoint = currentStep + 1;
      final isNewTarget = _lastTurnCueWaypointIndex != targetWaypoint;

      if (isNewTarget ||
          _cooldownReady(_lastTurnCueTime, sameCueCooldownSeconds)) {
        _lastTurnCueTime = now;
        _lastTurnCueWaypointIndex = targetWaypoint;
        _logEvent('realtime_turn_cue_$nextMan');
        _playCue(nextMan);
      }
      return;
    }

    // ── 5. Straight / continue cue ────────────────────────────────────────
    if (_cooldownReady(_lastStraightCueTime, continueCueMinSeconds)) {
      _lastStraightCueTime = now;
      _logEvent('realtime_straight_cue');
      _playCue('straight');
    }
  }

  // ---------------------------------------------------------------------------
  // Cue dispatch (audio or haptic)
  // ---------------------------------------------------------------------------

  Future<void> _playCue(String maneuver) async {
    // Global interlock: no two cues within 900 ms.
    final now = DateTime.now();
    if (_lastAnyCueTime != null &&
        now.difference(_lastAnyCueTime!).inMilliseconds < 900) {
      return;
    }
    _lastAnyCueTime = now;
    _logEvent('cue_played_$maneuver');

    if (currentCondition == FeedbackCondition.visualAudio) {
      await _playAudioCue(maneuver);
    } else {
      await _playHapticCue(maneuver);
    }
  }

  Future<void> _playAudioCue(String maneuver) async {
    switch (maneuver) {
      case 'straight':
        // One short high beep.
        await _playBeep(frequency: 880, durationMs: 120);
        break;
      case 'left':
        // Two short high beeps.
        await _playBeep(frequency: 880, durationMs: 100);
        await Future.delayed(const Duration(milliseconds: 120));
        await _playBeep(frequency: 880, durationMs: 100);
        break;
      case 'right':
        // One longer lower beep.
        await _playBeep(frequency: 660, durationMs: 350);
        break;
      case 'wrong':
        // Three fast low warning beeps.
        for (int i = 0; i < 3; i++) {
          await _playBeep(frequency: 440, durationMs: 100);
          if (i < 2) await Future.delayed(const Duration(milliseconds: 80));
        }
        break;
      case 'arrive':
        // Two rising beeps.
        await _playBeep(frequency: 1000, durationMs: 120);
        await Future.delayed(const Duration(milliseconds: 90));
        await _playBeep(frequency: 1200, durationMs: 160);
        break;
    }
  }

  Future<void> _playHapticCue(String maneuver) async {
    switch (maneuver) {
      case 'straight':
        // One light pulse.
        await HapticFeedback.lightImpact();
        break;
      case 'left':
        // Two light pulses.
        await HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.lightImpact();
        break;
      case 'right':
        // One medium pulse.
        await HapticFeedback.mediumImpact();
        break;
      case 'wrong':
        // Two heavy pulses.
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        await HapticFeedback.heavyImpact();
        break;
      case 'arrive':
        // Two medium pulses.
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.mediumImpact();
        break;
    }
  }

  Future<void> _playBeep({
    required int frequency,
    required int durationMs,
  }) async {
    final wav = _generateBeepWav(frequency: frequency, durationMs: durationMs);
    await _audioPlayer.stop();
    await _audioPlayer.play(BytesSource(wav));
  }

  // ---------------------------------------------------------------------------
  // Manual researcher controls
  // ---------------------------------------------------------------------------

  void _manualReachedPoint() {
    if (!routeStarted) return;

    final isLastStep = currentStep >= currentRoute.points.length - 1;
    if (isLastStep) {
      _logEvent('manual_finish_route');
      _playCue('arrive');
      _endRoute(completed: true);
      return;
    }

    setState(() {
      currentStep++;
      session.currentStep = currentStep;
      if (simulatedMode && origin != null) {
        final p = currentRoute.points[currentStep];
        userX = p.x;
        userY = p.y;
        currentLocation = _offsetMetersToLatLng(origin!, userX, userY);
        userPath.add(currentLocation!);
        pathFollowed.add({
          'timestamp': DateTime.now().toIso8601String(),
          'mode': 'simulated',
          'virtualX': userX,
          'virtualY': userY,
          'stepIndex': currentStep,
        });
      }
    });

    _logEvent('manual_reached_point');
    _playCue(currentRoute.steps[currentStep].maneuver);
  }

  void _markError(String type) {
    if (!routeStarted) return;
    _logEvent('manual_$type');
    _playCue('wrong');
  }

  void _manualCue(String cue) {
    if (!routeStarted) return;
    _logEvent('manual_cue_$cue');
    _playCue(cue);
  }

  // ---------------------------------------------------------------------------
  // End of route
  // ---------------------------------------------------------------------------

  Future<void> _endRoute({required bool completed}) async {
    await _locationSubscription?.cancel();

    session.endTime = DateTime.now();
    session.completed = completed;
    session.currentStep = currentStep;

    _logEvent(completed ? 'route_completed' : 'route_terminated');

    final sessionJson = session.toJson();
    sessionJson['routeDefinition'] = currentRoute.toJson();
    sessionJson['origin'] = origin == null
        ? null
        : {'lat': origin!.latitude, 'lng': origin!.longitude};
    sessionJson['trackingMode'] = simulatedMode ? 'simulated' : 'gps';
    sessionJson['pathFollowed'] = pathFollowed;
    sessionJson['gpsTrackingActive'] = gpsTrackingActive;
    sessionJson['gpsStatusAtEnd'] = gpsStatus;
    sessionJson['finalAccuracyMeters'] = currentAccuracyMeters;
    sessionJson['finalHeadingDegrees'] = currentHeadingDegrees;
    sessionJson['finalVirtualPosition'] = {'x': userX, 'y': userY};
    sessionJson['realtimeCuesEnabledAtEnd'] = realtimeCuesEnabled;

    final updatedLogs = [...widget.allSessionLogs, sessionJson];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'namo_${widget.participantId}',
      jsonEncode(updatedLogs),
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryScreen(
          participantId: widget.participantId,
          routeOrder: widget.routeOrder,
          conditionOrder: widget.conditionOrder,
          finishedRouteIndex: widget.routeIndex,
          allSessionLogs: updatedLogs,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final center = currentLocation ?? origin ?? fallbackCenter;

    final markers = <Marker>[
      if (currentLocation != null)
        Marker(
          point: currentLocation!,
          width: 72,
          height: 72,
          child: _UserLocationMarker(
            headingDegrees: currentHeadingDegrees,
            isGpsActive: gpsTrackingActive && !simulatedMode,
          ),
        ),
      if (fakeRoutePoints.isNotEmpty)
        Marker(
          point: fakeRoutePoints.first,
          width: 50,
          height: 50,
          child: const Icon(Icons.location_on, color: Colors.green, size: 34),
        ),
      if (fakeRoutePoints.length > 1 && currentStep < fakeRoutePoints.length)
        Marker(
          point: fakeRoutePoints[currentStep],
          width: 50,
          height: 50,
          child: const Icon(Icons.adjust, color: Colors.orange, size: 30),
        ),
      if (fakeRoutePoints.isNotEmpty)
        Marker(
          point: fakeRoutePoints.last,
          width: 50,
          height: 50,
          child: const Icon(Icons.flag, color: Colors.red, size: 34),
        ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _currentZoom,
              minZoom: 3,
              maxZoom: 22,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapEvent: (event) {
                _mapCenter = event.camera.center;
                _currentZoom = event.camera.zoom;
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.namo',
              ),
              if (studyBoundary.length >= 3)
                PolygonLayer(polygons: [
                  Polygon(
                    points: studyBoundary,
                    color: Colors.blue.withOpacity(0.10),
                    borderColor: Colors.blueAccent,
                    borderStrokeWidth: 4,
                  ),
                ]),
              if (fakeRoutePoints.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: fakeRoutePoints,
                    strokeWidth: 6,
                    color: Colors.black,
                  ),
                ]),
              if (userPath.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: userPath,
                    strokeWidth: 4,
                    color: Colors.blue,
                  ),
                ]),
              MarkerLayer(markers: markers),
            ],
          ),

          // ── Instruction card ───────────────────────────────────────────
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: _InstructionCard(
              instruction: _currentInstruction(),
              routeId: currentRoute.id,
              condition: _conditionToText(currentCondition),
              stepText:
                  'Step ${currentStep + 1} of ${currentRoute.steps.length}',
              gpsStatus: gpsStatus,
              icon: _currentIcon(),
              realtimeCuesEnabled: realtimeCuesEnabled,
            ),
          ),

          // ── Map control buttons ────────────────────────────────────────
          Positioned(
            top: 210,
            right: 16,
            child: _MapControlButtons(
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onRecalculateArea: _recalculateStudyAreaFromCurrentLocation,
            ),
          ),

          // ── Start / waiting overlay ────────────────────────────────────
          if (!routeStarted)
            Center(
              child: Card(
                elevation: 8,
                color: Colors.white,
                surfaceTintColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        waitingForGps
                            ? Icons.gps_not_fixed
                            : Icons.gps_fixed,
                        size: 42,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        waitingForGps
                            ? 'Waiting for GPS'
                            : 'Set study origin',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        waitingForGps
                            ? 'The app is waiting for the first valid location update.\nCheck browser permission or test on phone.'
                            : 'Stand at the physical start point.\nThe first valid GPS update will become virtual (0, 0).',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: waitingForGps
                            ? null
                            : _startRouteAndSetOrigin,
                        child:
                            const Text('Start Route and Set Origin'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => _startSimulatedMode(
                          reason: 'Simulated route mode selected manually.',
                        ),
                        child: const Text('Use Simulated Mode'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Researcher controls ────────────────────────────────────────
          if (routeStarted)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _ResearcherControls(
                isLastStep:
                    currentStep >= currentRoute.points.length - 1,
                speedText: simulatedMode
                    ? 'Simulated mode'
                    : '${currentSpeedKmh.toStringAsFixed(1)} km/h'
                        '${currentAccuracyMeters == null ? '' : ' · ±${currentAccuracyMeters!.toStringAsFixed(1)} m'}',
                realtimeCuesEnabled: realtimeCuesEnabled,
                controlsVisible: _controlsVisible,
                onToggleVisibility: () {
                  setState(() => _controlsVisible = !_controlsVisible);
                },
                onToggleRealtimeCues: _toggleRealtimeCues,
                onReachedPoint: _manualReachedPoint,
                onMissedTurn: () => _markError('missed_turn'),
                onWrongPath: () => _markError('wrong_path'),
                onCueStraight: () => _manualCue('straight'),
                onCueLeft: () => _manualCue('left'),
                onCueRight: () => _manualCue('right'),
                onCueWrong: () => _manualCue('wrong'),
                onTerminate: () => _endRoute(completed: false),
                onGoToLocation: _goToCurrentLocation,
                onTestCue: () {
                  final m = currentRoute.steps[currentStep].maneuver;
                  _manualCue(m);
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map control buttons widget
// ---------------------------------------------------------------------------

class _MapControlButtons extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecalculateArea;

  const _MapControlButtons({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecalculateArea,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Recalculate area from current GPS point',
            onPressed: onRecalculateArea,
            icon: const Icon(Icons.gps_fixed),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User location marker widget
// ---------------------------------------------------------------------------

class _UserLocationMarker extends StatelessWidget {
  final double? headingDegrees;
  final bool isGpsActive;

  const _UserLocationMarker({
    required this.headingDegrees,
    required this.isGpsActive,
  });

  @override
  Widget build(BuildContext context) {
    final radians = ((headingDegrees ?? 0.0) * math.pi) / 180.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.18),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isGpsActive ? Colors.blue : Colors.grey,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(blurRadius: 8, spreadRadius: 1, color: Colors.black26),
            ],
          ),
        ),
        if (headingDegrees != null)
          Transform.rotate(
            angle: radians,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 38),
              child: Icon(Icons.navigation, color: Colors.blue, size: 26),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Instruction card widget
// ---------------------------------------------------------------------------

class _InstructionCard extends StatelessWidget {
  final String instruction;
  final String routeId;
  final String condition;
  final String stepText;
  final String gpsStatus;
  final IconData icon;
  final bool realtimeCuesEnabled;

  const _InstructionCard({
    required this.instruction,
    required this.routeId,
    required this.condition,
    required this.stepText,
    required this.gpsStatus,
    required this.icon,
    required this.realtimeCuesEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: realtimeCuesEnabled
                    ? Colors.blue.shade600
                    : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instruction,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$routeId · $condition · $stepText',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    realtimeCuesEnabled
                        ? 'Realtime cues: ON'
                        : 'Realtime cues: OFF',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: realtimeCuesEnabled
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    gpsStatus,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Researcher controls widget
// ---------------------------------------------------------------------------

class _ResearcherControls extends StatelessWidget {
  final bool isLastStep;
  final String speedText;
  final bool realtimeCuesEnabled;
  final bool controlsVisible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleRealtimeCues;
  final VoidCallback onReachedPoint;
  final VoidCallback onMissedTurn;
  final VoidCallback onWrongPath;
  final VoidCallback onCueStraight;
  final VoidCallback onCueLeft;
  final VoidCallback onCueRight;
  final VoidCallback onCueWrong;
  final VoidCallback onTerminate;
  final VoidCallback onGoToLocation;
  final VoidCallback onTestCue;

  const _ResearcherControls({
    required this.isLastStep,
    required this.speedText,
    required this.realtimeCuesEnabled,
    required this.controlsVisible,
    required this.onToggleVisibility,
    required this.onToggleRealtimeCues,
    required this.onReachedPoint,
    required this.onMissedTurn,
    required this.onWrongPath,
    required this.onCueStraight,
    required this.onCueLeft,
    required this.onCueRight,
    required this.onCueWrong,
    required this.onTerminate,
    required this.onGoToLocation,
    required this.onTestCue,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with hide/show toggle.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Researcher controls · $speedText',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                IconButton(
                  tooltip: controlsVisible
                      ? 'Hide controls'
                      : 'Show controls',
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    controlsVisible
                        ? Icons.expand_more
                        : Icons.expand_less,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            if (controlsVisible) ...[
              const SizedBox(height: 8),

              // Real-time cue toggle.
              FilledButton(
                onPressed: onToggleRealtimeCues,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  backgroundColor:
                      realtimeCuesEnabled ? Colors.green : Colors.red,
                ),
                child: Text(
                  realtimeCuesEnabled
                      ? 'Disable Real-Time Cues'
                      : 'Enable Real-Time Cues',
                ),
              ),
              const SizedBox(height: 8),

              // Reached Point / Finish Route.
              FilledButton(
                onPressed: onReachedPoint,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child:
                    Text(isLastStep ? 'Finish Route' : 'Reached Point'),
              ),
              const SizedBox(height: 8),

              // Missed Turn / Wrong Path.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onMissedTurn,
                      child: const Text('Missed Turn'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onWrongPath,
                      child: const Text('Wrong Path'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Manual cue buttons.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCueStraight,
                      child: const Text('Straight'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCueLeft,
                      child: const Text('Left'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCueRight,
                      child: const Text('Right'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCueWrong,
                      child: const Text('Wrong'),
                    ),
                  ),
                ],
              ),

              // Utility buttons.
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onGoToLocation,
                      child: const Text('Center'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: onTestCue,
                      child: const Text('Test Current'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: onTerminate,
                      child: const Text('Terminate'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary screen
// ---------------------------------------------------------------------------

class SummaryScreen extends StatelessWidget {
  final String participantId;
  final List<StudyRoute> routeOrder;
  final List<FeedbackCondition> conditionOrder;
  final int finishedRouteIndex;
  final List<Map<String, dynamic>> allSessionLogs;

  const SummaryScreen({
    super.key,
    required this.participantId,
    required this.routeOrder,
    required this.conditionOrder,
    required this.finishedRouteIndex,
    required this.allSessionLogs,
  });

  bool get hasNextRoute => finishedRouteIndex + 1 < routeOrder.length;

  void _startNextRoute(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StudyMapScreen(
          participantId: participantId,
          routeOrder: routeOrder,
          conditionOrder: conditionOrder,
          routeIndex: finishedRouteIndex + 1,
          allSessionLogs: allSessionLogs,
        ),
      ),
    );
  }

  Future<void> _copyJson(BuildContext context, String json) async {
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prettyJson =
        const JsonEncoder.withIndent('  ').convert(allSessionLogs);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Route Summary'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasNextRoute
                          ? 'Route saved. Ready for next route.'
                          : 'Study complete.',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Participant ID: $participantId'),
                    Text('Completed routes: ${allSessionLogs.length}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                color: Colors.white,
                surfaceTintColor: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      prettyJson,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _copyJson(context, prettyJson),
              child: const Text('Copy JSON'),
            ),
            const SizedBox(height: 8),
            if (hasNextRoute)
              FilledButton(
                onPressed: () => _startNextRoute(context),
                child: const Text('Start Next Route'),
              )
            else
              FilledButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
                child: const Text('Start New Participant'),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WAV beep generator (PCM, 16-bit mono)
// ---------------------------------------------------------------------------

Uint8List _generateBeepWav({
  required int frequency,
  required int durationMs,
  int sampleRate = 44100,
}) {
  final sampleCount = (sampleRate * durationMs / 1000).round();
  final dataLength = sampleCount * 2;
  final fileLength = 44 + dataLength;

  final bytes = ByteData(fileLength);

  void writeString(int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  bytes.setUint32(4, fileLength - 8, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);  // PCM
  bytes.setUint16(22, 1, Endian.little);  // Mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  const amplitude = 0.35 * 32767;
  for (int i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final envelope = math.sin(math.pi * i / sampleCount);
    final sample = math.sin(2 * math.pi * frequency * t);
    final value = (sample * envelope * amplitude).round();
    bytes.setInt16(44 + i * 2, value, Endian.little);
  }

  return bytes.buffer.asUint8List();
}
