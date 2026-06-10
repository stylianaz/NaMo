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

enum FeedbackCondition {
  visualAudio,
  visualHaptic,
}

class VirtualPoint {
  final double x;
  final double y;

  const VirtualPoint(this.x, this.y);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
      };
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

  const StudyRoute({
    required this.id,
    required this.steps,
  });

  List<VirtualPoint> get points => steps.map((step) => step.point).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'steps': steps.map((step) => step.toJson()).toList(),
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
        'events': events.map((event) => event.toJson()).toList(),
      };
}

const routeA = StudyRoute(
  id: 'Route A',
  steps: [
    RouteStep(
      point: VirtualPoint(0, 0),
      instruction: 'Start walking straight',
      maneuver: 'straight',
    ),
    RouteStep(
      point: VirtualPoint(0, 25),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(25, 25),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(25, 50),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(55, 50),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(55, 80),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(85, 80),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(85, 55),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(110, 55),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(110, 30),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(75, 30),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(75, 5),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(45, 5),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(45, 35),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(15, 35),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(15, 70),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(40, 70),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(40, 105),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(0, 105),
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
      instruction: 'Start walking straight',
      maneuver: 'straight',
    ),
    RouteStep(
      point: VirtualPoint(30, 0),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(30, 30),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(60, 30),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(60, 65),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(30, 65),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(30, 95),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(70, 95),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(70, 70),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(105, 70),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(105, 35),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(80, 35),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(80, 10),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(50, 10),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(50, 45),
      instruction: 'Turn left soon',
      maneuver: 'left',
    ),
    RouteStep(
      point: VirtualPoint(15, 45),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(15, 85),
      instruction: 'Turn right soon',
      maneuver: 'right',
    ),
    RouteStep(
      point: VirtualPoint(75, 85),
      instruction: 'Arrive at destination',
      maneuver: 'arrive',
    ),
  ],
);

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
    final routeOrder = selectedOrder == 0 ? [routeA, routeB] : [routeB, routeA];

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
                        DropdownMenuItem(
                          value: 0,
                          child: Text('Order 1'),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text('Order 2'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          selectedOrder = value;
                        });
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
  final MapController _mapController = MapController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Location _locationService = Location();

  StreamSubscription<LocationData>? _locationSubscription;

  late StudyRoute currentRoute;
  late FeedbackCondition currentCondition;
  late RouteSession session;

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

  int currentStep = 0;

  bool routeStarted = false;
  bool gpsTrackingActive = false;
  bool simulatedMode = false;
  bool studyAreaCreated = false;
  bool waitingForGps = false;
  bool realtimeCuesEnabled = true;

  String gpsStatus = 'Stand at the start point, then set origin.';

  DateTime? lastCueTime;
  DateTime? lastContinueCueTime;
  DateTime? lastTurnCueTime;
  DateTime? lastWrongCueTime;

  int? lastTurnCueStepIndex;

  final List<Map<String, dynamic>> pathFollowed = [];

  static const double waypointReachRadius = 4.0;
  static const double offRouteThreshold = 8.0;
  static const double studySizeMeters = 120.0;

  static const double turnCueDistance = 12.0;
  static const double missedTurnDistance = 10.0;
  static const double continueCueMinSeconds = 8.0;
  static const double sameCueCooldownSeconds = 4.0;
  static const double wrongCueCooldownSeconds = 3.0;

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

  String _conditionToText(FeedbackCondition condition) {
    switch (condition) {
      case FeedbackCondition.visualAudio:
        return 'Visual + Audio';
      case FeedbackCondition.visualHaptic:
        return 'Visual + Haptic';
    }
  }

  String _currentInstruction() {
    if (!routeStarted) {
      if (waitingForGps) return 'Waiting for GPS';
      return 'Set study origin';
    }

    if (currentStep >= currentRoute.steps.length) {
      return 'Arrive at destination';
    }

    return currentRoute.steps[currentStep].instruction;
  }

  IconData _currentIcon() {
    if (!routeStarted) {
      if (waitingForGps) return Icons.gps_not_fixed;
      return Icons.gps_fixed;
    }

    if (currentStep >= currentRoute.steps.length) {
      return Icons.flag;
    }

    final maneuver = currentRoute.steps[currentStep].maneuver;

    switch (maneuver) {
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
    session.events.add(
      StudyEvent(
        type: type,
        timestamp: DateTime.now(),
        stepIndex: currentStep,
      ),
    );
  }

  Future<void> _startRouteAndSetOrigin() async {
    setState(() {
      gpsStatus = 'Checking location permission...';
      routeStarted = false;
      waitingForGps = true;
    });

    final canUseLocation = await _checkAndRequestLocationPermission();

    if (!canUseLocation) {
      setState(() {
        waitingForGps = false;
        gpsStatus = 'Location permission denied or location service disabled.';
      });

      _logEvent('location_permission_or_service_failed');
      return;
    }

    setState(() {
      gpsStatus = 'Waiting for first GPS update... Keep this tab active.';
    });

    await _waitForFirstLocationFromStream();
  }

  Future<bool> _checkAndRequestLocationPermission() async {
    try {
      if (kIsWeb) {
        debugPrint(
          'LOCATION DEBUG: web mode detected. Skipping location package permission check.',
        );

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
          debugPrint('LOCATION DEBUG: location service disabled');
          _logEvent('gps_service_disabled');
          return false;
        }
      }

      PermissionStatus permissionGranted = await _locationService.hasPermission();

      debugPrint('LOCATION DEBUG: initial permission = $permissionGranted');

      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _locationService.requestPermission();

        debugPrint('LOCATION DEBUG: requested permission = $permissionGranted');
      }

      if (permissionGranted != PermissionStatus.granted &&
          permissionGranted != PermissionStatus.grantedLimited) {
        debugPrint('LOCATION DEBUG: permission not granted');
        _logEvent('gps_permission_denied');
        return false;
      }

      await _locationService.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 1000,
        distanceFilter: 1,
      );

      return true;
    } catch (error) {
      debugPrint('LOCATION DEBUG: permission check failed: $error');
      _logEvent('gps_permission_check_failed');
      return false;
    }
  }

  Future<void> _waitForFirstLocationFromStream() async {
    await _locationSubscription?.cancel();

    bool firstLocationReceived = false;

    _locationSubscription = _locationService.onLocationChanged.listen(
      (LocationData locationData) {
        debugPrint(
          'LOCATION DEBUG: stream update '
          'lat=${locationData.latitude}, '
          'lng=${locationData.longitude}, '
          'accuracy=${locationData.accuracy}, '
          'speed=${locationData.speed}, '
          'heading=${locationData.heading}',
        );

        if (locationData.latitude == null || locationData.longitude == null) {
          if (!mounted) return;

          setState(() {
            gpsStatus = 'GPS update received, but latitude/longitude is null.';
          });

          return;
        }

        final start = LatLng(
          locationData.latitude!,
          locationData.longitude!,
        );

        if (!firstLocationReceived) {
          firstLocationReceived = true;
          _startGpsMode(start, locationData);
        } else {
          _handleLocationUpdate(locationData);
        }
      },
      onError: (error) {
        debugPrint('LOCATION DEBUG: stream error: $error');

        if (!mounted) return;

        setState(() {
          waitingForGps = false;
          gpsTrackingActive = false;
          gpsStatus = 'GPS stream error: $error';
        });

        _logEvent('location_stream_error');
      },
    );

    Future.delayed(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (firstLocationReceived) return;

      setState(() {
        waitingForGps = false;
        gpsStatus =
            'Still waiting for GPS. Check browser permission or test on phone.';
      });

      _logEvent('gps_first_location_timeout_30s');
    });
  }

  void _startGpsMode(LatLng start, LocationData initialLocation) {
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
      currentSpeedKmh = (initialLocation.speed ?? 0.0) * 3.6;
      currentHeadingDegrees = initialLocation.heading;
      currentAccuracyMeters = initialLocation.accuracy;
      userPath = [start];

      pathFollowed.add({
        'timestamp': DateTime.now().toIso8601String(),
        'mode': 'gps_origin',
        'lat': start.latitude,
        'lng': start.longitude,
        'virtualX': 0.0,
        'virtualY': 0.0,
        'speedKmh': currentSpeedKmh,
        'accuracy': initialLocation.accuracy,
        'heading': initialLocation.heading,
        'stepIndex': currentStep,
      });

      gpsStatus =
          'GPS active. Origin saved. Accuracy: ±${(initialLocation.accuracy ?? 0).toStringAsFixed(1)}m';
    });

    _logEvent('gps_origin_set');
    _logEvent('study_area_created');
    _logEvent('gps_mode_started_location_package');

    _currentZoom = 19.5;
    _mapController.move(start, _currentZoom);
  }

  void _handleLocationUpdate(LocationData locationData) {
    if (origin == null) return;
    if (locationData.latitude == null || locationData.longitude == null) return;

    final pos = LatLng(locationData.latitude!, locationData.longitude!);
    final virtual = _latLngToVirtual(origin!, pos);
    final accuracy = locationData.accuracy ?? 0.0;
    final heading = locationData.heading;

    setState(() {
      currentLocation = pos;
      userX = virtual.x;
      userY = virtual.y;
      currentSpeedKmh = (locationData.speed ?? 0.0) * 3.6;
      currentHeadingDegrees = heading;
      currentAccuracyMeters = accuracy;
      userPath.add(pos);

      pathFollowed.add({
        'timestamp': DateTime.now().toIso8601String(),
        'mode': 'gps_location_package',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'virtualX': userX,
        'virtualY': userY,
        'speedKmh': currentSpeedKmh,
        'accuracy': accuracy,
        'heading': heading,
        'stepIndex': currentStep,
      });

      gpsStatus =
          'GPS: x=${userX.toStringAsFixed(1)}, y=${userY.toStringAsFixed(1)}, '
          '±${accuracy.toStringAsFixed(1)}m, heading=${heading?.toStringAsFixed(0) ?? '-'}°';
    });

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

  LatLng _offsetMetersToLatLng(
    LatLng origin,
    double eastMeters,
    double northMeters,
  ) {
    const earthRadius = 6378137.0;

    final dLat = northMeters / earthRadius;
    final dLng = eastMeters /
        (earthRadius * math.cos(math.pi * origin.latitude / 180.0));

    final lat = origin.latitude + dLat * 180.0 / math.pi;
    final lng = origin.longitude + dLng * 180.0 / math.pi;

    return LatLng(lat, lng);
  }

  VirtualPoint _latLngToVirtual(LatLng origin, LatLng current) {
    const metersPerDegreeLat = 111320.0;

    final metersPerDegreeLng =
        111320.0 * math.cos(origin.latitude * math.pi / 180.0);

    final x = (current.longitude - origin.longitude) * metersPerDegreeLng;
    final y = (current.latitude - origin.latitude) * metersPerDegreeLat;

    return VirtualPoint(x, y);
  }

  List<LatLng> _createStudyBoundary(LatLng origin) {
    return [
      _offsetMetersToLatLng(origin, 0, 0),
      _offsetMetersToLatLng(origin, studySizeMeters, 0),
      _offsetMetersToLatLng(origin, studySizeMeters, studySizeMeters),
      _offsetMetersToLatLng(origin, 0, studySizeMeters),
    ];
  }

  List<LatLng> _createFakeRoute(
    LatLng origin,
    List<VirtualPoint> virtualRoute,
  ) {
    return virtualRoute.map((point) {
      return _offsetMetersToLatLng(origin, point.x, point.y);
    }).toList();
  }

  void _goToCurrentLocation() {
    if (currentLocation == null) return;

    _mapCenter = currentLocation;
    _currentZoom = 20.5;

    _mapController.move(currentLocation!, _currentZoom);
  }

  void _zoomIn() {
    final center = _mapCenter ?? currentLocation ?? origin ?? fallbackCenter;
    final nextZoom = (_currentZoom + 0.75).clamp(3.0, 22.0).toDouble();

    _currentZoom = nextZoom;
    _mapCenter = center;

    _mapController.move(center, nextZoom);
  }

  void _zoomOut() {
    final center = _mapCenter ?? currentLocation ?? origin ?? fallbackCenter;
    final nextZoom = (_currentZoom - 0.75).clamp(3.0, 22.0).toDouble();

    _currentZoom = nextZoom;
    _mapCenter = center;

    _mapController.move(center, nextZoom);
  }

  void _recalculateStudyAreaFromCurrentLocation() {
    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No current GPS point available yet.'),
        ),
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
      lastContinueCueTime = null;
      lastTurnCueTime = null;
      lastWrongCueTime = null;
      lastTurnCueStepIndex = null;

      gpsStatus =
          'Study area recalculated. Current GPS point is now virtual (0,0).';
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
      'stepIndex': currentStep,
    });

    _logEvent('study_area_recalculated_from_current_location');

    _mapCenter = newOrigin;
    _currentZoom = 19.5;
    _mapController.move(newOrigin, _currentZoom);
  }

  void _toggleRealtimeCues() {
    setState(() {
      realtimeCuesEnabled = !realtimeCuesEnabled;
      lastContinueCueTime = null;
      lastTurnCueTime = null;
      lastWrongCueTime = null;
      lastTurnCueStepIndex = null;
    });

    _logEvent(
      realtimeCuesEnabled
          ? 'realtime_cues_enabled'
          : 'realtime_cues_disabled',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          realtimeCuesEnabled
              ? 'Real-time cues enabled'
              : 'Real-time cues disabled. Manual controls still work.',
        ),
      ),
    );
  }

  double _distanceBetweenVirtual(VirtualPoint a, VirtualPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;

    return math.sqrt(dx * dx + dy * dy);
  }

  double _distanceToSegment(
    VirtualPoint p,
    VirtualPoint a,
    VirtualPoint b,
  ) {
    final projection = _projectPointToSegment(p, a, b);
    return projection.distanceToSegment;
  }

  SegmentProjection _projectPointToSegment(
    VirtualPoint p,
    VirtualPoint a,
    VirtualPoint b,
  ) {
    final px = p.x;
    final py = p.y;
    final ax = a.x;
    final ay = a.y;
    final bx = b.x;
    final by = b.y;

    final dx = bx - ax;
    final dy = by - ay;

    if (dx == 0 && dy == 0) {
      return SegmentProjection(
        t: 0.0,
        distanceToSegment: _distanceBetweenVirtual(p, a),
        closestPoint: a,
      );
    }

    final rawT = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
    final clampedT = rawT.clamp(0.0, 1.0).toDouble();

    final closestX = ax + clampedT * dx;
    final closestY = ay + clampedT * dy;

    final distanceX = px - closestX;
    final distanceY = py - closestY;

    return SegmentProjection(
      t: rawT,
      distanceToSegment: math.sqrt(distanceX * distanceX + distanceY * distanceY),
      closestPoint: VirtualPoint(closestX, closestY),
    );
  }

  bool _isCueCooldownReady(DateTime? lastTime, double seconds) {
    if (lastTime == null) return true;

    final elapsed = DateTime.now().difference(lastTime).inMilliseconds / 1000.0;
    return elapsed >= seconds;
  }

  String _nextManeuver() {
    if (currentStep + 1 >= currentRoute.steps.length) {
      return 'arrive';
    }

    return currentRoute.steps[currentStep + 1].maneuver;
  }

  void _evaluateRealtimeNavigationCues() {
    if (!routeStarted) return;
    if (currentStep >= currentRoute.points.length - 1) return;

    if (currentAccuracyMeters != null && currentAccuracyMeters! > 25) {
      _logEvent('gps_accuracy_too_low_for_realtime_cues');
      return;
    }

    final user = VirtualPoint(userX, userY);
    final segmentStart = currentRoute.points[currentStep];
    final segmentEnd = currentRoute.points[currentStep + 1];

    final projection = _projectPointToSegment(user, segmentStart, segmentEnd);
    final distanceToSegment = projection.distanceToSegment;
    final distanceToNextPoint = _distanceBetweenVirtual(user, segmentEnd);

    final now = DateTime.now();

    if (distanceToSegment > offRouteThreshold) {
      if (_isCueCooldownReady(lastWrongCueTime, wrongCueCooldownSeconds)) {
        lastWrongCueTime = now;
        _logEvent('wrong_path_detected');
        _playCue('wrong');
      }
      return;
    }

    final hasPassedWaypoint =
        projection.t > 1.15 && distanceToNextPoint > missedTurnDistance;

    if (hasPassedWaypoint) {
      if (_isCueCooldownReady(lastWrongCueTime, wrongCueCooldownSeconds)) {
        lastWrongCueTime = now;
        _logEvent('missed_turn_detected');
        _playCue('wrong');
      }
      return;
    }

    if (distanceToNextPoint <= waypointReachRadius) {
      setState(() {
        currentStep++;
        session.currentStep = currentStep;
        lastTurnCueStepIndex = null;
      });

      _logEvent('auto_reached_point');

      if (currentStep >= currentRoute.points.length - 1) {
        _playCue('arrive');
      }

      return;
    }

    final nextManeuver = _nextManeuver();

    final approachingTurn =
        distanceToNextPoint <= turnCueDistance &&
        (nextManeuver == 'left' || nextManeuver == 'right');

    if (approachingTurn) {
      final isNewTurnCue = lastTurnCueStepIndex != currentStep + 1;

      if (isNewTurnCue ||
          _isCueCooldownReady(lastTurnCueTime, sameCueCooldownSeconds)) {
        lastTurnCueTime = now;
        lastTurnCueStepIndex = currentStep + 1;

        _logEvent('realtime_turn_cue_$nextManeuver');
        _playCue(nextManeuver);
      }

      return;
    }

    if (_isCueCooldownReady(lastContinueCueTime, continueCueMinSeconds)) {
      lastContinueCueTime = now;

      _logEvent('realtime_continue_straight_cue');
      _playCue('straight');
    }
  }

  Future<void> _playCue(String maneuver) async {
    final now = DateTime.now();

    if (lastCueTime != null &&
        now.difference(lastCueTime!).inMilliseconds < 900) {
      return;
    }

    lastCueTime = now;
    _logEvent('cue_$maneuver');

    if (currentCondition == FeedbackCondition.visualAudio) {
      await _playAudioCue(maneuver);
    } else {
      await _playHapticCue(maneuver);
    }
  }

  Future<void> _playAudioCue(String maneuver) async {
    switch (maneuver) {
      case 'straight':
        await _playBeep(frequency: 880, durationMs: 120);
        break;

      case 'left':
        await _playBeep(frequency: 880, durationMs: 100);
        await Future.delayed(const Duration(milliseconds: 120));
        await _playBeep(frequency: 880, durationMs: 100);
        break;

      case 'right':
        await _playBeep(frequency: 660, durationMs: 350);
        break;

      case 'wrong':
        for (int i = 0; i < 3; i++) {
          await _playBeep(frequency: 440, durationMs: 100);
          await Future.delayed(const Duration(milliseconds: 80));
        }
        break;

      case 'arrive':
        await _playBeep(frequency: 1000, durationMs: 120);
        await Future.delayed(const Duration(milliseconds: 90));
        await _playBeep(frequency: 1200, durationMs: 160);
        break;
    }
  }

  Future<void> _playHapticCue(String maneuver) async {
    switch (maneuver) {
      case 'straight':
        await HapticFeedback.lightImpact();
        break;

      case 'left':
        await HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.lightImpact();
        break;

      case 'right':
        await HapticFeedback.mediumImpact();
        break;

      case 'wrong':
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        await HapticFeedback.heavyImpact();
        break;

      case 'arrive':
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
    final wavBytes = _generateBeepWav(
      frequency: frequency,
      durationMs: durationMs,
    );

    await _audioPlayer.stop();
    await _audioPlayer.play(BytesSource(wavBytes));
  }

  void _manualReachedPoint() {
    if (!routeStarted) return;

    final isLastStep = currentStep >= currentRoute.points.length - 1;

    if (isLastStep) {
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

    _logEvent(type);
    _playCue('wrong');
  }

  void _manualCue(String cue) {
    if (!routeStarted) return;

    _logEvent('manual_cue_$cue');
    _playCue(cue);
  }

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
        : {
            'lat': origin!.latitude,
            'lng': origin!.longitude,
          };

    sessionJson['trackingMode'] = simulatedMode ? 'simulated' : 'gps';
    sessionJson['pathFollowed'] = pathFollowed;
    sessionJson['gpsTrackingActive'] = gpsTrackingActive;
    sessionJson['gpsStatusAtEnd'] = gpsStatus;
    sessionJson['finalAccuracyMeters'] = currentAccuracyMeters;
    sessionJson['finalHeadingDegrees'] = currentHeadingDegrees;
    sessionJson['finalVirtualPosition'] = {
      'x': userX,
      'y': userY,
    };
    sessionJson['realtimeCuesEnabledAtEnd'] = realtimeCuesEnabled;

    final updatedLogs = [
      ...widget.allSessionLogs,
      sessionJson,
    ];

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
          child: const Icon(
            Icons.location_on,
            color: Colors.green,
            size: 34,
          ),
        ),
      if (fakeRoutePoints.length > 1 && currentStep < fakeRoutePoints.length)
        Marker(
          point: fakeRoutePoints[currentStep],
          width: 50,
          height: 50,
          child: const Icon(
            Icons.adjust,
            color: Colors.orange,
            size: 30,
          ),
        ),
      if (fakeRoutePoints.isNotEmpty)
        Marker(
          point: fakeRoutePoints.last,
          width: 50,
          height: 50,
          child: const Icon(
            Icons.flag,
            color: Colors.red,
            size: 34,
          ),
        ),
    ];

    return Scaffold(
      body: Stack(
        children: [
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.namo',
              ),
              if (studyBoundary.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: studyBoundary,
                      color: Colors.blue.withOpacity(0.10),
                      borderColor: Colors.blueAccent,
                      borderStrokeWidth: 4,
                    ),
                  ],
                ),
              if (fakeRoutePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: fakeRoutePoints,
                      strokeWidth: 7,
                      color: Colors.black,
                    ),
                  ],
                ),
              if (userPath.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: userPath,
                      strokeWidth: 4,
                      color: Colors.blue,
                    ),
                  ],
                ),
              if (markers.isNotEmpty)
                MarkerLayer(
                  markers: markers,
                ),
            ],
          ),
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: _InstructionCard(
              instruction: _currentInstruction(),
              routeId: currentRoute.id,
              condition: _conditionToText(currentCondition),
              stepText: 'Step ${currentStep + 1} of ${currentRoute.steps.length}',
              gpsStatus: gpsStatus,
              icon: _currentIcon(),
              realtimeCuesEnabled: realtimeCuesEnabled,
            ),
          ),
          Positioned(
            top: 190,
            right: 16,
            child: _MapControlButtons(
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onRecalculateArea: _recalculateStudyAreaFromCurrentLocation,
            ),
          ),
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
                        waitingForGps ? Icons.gps_not_fixed : Icons.gps_fixed,
                        size: 42,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        waitingForGps ? 'Waiting for GPS' : 'Set study origin',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        waitingForGps
                            ? 'The app is waiting for the first valid location update.\nCheck browser permission or test on phone.'
                            : 'Stand at the physical start point.\nThe app will use the first valid GPS update as virtual point (0,0).',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed:
                            waitingForGps ? null : _startRouteAndSetOrigin,
                        child: const Text('Start Route and Set Origin'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                          _startSimulatedMode(
                            reason: 'Simulated route mode selected manually.',
                          );
                        },
                        child: const Text('Use Simulated Mode'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (routeStarted)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _ResearcherControls(
                isLastStep: currentStep >= currentRoute.points.length - 1,
                speedText: simulatedMode
                    ? 'Simulated mode'
                    : '${currentSpeedKmh.toStringAsFixed(1)} km/h'
                        '${currentAccuracyMeters == null ? '' : ' • ±${currentAccuracyMeters!.toStringAsFixed(1)}m'}',
                realtimeCuesEnabled: realtimeCuesEnabled,
                onToggleRealtimeCues: _toggleRealtimeCues,
                onReachedPoint: _manualReachedPoint,
                onMissedTurn: () => _markError('missed_turn'),
                onWrongTurn: () => _markError('wrong_turn'),
                onCueStraight: () => _manualCue('straight'),
                onCueLeft: () => _manualCue('left'),
                onCueRight: () => _manualCue('right'),
                onCueWrong: () => _manualCue('wrong'),
                onTerminate: () => _endRoute(completed: false),
                onGoToLocation: _goToCurrentLocation,
                onTestCue: () {
                  final maneuver = currentRoute.steps[currentStep].maneuver;
                  _manualCue(maneuver);
                },
              ),
            ),
        ],
      ),
    );
  }
}

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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

