import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
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

class RoutePoint {
  final double x;
  final double y;

  const RoutePoint(this.x, this.y);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
      };
}

class StudyRoute {
  final String id;
  final List<RoutePoint> points;

  const StudyRoute({
    required this.id,
    required this.points,
  });
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

const routeA = StudyRoute(
  id: 'Route A',
  points: [
    RoutePoint(1, 1),
    RoutePoint(1, 4),
    RoutePoint(4, 4),
    RoutePoint(4, 8),
    RoutePoint(8, 8),
  ],
);

const routeB = StudyRoute(
  id: 'Route B',
  points: [
    RoutePoint(1, 1),
    RoutePoint(4, 1),
    RoutePoint(4, 5),
    RoutePoint(8, 5),
    RoutePoint(8, 8),
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
        builder: (_) => NavigationScreen(
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

class NavigationScreen extends StatefulWidget {
  final String participantId;
  final List<StudyRoute> routeOrder;
  final List<FeedbackCondition> conditionOrder;
  final int routeIndex;
  final List<Map<String, dynamic>> allSessionLogs;

  const NavigationScreen({
    super.key,
    required this.participantId,
    required this.routeOrder,
    required this.conditionOrder,
    required this.routeIndex,
    required this.allSessionLogs,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late StudyRoute currentRoute;
  late FeedbackCondition currentCondition;
  late RouteSession session;

  Position? originPosition;
  Position? currentGpsPosition;
  StreamSubscription<Position>? positionStream;

  double userX = 1.0;
  double userY = 1.0;

  bool gpsTrackingActive = false;
  String gpsStatus = 'GPS not started yet';

  final List<Map<String, dynamic>> pathFollowed = [];

  @override
  void initState() {
    super.initState();

    currentRoute = widget.routeOrder[widget.routeIndex];
    currentCondition = widget.conditionOrder[widget.routeIndex];

    userX = currentRoute.points.first.x;
    userY = currentRoute.points.first.y;

    session = RouteSession(
      participantId: widget.participantId,
      routeId: currentRoute.id,
      condition: _conditionToText(currentCondition),
      startTime: DateTime.now(),
      events: [],
    );

    _logEvent('route_started');
    _startGpsTracking();
  }

  @override
  void dispose() {
    positionStream?.cancel();
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
    if (session.currentStep >= currentRoute.points.length - 1) {
      return 'Arrive at destination';
    }

    final current = currentRoute.points[session.currentStep];
    final next = currentRoute.points[session.currentStep + 1];

    final dx = next.x - current.x;
    final dy = next.y - current.y;

    if (dx.abs() > dy.abs()) {
      return dx > 0 ? 'Continue east, then follow the blue route' : 'Continue west, then follow the blue route';
    } else {
      return dy > 0 ? 'Continue north, then follow the blue route' : 'Continue south, then follow the blue route';
    }
  }

  void _logEvent(String type) {
    session.events.add(
      StudyEvent(
        type: type,
        timestamp: DateTime.now(),
        stepIndex: session.currentStep,
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      setState(() {
        gpsStatus = 'Location services are disabled';
      });
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(() {
        gpsStatus = 'Location permission denied';
      });
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        gpsStatus = 'Location permission permanently denied';
      });
      return false;
    }

    return true;
  }

  Map<String, double> _gpsToVirtualXY(Position origin, Position current) {
    final startPoint = currentRoute.points.first;

    final northDistance = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      current.latitude,
      origin.longitude,
    );

    final eastDistance = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      origin.latitude,
      current.longitude,
    );

    final isNorth = current.latitude >= origin.latitude;
    final isEast = current.longitude >= origin.longitude;

    final deltaY = isNorth ? northDistance : -northDistance;
    final deltaX = isEast ? eastDistance : -eastDistance;

    final virtualX = (startPoint.x + deltaX).clamp(0.0, 10.0);
    final virtualY = (startPoint.y + deltaY).clamp(0.0, 10.0);

    return {
      'x': virtualX,
      'y': virtualY,
    };
  }

  Future<void> _startGpsTracking() async {
    setState(() {
      gpsStatus = 'Requesting GPS permission...';
    });

    final hasPermission = await _ensureLocationPermission();

    if (!hasPermission) {
      _logEvent('gps_permission_failed');
      return;
    }

    try {
      originPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _logEvent('gps_origin_set');

      setState(() {
        gpsStatus = 'GPS active. Origin saved.';
        gpsTrackingActive = true;
      });

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      );

      positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          if (originPosition == null) return;

          final virtual = _gpsToVirtualXY(originPosition!, position);

          setState(() {
            currentGpsPosition = position;
            userX = virtual['x']!;
            userY = virtual['y']!;

            pathFollowed.add({
              'timestamp': DateTime.now().toIso8601String(),
              'lat': position.latitude,
              'lng': position.longitude,
              'accuracy': position.accuracy,
              'virtualX': userX,
              'virtualY': userY,
              'stepIndex': session.currentStep,
            });

            gpsStatus =
                'GPS active: x=${userX.toStringAsFixed(1)}, y=${userY.toStringAsFixed(1)}';
          });
        },
        onError: (_) {
          setState(() {
            gpsStatus = 'GPS stream error';
            gpsTrackingActive = false;
          });
          _logEvent('gps_stream_error');
        },
      );
    } catch (_) {
      setState(() {
        gpsStatus = 'Could not start GPS';
        gpsTrackingActive = false;
      });
      _logEvent('gps_start_failed');
    }
  }

