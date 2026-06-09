import 'dart:convert';
import 'package:flutter/material.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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
        ? 'Visual+Audio → Visual+Haptic'
        : 'Visual+Haptic → Visual+Audio';

    return Scaffold(
      appBar: AppBar(
        title: const Text('NaMo Study Setup'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Generated Participant ID',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              participantId,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const Text('Counterbalancing Order'),
            const SizedBox(height: 8),
            DropdownButton<int>(
              value: selectedOrder,
              items: const [
                DropdownMenuItem(
                  value: 0,
                  child: Text('Order 1: Route A + VA, then Route B + VH'),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text('Order 2: Route B + VH, then Route A + VA'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  selectedOrder = value;
                });
              },
            ),
            const SizedBox(height: 24),
            Text('Route order: $routeOrderText'),
            Text('Condition order: $conditionOrderText'),
            const Spacer(),
            ElevatedButton(
              onPressed: _startStudy,
              child: const Text('Start Study'),
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

    _logEvent('route_started');
  }

  String _conditionToText(FeedbackCondition condition) {
    switch (condition) {
      case FeedbackCondition.visualAudio:
        return 'Visual + Audio';
      case FeedbackCondition.visualHaptic:
        return 'Visual + Haptic';
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

  void _reachedPoint() {
    setState(() {
      _logEvent('reached_point');

      if (session.currentStep < currentRoute.points.length - 1) {
        session.currentStep++;
      } else {
        _endRoute(completed: true);
      }
    });
  }

  void _markError(String type) {
    setState(() {
      _logEvent(type);
    });
  }

  Future<void> _endRoute({required bool completed}) async {
    session.endTime = DateTime.now();
    session.completed = completed;
    _logEvent(completed ? 'route_completed' : 'route_terminated');

    final updatedLogs = [
      ...widget.allSessionLogs,
      session.toJson(),
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
    final currentPoint = currentRoute.points[session.currentStep];
    final isLastStep = session.currentStep == currentRoute.points.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('${currentRoute.id} — ${_conditionToText(currentCondition)}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: MapPainter(
                route: currentRoute,
                currentStep: session.currentStep,
              ),
              child: Container(),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Step ${session.currentStep + 1} of ${currentRoute.points.length}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  isLastStep
                      ? 'You reached the final target.'
                      : 'Go to point (${currentPoint.x}, ${currentPoint.y})',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _reachedPoint,
                  child: Text(isLastStep ? 'Finish Route' : 'Reached Point'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _markError('missed_turn'),
                        child: const Text('Missed Turn'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _markError('wrong_turn'),
                        child: const Text('Wrong Turn'),
                      ),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: () => _markError('backtracking'),
                  child: const Text('Backtracking'),
                ),
                TextButton(
                  onPressed: () => _endRoute(completed: false),
                  child: const Text('Terminate Route'),
                ),
              ],
            ),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final prettyJson = const JsonEncoder.withIndent('  ').convert(allSessionLogs);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Summary'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasNextRoute ? 'Route saved. Ready for next route.' : 'Study complete.',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Participant ID: $participantId'),
            Text('Completed routes: ${allSessionLogs.length}'),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(prettyJson),
              ),
            ),
            const SizedBox(height: 12),
            if (hasNextRoute)
              ElevatedButton(
                onPressed: () => _startNextRoute(context),
                child: const Text('Start Next Route'),
              )
            else
              ElevatedButton(
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

  MapPainter({
    required this.route,
    required this.currentStep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 32.0;
    final mapSize = size.shortestSide - padding * 2;
    final left = (size.width - mapSize) / 2;
    final top = (size.height - mapSize) / 2;

    Offset toScreen(RoutePoint p) {
      final x = left + (p.x / 10.0) * mapSize;
      final y = top + mapSize - (p.y / 10.0) * mapSize;
      return Offset(x, y);
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.black;

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.grey.shade300;

    final routePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = Colors.blue;

    final completedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = Colors.green;

    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue;

    final currentPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red;

    final rect = Rect.fromLTWH(left, top, mapSize, mapSize);
    canvas.drawRect(rect, borderPaint);

    for (int i = 1; i < 10; i++) {
      final x = left + (i / 10.0) * mapSize;
      final y = top + (i / 10.0) * mapSize;
      canvas.drawLine(Offset(x, top), Offset(x, top + mapSize), gridPaint);
      canvas.drawLine(Offset(left, y), Offset(left + mapSize, y), gridPaint);
    }

    for (int i = 0; i < route.points.length - 1; i++) {
      final start = toScreen(route.points[i]);
      final end = toScreen(route.points[i + 1]);

      canvas.drawLine(
        start,
        end,
        i < currentStep ? completedPaint : routePaint,
      );
    }

    for (int i = 0; i < route.points.length; i++) {
      final point = toScreen(route.points[i]);
      canvas.drawCircle(point, 8, i == currentStep ? currentPaint : pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) {
    return oldDelegate.currentStep != currentStep || oldDelegate.route != route;
  }
}