class _UserLocationMarker extends StatelessWidget {
  final double? headingDegrees;
  final bool isGpsActive;

  const _UserLocationMarker({
    required this.headingDegrees,
    required this.isGpsActive,
  });

  @override
  Widget build(BuildContext context) {
    final rotationRadians = ((headingDegrees ?? 0.0) * math.pi) / 180.0;

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
              BoxShadow(
                blurRadius: 8,
                spreadRadius: 1,
                color: Colors.black26,
              ),
            ],
          ),
        ),
        if (headingDegrees != null)
          Transform.rotate(
            angle: rotationRadians,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 38),
              child: Icon(
                Icons.navigation,
                color: Colors.blue,
                size: 26,
              ),
            ),
          ),
      ],
    );
  }
}

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
    final realtimeText =
        realtimeCuesEnabled ? 'Realtime cues: ON' : 'Realtime cues: OFF';

    return Card(
      elevation: 8,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: realtimeCuesEnabled ? Colors.blue.shade600 : Colors.grey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
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
                    '$routeId • $condition • $stepText',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    realtimeText,
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

class _ResearcherControls extends StatelessWidget {
  final bool isLastStep;
  final String speedText;
  final bool realtimeCuesEnabled;
  final VoidCallback onToggleRealtimeCues;
  final VoidCallback onReachedPoint;
  final VoidCallback onMissedTurn;
  final VoidCallback onWrongTurn;
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
    required this.onToggleRealtimeCues,
    required this.onReachedPoint,
    required this.onMissedTurn,
    required this.onWrongTurn,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Researcher controls • $speedText',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
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
            FilledButton(
              onPressed: onReachedPoint,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: Text(isLastStep ? 'Finish Route' : 'Reached Point'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onMissedTurn,
                    child: const Text('Missed'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onWrongTurn,
                    child: const Text('Wrong'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCueStraight,
                    child: const Text('Straight'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCueLeft,
                    child: const Text('Left'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCueRight,
                    child: const Text('Right'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCueWrong,
                    child: const Text('Wrong Cue'),
                  ),
                ),
              ],
            ),
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
        ),
      ),
    );
  }
}

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

  Future<void> _copyJson(BuildContext context, String jsonText) async {
    await Clipboard.setData(ClipboardData(text: jsonText));

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
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeString(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  final amplitude = 0.35 * 32767;

  for (int i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final envelope = math.sin(math.pi * i / sampleCount);
    final sample = math.sin(2 * math.pi * frequency * t);
    final value = (sample * envelope * amplitude).round();

    bytes.setInt16(44 + i * 2, value, Endian.little);
  }

  return bytes.buffer.asUint8List();
}