  void _reachedPoint() {
    final isLastStep = session.currentStep == currentRoute.points.length - 1;

    if (isLastStep) {
      _endRoute(completed: true);
      return;
    }

    setState(() {
      _logEvent('reached_point');

      session.currentStep++;

      if (!gpsTrackingActive) {
        final newPoint = currentRoute.points[session.currentStep];
        userX = newPoint.x;
        userY = newPoint.y;
      }
    });
  }

  void _markError(String type) {
    setState(() {
      _logEvent(type);
    });
  }

  Future<void> _endRoute({required bool completed}) async {
    await positionStream?.cancel();

    session.endTime = DateTime.now();
    session.completed = completed;
    _logEvent(completed ? 'route_completed' : 'route_terminated');

    final sessionJson = session.toJson();
    sessionJson['pathFollowed'] = pathFollowed;
    sessionJson['gpsTrackingActive'] = gpsTrackingActive;
    sessionJson['gpsStatusAtEnd'] = gpsStatus;
    sessionJson['finalVirtualPosition'] = {
      'x': userX,
      'y': userY,
    };

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
    final isLastStep = session.currentStep == currentRoute.points.length - 1;
    final instruction = _currentInstruction();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: MapPainter(
                  route: currentRoute,
                  currentStep: session.currentStep,
                  userX: userX,
                  userY: userY,
                ),
                child: Container(),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _InstructionCard(
                routeId: currentRoute.id,
                condition: _conditionToText(currentCondition),
                instruction: instruction,
                stepText:
                    'Step ${session.currentStep + 1} of ${currentRoute.points.length}',
                gpsStatus: gpsStatus,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _ResearcherControls(
                isLastStep: isLastStep,
                onReachedPoint: _reachedPoint,
                onMissedTurn: () => _markError('missed_turn'),
                onWrongTurn: () => _markError('wrong_turn'),
                onBacktracking: () => _markError('backtracking'),
                onTerminate: () => _endRoute(completed: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  final String routeId;
  final String condition;
  final String instruction;
  final String stepText;
  final String gpsStatus;

  const _InstructionCard({
    required this.routeId,
    required this.condition,
    required this.instruction,
    required this.stepText,
    required this.gpsStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
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
                color: Colors.blue.shade600,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.navigation,
                color: Colors.white,
                size: 30,
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
  final VoidCallback onReachedPoint;
  final VoidCallback onMissedTurn;
  final VoidCallback onWrongTurn;
  final VoidCallback onBacktracking;
  final VoidCallback onTerminate;

  const _ResearcherControls({
    required this.isLastStep,
    required this.onReachedPoint,
    required this.onMissedTurn,
    required this.onWrongTurn,
    required this.onBacktracking,
    required this.onTerminate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onBacktracking,
                    child: const Text('Backtrack'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: onTerminate,
              child: const Text('Terminate Route'),
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
        builder: (_) => NavigationScreen(
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
    final prettyJson = const JsonEncoder.withIndent('  ').convert(allSessionLogs);

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

class MapPainter extends CustomPainter {
  final StudyRoute route;
  final int currentStep;
  final double userX;
  final double userY;

  MapPainter({
    required this.route,
    required this.currentStep,
    required this.userX,
    required this.userY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 38.0;
    final mapSize = size.shortestSide - padding * 2;
    final left = (size.width - mapSize) / 2;
    final top = (size.height - mapSize) / 2 + 20;

    Offset toScreen(RoutePoint p) {
      final x = left + (p.x / 10.0) * mapSize;
      final y = top + mapSize - (p.y / 10.0) * mapSize;
      return Offset(x, y);
    }

    final backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE8F1E5);

    final mapRect = Rect.fromLTWH(left, top, mapSize, mapSize);
    canvas.drawRect(mapRect, backgroundPaint);

    _drawFakeMapBackground(canvas, mapRect);
    _drawRoute(canvas, toScreen);
    _drawMarkers(canvas, toScreen);
    _drawUser(canvas, toScreen);
  }

  void _drawFakeMapBackground(Canvas canvas, Rect mapRect) {
    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF7F3E8);

    final pathBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD7D1C2);

    final faintLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.7);

    final parkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFD8EBCB);

    canvas.drawRRect(
      RRect.fromRectAndRadius(mapRect, const Radius.circular(28)),
      parkPaint,
    );

    final p1 = Offset(mapRect.left + mapRect.width * 0.10, mapRect.top + mapRect.height * 0.25);
    final p2 = Offset(mapRect.left + mapRect.width * 0.90, mapRect.top + mapRect.height * 0.25);
    final p3 = Offset(mapRect.left + mapRect.width * 0.18, mapRect.top + mapRect.height * 0.70);
    final p4 = Offset(mapRect.left + mapRect.width * 0.82, mapRect.top + mapRect.height * 0.70);
    final p5 = Offset(mapRect.left + mapRect.width * 0.50, mapRect.top + mapRect.height * 0.08);
    final p6 = Offset(mapRect.left + mapRect.width * 0.50, mapRect.top + mapRect.height * 0.92);

    canvas.drawLine(p1, p2, pathBorderPaint);
    canvas.drawLine(p3, p4, pathBorderPaint);
    canvas.drawLine(p5, p6, pathBorderPaint);

    canvas.drawLine(p1, p2, pathPaint);
    canvas.drawLine(p3, p4, pathPaint);
    canvas.drawLine(p5, p6, pathPaint);

    for (int i = 1; i < 10; i++) {
      final x = mapRect.left + (i / 10.0) * mapRect.width;
      final y = mapRect.top + (i / 10.0) * mapRect.height;
      canvas.drawLine(Offset(x, mapRect.top), Offset(x, mapRect.bottom), faintLinePaint);
      canvas.drawLine(Offset(mapRect.left, y), Offset(mapRect.right, y), faintLinePaint);
    }
  }

  void _drawRoute(Canvas canvas, Offset Function(RoutePoint p) toScreen) {
    final routeShadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.blue.withOpacity(0.18);

    final remainingRoutePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.blue.shade600;

    final completedRoutePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.green.shade600;

    for (int i = 0; i < route.points.length - 1; i++) {
      final start = toScreen(route.points[i]);
      final end = toScreen(route.points[i + 1]);

      canvas.drawLine(start, end, routeShadowPaint);
      canvas.drawLine(
        start,
        end,
        i < currentStep ? completedRoutePaint : remainingRoutePaint,
      );
    }
  }

  void _drawMarkers(Canvas canvas, Offset Function(RoutePoint p) toScreen) {
    final normalPointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    final normalPointBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.blue.shade600;

    final currentPointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.orange.shade700;

    final destinationPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red.shade600;

    for (int i = 0; i < route.points.length; i++) {
      final point = toScreen(route.points[i]);

      if (i == route.points.length - 1) {
        canvas.drawCircle(point, 11, destinationPaint);
      } else if (i == currentStep) {
        canvas.drawCircle(point, 10, currentPointPaint);
      } else {
        canvas.drawCircle(point, 8, normalPointPaint);
        canvas.drawCircle(point, 8, normalPointBorderPaint);
      }
    }
  }

  void _drawUser(Canvas canvas, Offset Function(RoutePoint p) toScreen) {
    final userPoint = toScreen(RoutePoint(userX, userY));

    final accuracyPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue.withOpacity(0.18);

    final userPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue.shade700;

    final userBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white;

    canvas.drawCircle(userPoint, 20, accuracyPaint);
    canvas.drawCircle(userPoint, 10, userPaint);
    canvas.drawCircle(userPoint, 10, userBorderPaint);
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) {
    return oldDelegate.currentStep != currentStep ||
        oldDelegate.route != route ||
        oldDelegate.userX != userX ||
        oldDelegate.userY != userY;
  }
}