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

void main() { runApp(const NaMoApp()); }

class NaMoApp extends StatelessWidget {
  const NaMoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NaMo Study Prototype',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true),
    home: const HomeScreen(),
  );
}

// ── Enums ──────────────────────────────────────────────────────────────────
enum FeedbackCondition { visualAudio, visualHaptic }
enum StudyMode { experiment, tutorial, normal }

// ── Data classes ───────────────────────────────────────────────────────────
class VirtualPoint {
  final double x, y;
  const VirtualPoint(this.x, this.y);
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class SegmentProjection {
  final double t, distanceToSegment;
  final VirtualPoint closestPoint;
  const SegmentProjection({required this.t, required this.distanceToSegment, required this.closestPoint});
}

class RouteStep {
  final VirtualPoint point;
  final String instruction, maneuver;
  const RouteStep({required this.point, required this.instruction, required this.maneuver});
  Map<String, dynamic> toJson() => {'point': point.toJson(), 'instruction': instruction, 'maneuver': maneuver};
}

class StudyRoute {
  final String id;
  final List<RouteStep> steps;
  const StudyRoute({required this.id, required this.steps});
  List<VirtualPoint> get points => steps.map((s) => s.point).toList();
  Map<String, dynamic> toJson() => {'id': id, 'steps': steps.map((s) => s.toJson()).toList()};
}

class StudyEvent {
  final String type;
  final DateTime timestamp;
  final int stepIndex;
  StudyEvent({required this.type, required this.timestamp, required this.stepIndex});
  Map<String, dynamic> toJson() => {'type': type, 'timestamp': timestamp.toIso8601String(), 'stepIndex': stepIndex};
}

class RouteSession {
  final String participantId, routeId, condition;
  final DateTime startTime;
  DateTime? endTime;
  bool completed;
  int currentStep;
  final List<StudyEvent> events;
  RouteSession({required this.participantId, required this.routeId, required this.condition,
    required this.startTime, this.endTime, this.completed = false, this.currentStep = 0, required this.events});
  int? get completionTimeSeconds => endTime == null ? null : endTime!.difference(startTime).inSeconds;
  Map<String, dynamic> toJson() => {
    'participantId': participantId, 'routeId': routeId, 'condition': condition,
    'startTime': startTime.toIso8601String(), 'endTime': endTime?.toIso8601String(),
    'completionTimeSeconds': completionTimeSeconds, 'completed': completed,
    'currentStep': currentStep, 'events': events.map((e) => e.toJson()).toList(),
  };
}

// ── Routes ─────────────────────────────────────────────────────────────────
// Both routes fit ~120x120 m virtual space with realistic street-block geometry.
const routeA = StudyRoute(id: 'Route A', steps: [
  RouteStep(point: VirtualPoint(0, 0),    instruction: 'Start – walk north',    maneuver: 'straight'),
  RouteStep(point: VirtualPoint(0, 35),   instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(30, 35),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(30, 60),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(55, 60),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(55, 85),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(80, 85),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(80, 60),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(105, 60), instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(105, 35), instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(70, 35),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(70, 10),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(40, 10),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(40, 40),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(15, 40),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(15, 70),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(0, 70),   instruction: 'Arrive at destination', maneuver: 'arrive'),
]);

const routeB = StudyRoute(id: 'Route B', steps: [
  RouteStep(point: VirtualPoint(0, 0),    instruction: 'Start – walk east',     maneuver: 'straight'),
  RouteStep(point: VirtualPoint(30, 0),   instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(30, 30),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(60, 30),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(60, 60),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(90, 60),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(90, 85),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(60, 85),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(60, 110), instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(90, 110), instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(90, 80),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(110, 80), instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(110, 50), instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(80, 50),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(80, 20),  instruction: 'Turn right',            maneuver: 'right'),
  RouteStep(point: VirtualPoint(50, 20),  instruction: 'Turn left',             maneuver: 'left'),
  RouteStep(point: VirtualPoint(50, 0),   instruction: 'Arrive at destination', maneuver: 'arrive'),
]);

// ── Navigation constants ───────────────────────────────────────────────────
class NavConst {
  static const double waypointReachRadius     = 6.0;
  static const double offRouteThreshold       = 10.0;
  static const double turnCueDistance         = 12.0;
  static const double missedTurnDistance      = 10.0;
  static const double continueCueMinSeconds   = 4.0;
  static const double sameCueCooldownSeconds  = 4.0;
  static const double wrongCueCooldownSeconds = 4.0;
  static const double studySizeMeters         = 130.0;
  static const int    globalCueLockMs         = 900;
  static const double maxAccuracyForCues      = 25.0;
}

// ── WAV generator ──────────────────────────────────────────────────────────
Uint8List generateBeepWav({required int frequency, required int durationMs, int sampleRate = 44100}) {
  final n = (sampleRate * durationMs / 1000).round();
  final dl = n * 2; final fl = 44 + dl;
  final b = ByteData(fl);
  void ws(int o, String v) { for (int i = 0; i < v.length; i++) b.setUint8(o + i, v.codeUnitAt(i)); }
  ws(0,'RIFF'); b.setUint32(4,fl-8,Endian.little); ws(8,'WAVE'); ws(12,'fmt ');
  b.setUint32(16,16,Endian.little); b.setUint16(20,1,Endian.little); b.setUint16(22,1,Endian.little);
  b.setUint32(24,sampleRate,Endian.little); b.setUint32(28,sampleRate*2,Endian.little);
  b.setUint16(32,2,Endian.little); b.setUint16(34,16,Endian.little);
  ws(36,'data'); b.setUint32(40,dl,Endian.little);
  const amp = 0.35 * 32767;
  for (int i = 0; i < n; i++) {
    final t = i / sampleRate;
    final env = math.sin(math.pi * i / n);
    final val = (math.sin(2 * math.pi * frequency * t) * env * amp).round();
    b.setInt16(44 + i * 2, val, Endian.little);
  }
  return b.buffer.asUint8List();
}

// ── Cue engine mixin ───────────────────────────────────────────────────────
mixin CueEngine {
  AudioPlayer get audioPlayer;
  FeedbackCondition get currentCondition;

  DateTime? lastAnyCueTime;
  DateTime? lastStraightCueTime;
  DateTime? lastTurnCueTime;
  DateTime? lastWrongCueTime;
  int? lastTurnCueWaypointIndex;

  void resetCueCooldowns() {
    lastStraightCueTime = null; lastTurnCueTime = null;
    lastWrongCueTime = null; lastTurnCueWaypointIndex = null;
  }

  bool cooldownReady(DateTime? last, double seconds) {
    if (last == null) return true;
    return DateTime.now().difference(last).inMilliseconds / 1000.0 >= seconds;
  }

  // Stamp lastAnyCueTime synchronously BEFORE the async playback so rapid
  // GPS ticks cannot slip through the 900ms global lock.
  bool _cueGate() {
    final now = DateTime.now();
    if (lastAnyCueTime != null &&
        now.difference(lastAnyCueTime!).inMilliseconds < NavConst.globalCueLockMs) return false;
    lastAnyCueTime = now;
    return true;
  }

  Future<bool> playCue(String m, void Function(String) log) async {
    if (!_cueGate()) return false;
    log('cue_played_$m');
    if (currentCondition == FeedbackCondition.visualAudio) { await _audioC(m); }
    else { await _hapticC(m); }
    return true;
  }

  Future<void> _audioC(String m) async {
    switch (m) {
      case 'straight': await _beep(880, 120); break;
      case 'left':
        await _beep(880, 100); await Future.delayed(const Duration(milliseconds: 120)); await _beep(880, 100); break;
      case 'right': await _beep(660, 350); break;
      case 'wrong':
        for (int i = 0; i < 3; i++) { await _beep(440, 100); if (i < 2) await Future.delayed(const Duration(milliseconds: 80)); } break;
      case 'arrive':
        // 3-note rising fanfare — distinct from all other cues
        await _beep(880, 100); await Future.delayed(const Duration(milliseconds: 70));
        await _beep(1047, 100); await Future.delayed(const Duration(milliseconds: 70));
        await _beep(1320, 280); break;
    }
  }

  Future<void> _hapticC(String m) async {
    switch (m) {
      case 'straight': await HapticFeedback.lightImpact(); break;
      case 'left':
        await HapticFeedback.lightImpact(); await Future.delayed(const Duration(milliseconds: 120)); await HapticFeedback.lightImpact(); break;
      case 'right': await HapticFeedback.mediumImpact(); break;
      case 'wrong':
        await HapticFeedback.heavyImpact(); await Future.delayed(const Duration(milliseconds: 100)); await HapticFeedback.heavyImpact(); break;
      case 'arrive':
        // Triple medium pulse — distinct from wrong (2x heavy)
        for (int i = 0; i < 3; i++) { await HapticFeedback.mediumImpact(); if (i < 2) await Future.delayed(const Duration(milliseconds: 110)); } break;
    }
  }

  Future<void> _beep(int freq, int ms) async {
    await audioPlayer.stop(); await audioPlayer.play(BytesSource(generateBeepWav(frequency: freq, durationMs: ms)));
  }
}

// ── GPS/route geometry mixin ───────────────────────────────────────────────
mixin GpsRouteMixin {
  Location get locationService;
  LatLng get fallbackCenter;

  LatLng? origin; LatLng? currentLocation;
  double userX = 0, userY = 0, currentSpeedKmh = 0;
  double? currentHeadingDegrees, currentAccuracyMeters;
  bool simulatedMode = false;
  List<LatLng> userPath = [], studyBoundary = [], fakeRoutePoints = [];
  final List<Map<String, dynamic>> pathFollowed = [];
  String gpsStatus = 'Stand at the start point, then set origin.';

  LatLng offsetLatLng(LatLng o, double east, double north) {
    const R = 6378137.0;
    final dLat = north / R; final dLng = east / (R * math.cos(math.pi * o.latitude / 180));
    return LatLng(o.latitude + dLat * 180 / math.pi, o.longitude + dLng * 180 / math.pi);
  }
  VirtualPoint latLngToV(LatLng o, LatLng c) {
    const mLat = 111320.0; final mLng = 111320.0 * math.cos(o.latitude * math.pi / 180);
    return VirtualPoint((c.longitude - o.longitude) * mLng, (c.latitude - o.latitude) * mLat);
  }
  List<LatLng> mkBoundary(LatLng o) => [
    offsetLatLng(o, 0, 0), offsetLatLng(o, NavConst.studySizeMeters, 0),
    offsetLatLng(o, NavConst.studySizeMeters, NavConst.studySizeMeters), offsetLatLng(o, 0, NavConst.studySizeMeters),
  ];
  List<LatLng> mkRoute(LatLng o, List<VirtualPoint> pts) => pts.map((p) => offsetLatLng(o, p.x, p.y)).toList();
  double distVP(VirtualPoint a, VirtualPoint b) { final dx=a.x-b.x; final dy=a.y-b.y; return math.sqrt(dx*dx+dy*dy); }
  SegmentProjection projectSeg(VirtualPoint p, VirtualPoint a, VirtualPoint b) {
    final dx=b.x-a.x; final dy=b.y-a.y;
    if (dx==0&&dy==0) return SegmentProjection(t:0,distanceToSegment:distVP(p,a),closestPoint:a);
    final rawT=((p.x-a.x)*dx+(p.y-a.y)*dy)/(dx*dx+dy*dy);
    final t=rawT.clamp(0.0,1.0).toDouble();
    final cx=a.x+t*dx; final cy=a.y+t*dy;
    final dx2=p.x-cx; final dy2=p.y-cy;
    return SegmentProjection(t:rawT,distanceToSegment:math.sqrt(dx2*dx2+dy2*dy2),closestPoint:VirtualPoint(cx,cy));
  }
  Future<bool> requestLocationPermission() async {
    try {
      if (kIsWeb) { await locationService.changeSettings(accuracy:LocationAccuracy.high,interval:1000,distanceFilter:1); return true; }
      bool svc = await locationService.serviceEnabled();
      if (!svc) { svc = await locationService.requestService(); if (!svc) return false; }
      PermissionStatus p = await locationService.hasPermission();
      if (p == PermissionStatus.denied) p = await locationService.requestPermission();
      if (p != PermissionStatus.granted && p != PermissionStatus.grantedLimited) return false;
      await locationService.changeSettings(accuracy:LocationAccuracy.high,interval:1000,distanceFilter:1);
      return true;
    } catch (_) { return false; }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HOME SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  String pid = ''; int order = 0; StudyMode mode = StudyMode.normal;
  @override void initState() { super.initState(); pid = _genId(); }
  String _genId() { final n=DateTime.now(); return 'P${n.millisecondsSinceEpoch.toString().substring(7)}'; }
  List<StudyRoute> get _routes => order == 0 ? [routeA, routeB] : [routeB, routeA];
  List<FeedbackCondition> get _conds => order == 0
    ? [FeedbackCondition.visualAudio, FeedbackCondition.visualHaptic]
    : [FeedbackCondition.visualHaptic, FeedbackCondition.visualAudio];

  void _start() {
    switch (mode) {
      case StudyMode.tutorial:
        Navigator.push(context, MaterialPageRoute(builder:(_)=>TutorialScreen(participantId:pid)));
        break;
      case StudyMode.experiment:
        Navigator.push(context, MaterialPageRoute(builder:(_)=>ExperimentMapScreen(
          participantId:pid, routeOrder:_routes, conditionOrder:_conds, routeIndex:0, allSessionLogs:const [])));
        break;
      case StudyMode.normal:
        Navigator.push(context, MaterialPageRoute(builder:(_)=>NormalMapScreen(
          participantId:pid, routeOrder:_routes, conditionOrder:_conds, routeIndex:0, allSessionLogs:const [])));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = order==0?'Route A → Route B':'Route B → Route A';
    final ct = order==0?'Visual+Audio → Visual+Haptic':'Visual+Haptic → Visual+Audio';
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title:const Text('NaMo Study Setup'),backgroundColor:Colors.white,elevation:1),
      body: SafeArea(child: SingleChildScrollView(padding:const EdgeInsets.all(20),child:Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(elevation:2,color:Colors.white,child:Padding(padding:const EdgeInsets.all(18),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              const Text('Participant ID',style:TextStyle(fontSize:14,color:Colors.grey)),
              const SizedBox(height:4),
              Text(pid,style:const TextStyle(fontSize:30,fontWeight:FontWeight.bold)),
              const SizedBox(height:8),
              OutlinedButton(onPressed:()=>setState(()=>pid=_genId()),child:const Text('Generate New ID')),
            ]))),
          const SizedBox(height:14),
          Card(elevation:2,color:Colors.white,child:Padding(padding:const EdgeInsets.all(18),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              const Text('Study Mode',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
              const SizedBox(height:12),
              SegmentedButton<StudyMode>(
                segments:const [
                  ButtonSegment(value:StudyMode.tutorial,label:Text('Tutorial'),icon:Icon(Icons.school_outlined)),
                  ButtonSegment(value:StudyMode.experiment,label:Text('Experiment'),icon:Icon(Icons.science_outlined)),
                  ButtonSegment(value:StudyMode.normal,label:Text('Normal'),icon:Icon(Icons.map_outlined)),
                ],
                selected:{mode}, onSelectionChanged:(s)=>setState(()=>mode=s.first),
              ),
              const SizedBox(height:10),
              Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.grey.shade100,borderRadius:BorderRadius.circular(8)),
                child:Text(switch(mode){
                  StudyMode.tutorial=>'Learn all 5 cue patterns then quiz until all correct. Max 3 min.',
                  StudyMode.experiment=>'Map hidden by default. Touch+hold eye button to peek. No turn-direction card.',
                  StudyMode.normal=>'Full map + instruction card always visible. Use for design & testing.',
                },style:const TextStyle(fontSize:12,color:Colors.black54))),
              if (mode != StudyMode.tutorial)...[
                const SizedBox(height:14),
                const Text('Counterbalancing Order',style:TextStyle(fontSize:14)),
                const SizedBox(height:8),
                DropdownButtonFormField<int>(value:order,
                  decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'Study order'),
                  items:const [DropdownMenuItem(value:0,child:Text('Order 1')),DropdownMenuItem(value:1,child:Text('Order 2'))],
                  onChanged:(v){if(v!=null)setState(()=>order=v);}),
                const SizedBox(height:8),
                Text('Routes: $rt',style:const TextStyle(fontSize:13)),
                Text('Conditions: $ct',style:const TextStyle(fontSize:13)),
              ],
            ]))),
          const SizedBox(height:24),
          FilledButton(onPressed:_start,
            style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16)),
            child:const Text('Start Study',style:TextStyle(fontSize:18))),
        ],
      ))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TUTORIAL SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class TutorialScreen extends StatefulWidget {
  final String participantId;
  const TutorialScreen({super.key,required this.participantId});
  @override State<TutorialScreen> createState()=>_TutorialScreenState();
}
class _TutorialScreenState extends State<TutorialScreen> with CueEngine {
  @override final AudioPlayer audioPlayer = AudioPlayer();
  FeedbackCondition _cond = FeedbackCondition.visualAudio;
  @override FeedbackCondition get currentCondition => _cond;

  int _phase = 0; // 0=pick, 1=learn, 2=quiz
  static const List<String> _cues = ['straight','left','right','wrong','arrive'];
  static const Map<String,String> _labels = {'straight':'Straight','left':'Turn Left','right':'Turn Right','wrong':'Wrong / Off-route','arrive':'Arrived'};
  static const Map<String,String> _descs = {
    'straight':'You are on track. Keep walking straight ahead.',
    'left':'A left turn is approaching within ~12 metres.',
    'right':'A right turn is approaching within ~12 metres.',
    'wrong':'You have gone off-route or missed a turn.',
    'arrive':'You have reached the destination.',
  };
  static const Map<String,String> _audioPat = {
    'straight':'1 short high beep (880 Hz)','left':'2 short high beeps (880 Hz)',
    'right':'1 longer low beep (660 Hz)','wrong':'3 fast low beeps (440 Hz)',
    'arrive':'3 rising beeps (880→1047→1320 Hz)',
  };
  static const Map<String,String> _hapticPat = {
    'straight':'1 light pulse','left':'2 light pulses','right':'1 medium pulse',
    'wrong':'2 heavy pulses','arrive':'3 medium pulses',
  };

  int _li = 0; bool _playing = false; DateTime? _t0; Timer? _maxTimer;
  final math.Random _rng = math.Random();
  final Set<String> _mastered = {};
  String? _qCue, _qSel; bool _qAnswered = false;

  @override
  void initState(){super.initState();_t0=DateTime.now();_maxTimer=Timer(const Duration(minutes:3),(){if(mounted)Navigator.pop(context);});}
  @override
  void dispose(){_maxTimer?.cancel();audioPlayer.dispose();super.dispose();}

  Future<void> _play(String c) async {
    if(_playing)return; setState(()=>_playing=true);
    lastAnyCueTime=null; await playCue(c,(_){});
    lastAnyCueTime=null; if(mounted)setState(()=>_playing=false);
  }

  void _goLearn(){setState((){_phase=1;_li=0;});_autoPlay();}

  void _autoPlay(){Future.delayed(const Duration(milliseconds:350),()async{if(mounted&&_phase==1)await _play(_cues[_li]);});}

  void _nextLearn() async {
    await _play(_cues[_li]);
    await Future.delayed(const Duration(milliseconds:350));
    if(!mounted)return;
    if(_li<_cues.length-1){setState(()=>_li++);_autoPlay();}
    else{setState((){_phase=2;_mastered.clear();_pickQ();});}
  }

  void _pickQ(){
    final rem=_cues.where((c)=>!_mastered.contains(c)).toList();
    if(rem.isEmpty)return;
    _qCue=rem[_rng.nextInt(rem.length)]; _qSel=null; _qAnswered=false;
    Future.delayed(const Duration(milliseconds:400),()async{if(mounted&&_qCue!=null)await _play(_qCue!);});
  }

  void _answer(String a) {
    if(_qAnswered||_qCue==null)return;
    final ok = a==_qCue;
    setState((){_qSel=a; _qAnswered=ok; if(ok)_mastered.add(_qCue!);});
    if(ok){
      Future.delayed(const Duration(milliseconds:1200),(){
        if(!mounted)return;
        if(_mastered.length==_cues.length)setState((){});
        else setState(()=>_pickQ());
      });
    } else {
      Future.delayed(const Duration(milliseconds:800),(){if(mounted&&!_qAnswered)setState(()=>_qSel=null);});
    }
  }

  IconData _icon(String c)=>switch(c){'straight'=>Icons.straight,'left'=>Icons.turn_left,'right'=>Icons.turn_right,'wrong'=>Icons.warning_amber_rounded,'arrive'=>Icons.flag_rounded,_=>Icons.navigation};
  Color _color(String c)=>switch(c){'straight'=>Colors.blue,'left'=>Colors.indigo,'right'=>Colors.purple,'wrong'=>Colors.red,'arrive'=>Colors.green,_=>Colors.grey};

  @override
  Widget build(BuildContext ctx){
    return Scaffold(
      backgroundColor:Colors.grey.shade50,
      appBar:AppBar(title:const Text('Tutorial Mode'),backgroundColor:Colors.white,elevation:1,
        leading:IconButton(icon:const Icon(Icons.close),onPressed:()=>Navigator.pop(ctx))),
      body:SafeArea(child:AnimatedSwitcher(duration:const Duration(milliseconds:250),child:switch(_phase){
        0=>_pickPhase(), 1=>_learnPhase(), _=>_quizPhase(),
      })),
    );
  }

  Widget _pickPhase()=>SingleChildScrollView(key:const ValueKey('p0'),padding:const EdgeInsets.all(24),child:Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,
    children:[
      const Text('Which feedback type?',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      const Text('The tutorial will demonstrate and quiz using this modality.',style:TextStyle(color:Colors.black54)),
      const SizedBox(height:28),
      _CTile(label:'Visual + Audio',icon:Icons.volume_up_rounded,sel:_cond==FeedbackCondition.visualAudio,onTap:()=>setState(()=>_cond=FeedbackCondition.visualAudio)),
      const SizedBox(height:12),
      _CTile(label:'Visual + Haptic',icon:Icons.vibration_rounded,sel:_cond==FeedbackCondition.visualHaptic,onTap:()=>setState(()=>_cond=FeedbackCondition.visualHaptic)),
      const SizedBox(height:32),
      FilledButton(onPressed:_goLearn,style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16)),child:const Text('Begin Tutorial →',style:TextStyle(fontSize:17))),
    ]));

  Widget _learnPhase(){
    final c=_cues[_li]; final isLast=_li==_cues.length-1;
    final isAudio=_cond==FeedbackCondition.visualAudio;
    final pat=isAudio?_audioPat[c]!:_hapticPat[c]!;
    final elapsed=_t0!=null?DateTime.now().difference(_t0!).inSeconds:0;
    return SingleChildScrollView(key:ValueKey('l$c'),padding:const EdgeInsets.all(24),child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,
      children:[
        Row(children:[
          Expanded(child:LinearProgressIndicator(value:(_li+1)/_cues.length,backgroundColor:Colors.grey.shade200)),
          const SizedBox(width:12),
          Text('${elapsed~/60}:${(elapsed%60).toString().padLeft(2,'0')} / 3:00',
            style:TextStyle(fontSize:12,color:elapsed>160?Colors.red:Colors.black54)),
        ]),
        const SizedBox(height:6),
        Text('Cue ${_li+1} of ${_cues.length}',style:const TextStyle(fontSize:12,color:Colors.black54)),
        const SizedBox(height:20),
        Card(elevation:3,color:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
          child:Padding(padding:const EdgeInsets.all(28),child:Column(children:[
            Icon(_icon(c),size:52,color:_color(c)),
            const SizedBox(height:12),
            Text(_labels[c]!,style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold)),
            const SizedBox(height:8),
            Text(_descs[c]!,textAlign:TextAlign.center,style:const TextStyle(fontSize:14,color:Colors.black54)),
            const SizedBox(height:20),
            Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
              decoration:BoxDecoration(color:_color(c).withOpacity(0.10),borderRadius:BorderRadius.circular(10)),
              child:Row(mainAxisSize:MainAxisSize.min,children:[
                Icon(isAudio?Icons.music_note:Icons.vibration,size:16,color:_color(c)),
                const SizedBox(width:8),
                Text(pat,style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:_color(c))),
              ])),
          ]))),
        const SizedBox(height:14),
        OutlinedButton.icon(onPressed:_playing?null:()=>_play(c),
          icon:Icon(_playing?Icons.hourglass_empty:Icons.play_circle_outline),
          label:Text(_playing?'Playing…':'Play cue again'),
          style:OutlinedButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:14))),
        const SizedBox(height:14),
        FilledButton(onPressed:_playing?null:_nextLearn,
          style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16)),
          child:Text(isLast?'Start Quiz →':'Next Cue →',style:const TextStyle(fontSize:16))),
        const SizedBox(height:20), _ftoggle(),
      ]));
  }

  Widget _quizPhase(){
    if(_mastered.length==_cues.length) return _complete();
    final rem=_cues.where((c)=>!_mastered.contains(c)).length;
    final isAudio=_cond==FeedbackCondition.visualAudio;
    return SingleChildScrollView(key:ValueKey('q${_qCue}${_qAnswered}'),padding:const EdgeInsets.all(24),child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,
      children:[
        Wrap(spacing:6,runSpacing:4,children:_cues.map((c){
          final done=_mastered.contains(c);
          return Chip(label:Text(_labels[c]!,style:TextStyle(fontSize:11,color:done?Colors.white:Colors.black87)),
            backgroundColor:done?Colors.green:Colors.grey.shade200,padding:EdgeInsets.zero,visualDensity:VisualDensity.compact);
        }).toList()),
        const SizedBox(height:6),
        Text('$rem cue${rem==1?'':'s'} left',style:const TextStyle(fontSize:13,color:Colors.black54)),
        const SizedBox(height:20),
        Card(elevation:3,color:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
          child:Padding(padding:const EdgeInsets.all(22),child:Column(children:[
            const Text('Which cue was that?',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
            const SizedBox(height:14),
            OutlinedButton.icon(onPressed:_playing||_qCue==null?null:()=>_play(_qCue!),
              icon:Icon(isAudio?Icons.replay:Icons.vibration),label:const Text('Play again')),
          ]))),
        const SizedBox(height:18),
        ..._cues.map((opt){
          final isCor=opt==_qCue; final isSel=opt==_qSel;
          Color? bg; Color? bc;
          if(_qAnswered&&isCor&&isSel){bg=Colors.green.shade50;bc=Colors.green;}
          else if(!_qAnswered&&isSel){bg=Colors.red.shade50;bc=Colors.red;}
          return Padding(padding:const EdgeInsets.only(bottom:10),child:AnimatedContainer(
            duration:const Duration(milliseconds:180),
            decoration:BoxDecoration(color:bg??Colors.white,
              border:Border.all(color:bc??Colors.grey.shade300,width:bc!=null?2:1),
              borderRadius:BorderRadius.circular(12)),
            child:ListTile(
              leading:Icon(_icon(opt),color:bc??_color(opt)),
              title:Text(_labels[opt]!,style:TextStyle(fontWeight:isSel?FontWeight.bold:FontWeight.normal)),
              trailing:(_qAnswered&&isCor&&isSel)?const Icon(Icons.check_circle,color:Colors.green)
                :(!_qAnswered&&isSel)?const Icon(Icons.cancel,color:Colors.red):null,
              onTap:()=>_answer(opt),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)))));
        }),
        const SizedBox(height:14), _ftoggle(),
      ]));
  }

  Widget _complete()=>Padding(key:const ValueKey('done'),padding:const EdgeInsets.all(32),child:Column(
    mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.stretch,
    children:[
      const Icon(Icons.check_circle_rounded,color:Colors.green,size:80),
      const SizedBox(height:20),
      const Text('Tutorial Complete!',textAlign:TextAlign.center,style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),
      const SizedBox(height:10),
      const Text('All cue types identified correctly.\nYou are ready for the study.',textAlign:TextAlign.center,style:TextStyle(fontSize:16,color:Colors.black54)),
      const SizedBox(height:40),
      FilledButton(onPressed:()=>Navigator.pop(context),style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:16)),child:const Text('Back to Home',style:TextStyle(fontSize:17))),
    ]));

  Widget _ftoggle()=>Card(color:Colors.white,elevation:1,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
      const Text('Feedback: '),const SizedBox(width:8),
      SegmentedButton<FeedbackCondition>(
        segments:const [
          ButtonSegment(value:FeedbackCondition.visualAudio,label:Text('Audio'),icon:Icon(Icons.volume_up,size:16)),
          ButtonSegment(value:FeedbackCondition.visualHaptic,label:Text('Haptic'),icon:Icon(Icons.vibration,size:16)),
        ],
        selected:{_cond}, onSelectionChanged:(s)=>setState(()=>_cond=s.first)),
    ])));
}

class _CTile extends StatelessWidget {
  final String label; final IconData icon; final bool sel; final VoidCallback onTap;
  const _CTile({required this.label,required this.icon,required this.sel,required this.onTap});
  @override Widget build(BuildContext ctx)=>AnimatedContainer(duration:const Duration(milliseconds:160),
    decoration:BoxDecoration(color:sel?Colors.blue.shade50:Colors.white,
      border:Border.all(color:sel?Colors.blue:Colors.grey.shade300,width:sel?2:1),borderRadius:BorderRadius.circular(14)),
    child:ListTile(leading:Icon(icon,color:sel?Colors.blue:Colors.grey),
      title:Text(label,style:TextStyle(fontWeight:sel?FontWeight.bold:FontWeight.normal,color:sel?Colors.blue.shade800:Colors.black87)),
      trailing:sel?const Icon(Icons.check_circle,color:Colors.blue):null,onTap:onTap,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))));
}

// ═══════════════════════════════════════════════════════════════════════════
// BASE MAP STATE — shared logic for both Experiment and Normal screens
// ═══════════════════════════════════════════════════════════════════════════
abstract class _BaseMapScreen extends StatefulWidget {
  final String participantId;
  final List<StudyRoute> routeOrder;
  final List<FeedbackCondition> conditionOrder;
  final int routeIndex;
  final List<Map<String, dynamic>> allSessionLogs;
  const _BaseMapScreen({super.key, required this.participantId, required this.routeOrder,
    required this.conditionOrder, required this.routeIndex, required this.allSessionLogs});
}

abstract class BaseMapState<T extends _BaseMapScreen> extends State<T> with CueEngine, GpsRouteMixin {
  @override final AudioPlayer audioPlayer = AudioPlayer();
  @override final Location locationService = Location();
  @override final LatLng fallbackCenter = const LatLng(52.0907, 5.1214);

  late StudyRoute currentRoute;
  late FeedbackCondition _cond;
  @override FeedbackCondition get currentCondition => _cond;
  late RouteSession session;
  StreamSubscription<LocationData>? _sub;
  final MapController mapController = MapController();
  LatLng? mapCenter; double currentZoom = 19.5;

  int currentStep = 0;
  bool routeStarted = false, gpsActive = false, waitingGps = false, realtimeEnabled = true, ctrlVisible = true;

  String condText(FeedbackCondition c) => c == FeedbackCondition.visualAudio ? 'Visual + Audio' : 'Visual + Haptic';

  @override
  void initState() {
    super.initState();
    currentRoute = widget.routeOrder[widget.routeIndex];
    _cond        = widget.conditionOrder[widget.routeIndex];
    session = RouteSession(participantId:widget.participantId, routeId:currentRoute.id,
      condition:condText(_cond), startTime:DateTime.now(), events:[]);
    logEvent('screen_opened');
    // Auto-start GPS on every route screen (including second/third routes).
    // Both Normal and Experiment mode need a fresh subscription each time.
    WidgetsBinding.instance.addPostFrameCallback((_) => startGps());
  }

  @override
  void dispose(){ _sub?.cancel(); audioPlayer.dispose(); super.dispose(); }

  void logEvent(String t) => session.events.add(StudyEvent(type:t, timestamp:DateTime.now(), stepIndex:currentStep));

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> startGps() async {
    setState((){ gpsStatus='Checking permission…'; waitingGps=true; });
    final ok = await requestLocationPermission();
    if (!ok) { setState((){waitingGps=false;gpsStatus='Permission denied.';}); logEvent('permission_failed'); return; }
    setState(()=>gpsStatus='Waiting for GPS…');
    await _listen();
  }

  Future<void> _listen() async {
    await _sub?.cancel(); bool first = false;
    _sub = locationService.onLocationChanged.listen(
      (d) { if(d.latitude==null||d.longitude==null)return; final pos=LatLng(d.latitude!,d.longitude!);
        if(!first){first=true;_init(pos,d);}else{_update(d);} },
      onError:(e){if(!mounted)return;setState((){waitingGps=false;gpsStatus='GPS error:$e';});logEvent('gps_error');},
    );
    Future.delayed(const Duration(seconds:30),(){if(!mounted||routeStarted)return;setState((){waitingGps=false;gpsStatus='GPS timeout.';});logEvent('gps_timeout');});
  }

  void _init(LatLng start, LocationData d) {
    origin=start; currentLocation=start; mapCenter=start;
    studyBoundary=mkBoundary(start); fakeRoutePoints=mkRoute(start,currentRoute.points);
    setState((){routeStarted=true;gpsActive=true;simulatedMode=false;waitingGps=false;
      currentStep=0;session.currentStep=0;userX=0;userY=0;
      currentSpeedKmh=(d.speed??0)*3.6;currentHeadingDegrees=d.heading;currentAccuracyMeters=d.accuracy;
      userPath=[start];
      gpsStatus='GPS active ±${(d.accuracy??0).toStringAsFixed(1)} m';
    });
    logEvent('gps_origin_set'); onRouteInitialized();
    mapController.move(start, currentZoom);
  }

  void _update(LocationData d) {
    if(origin==null||d.latitude==null||d.longitude==null)return;
    final pos=LatLng(d.latitude!,d.longitude!); final v=latLngToV(origin!,pos); final acc=d.accuracy??0.0;
    setState((){
      currentLocation=pos; userX=v.x; userY=v.y;
      currentSpeedKmh=(d.speed??0)*3.6; currentHeadingDegrees=d.heading; currentAccuracyMeters=acc;
      userPath.add(pos);
      pathFollowed.add({'timestamp':DateTime.now().toIso8601String(),'lat':pos.latitude,'lng':pos.longitude,
        'virtualX':userX,'virtualY':userY,'accuracy':acc,'heading':d.heading,'stepIndex':currentStep});
      gpsStatus='x=${userX.toStringAsFixed(1)}, y=${userY.toStringAsFixed(1)} ±${acc.toStringAsFixed(1)} m';
    });
    if(realtimeEnabled) evalCues(); // fire-and-forget async; gate prevents overlap
    onLocationUpdated();
  }

  void simMode() {
    _sub?.cancel(); origin=fallbackCenter;
    currentLocation=offsetLatLng(fallbackCenter,0,0); mapCenter=currentLocation;
    studyBoundary=mkBoundary(fallbackCenter); fakeRoutePoints=mkRoute(fallbackCenter,currentRoute.points);
    setState((){routeStarted=true;gpsActive=false;simulatedMode=true;waitingGps=false;
      currentStep=0;session.currentStep=0;userX=0;userY=0;userPath=[currentLocation!];gpsStatus='Simulated mode';});
    logEvent('simulated_mode_started'); onRouteInitialized();
    mapController.move(fallbackCenter,currentZoom);
  }

  // ── Cue engine ─────────────────────────────────────────────────────────────
  // Called on every GPS update. async so each playCue is properly awaited.
  // Accuracy guard is relaxed to 50 m so web/browser GPS is not silently
  // blocked (browser accuracy is often 20-100 m even with a good fix).
  Future<void> evalCues() async {
    if(!routeStarted)return;
    if(currentStep>=currentRoute.points.length-1)return;
    // Skip only if accuracy is truly terrible (> 50 m)
    if((currentAccuracyMeters??0)>50.0)return;

    final user=VirtualPoint(userX,userY);
    final sS=currentRoute.points[currentStep]; final sE=currentRoute.points[currentStep+1];
    final proj=projectSeg(user,sS,sE); final dSeg=proj.distanceToSegment; final dNext=distVP(user,sE);
    final now=DateTime.now();

    // 1. Off-route
    if(dSeg>NavConst.offRouteThreshold){
      if(cooldownReady(lastWrongCueTime,NavConst.wrongCueCooldownSeconds)){
        lastWrongCueTime=now; logEvent('off_route_detected'); await playCue('wrong',logEvent);
      }
      return;
    }

    // 2. Missed turn (shot past waypoint)
    if(proj.t>1.15&&dNext>NavConst.missedTurnDistance){
      if(cooldownReady(lastWrongCueTime,NavConst.wrongCueCooldownSeconds)){
        lastWrongCueTime=now; logEvent('missed_turn_detected'); await playCue('wrong',logEvent);
      }
      return;
    }

    // 3. Waypoint reached — advance step
    if(dNext<=NavConst.waypointReachRadius){
      setState((){currentStep++;session.currentStep=currentStep;lastTurnCueWaypointIndex=null;});
      logEvent('realtime_reached_waypoint');
      if(currentStep>=currentRoute.points.length-1){
        await playCue('arrive',logEvent); logEvent('realtime_arrived');
      }
      return;
    }

    // 4. Approaching a turn
    final nm=currentStep+1<currentRoute.steps.length?currentRoute.steps[currentStep+1].maneuver:'arrive';
    if(dNext<=NavConst.turnCueDistance&&(nm=='left'||nm=='right')){
      final tgt=currentStep+1;
      if(lastTurnCueWaypointIndex!=tgt||cooldownReady(lastTurnCueTime,NavConst.sameCueCooldownSeconds)){
        lastTurnCueTime=now; lastTurnCueWaypointIndex=tgt;
        logEvent('realtime_turn_cue_$nm'); await playCue(nm,logEvent);
      }
      return;
    }

    // 5. Straight / continue — fires every 4 s while correctly on segment
    if(cooldownReady(lastStraightCueTime,NavConst.continueCueMinSeconds)){
      lastStraightCueTime=now; logEvent('realtime_straight_cue'); await playCue('straight',logEvent);
    }
  }

  // ── Manual ────────────────────────────────────────────────────────────────
  void manualCue(String c){logEvent('manual_cue_$c');playCue(c,logEvent);}

  void manualReached(){
    if(!routeStarted)return;
    if(currentStep>=currentRoute.points.length-1){logEvent('manual_finish');playCue('arrive',logEvent);endRoute(completed:true);return;}
    setState((){currentStep++;session.currentStep=currentStep;
      if(simulatedMode&&origin!=null){final p=currentRoute.points[currentStep];userX=p.x;userY=p.y;
        currentLocation=offsetLatLng(origin!,userX,userY);userPath.add(currentLocation!);
        pathFollowed.add({'timestamp':DateTime.now().toIso8601String(),'mode':'simulated','virtualX':userX,'virtualY':userY,'stepIndex':currentStep});}
    });
    logEvent('manual_reached'); playCue(currentRoute.steps[currentStep].maneuver,logEvent);
  }

  void toggleRealtime(){
    setState((){realtimeEnabled=!realtimeEnabled;if(!realtimeEnabled)resetCueCooldowns();});
    logEvent(realtimeEnabled?'realtime_enabled':'realtime_disabled');
  }

  void recalcArea(){
    if(currentLocation==null)return; final no=currentLocation!; origin=no;
    studyBoundary=mkBoundary(no); fakeRoutePoints=mkRoute(no,currentRoute.points);
    setState((){currentStep=0;session.currentStep=0;userX=0;userY=0;userPath=[no];resetCueCooldowns();gpsStatus='Recalculated. (0,0)=current.';});
    logEvent('area_recalculated'); mapCenter=no; currentZoom=19.5; mapController.move(no,currentZoom);
  }

  // ── End route ─────────────────────────────────────────────────────────────
  Future<void> endRoute({required bool completed}) async {
    await _sub?.cancel();
    onBeforeEnd();
    session.endTime=DateTime.now(); session.completed=completed; session.currentStep=currentStep;
    logEvent(completed?'route_completed':'route_terminated');
    final j=session.toJson();
    j['routeDefinition']=currentRoute.toJson();
    j['origin']=origin==null?null:{'lat':origin!.latitude,'lng':origin!.longitude};
    j['trackingMode']=simulatedMode?'simulated':'gps'; j['pathFollowed']=pathFollowed;
    j['gpsTrackingActive']=gpsActive; j['finalAccuracyMeters']=currentAccuracyMeters;
    j['finalVirtualPosition']={'x':userX,'y':userY}; j['realtimeCuesEnabledAtEnd']=realtimeEnabled;
    addExtraSessionData(j);
    final logs=[...widget.allSessionLogs, j];
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString('namo_${widget.participantId}',jsonEncode(logs));
    if(!mounted)return;

    final nextIndex = widget.routeIndex + 1;
    final hasNext   = nextIndex < widget.routeOrder.length;

    if (hasNext) {
      // Launch the same screen type (Experiment or Normal) for the next route,
      // preserving the counterbalanced order chosen on the home screen.
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => nextScreenForMode(
          participantId:  widget.participantId,
          routeOrder:     widget.routeOrder,
          conditionOrder: widget.conditionOrder,
          routeIndex:     nextIndex,
          allSessionLogs: logs,
        ),
      ));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder:(_)=>SummaryScreen(
        participantId:widget.participantId, routeOrder:widget.routeOrder, conditionOrder:widget.conditionOrder,
        finishedRouteIndex:widget.routeIndex, allSessionLogs:logs)));
    }
  }

  /// Subclasses return the correct next-screen widget (Experiment or Normal).
  // implemented via nextScreenForMode hook below

  // ── Hooks for subclasses ──────────────────────────────────────────────────
  void onRouteInitialized() {}
  void onLocationUpdated() {}
  void onBeforeEnd() {}
  void addExtraSessionData(Map<String,dynamic> j) {}
  // Must be implemented by each subclass to return the correct screen type.
  Widget nextScreenForMode({
    required String participantId,
    required List<StudyRoute> routeOrder,
    required List<FeedbackCondition> conditionOrder,
    required int routeIndex,
    required List<Map<String,dynamic>> allSessionLogs,
  });

  // ── Shared map layers ─────────────────────────────────────────────────────
  List<Widget> mapLayers() => [
    TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.example.namo'),
    if(studyBoundary.length>=3)PolygonLayer(polygons:[Polygon(points:studyBoundary,color:Colors.blue.withOpacity(0.08),borderColor:Colors.blueAccent,borderStrokeWidth:3)]),
    if(fakeRoutePoints.length>=2)PolylineLayer(polylines:[Polyline(points:fakeRoutePoints,strokeWidth:6,color:Colors.black)]),
    if(userPath.length>=2)PolylineLayer(polylines:[Polyline(points:userPath,strokeWidth:4,color:Colors.blue)]),
    MarkerLayer(markers:[
      if(fakeRoutePoints.isNotEmpty)Marker(point:fakeRoutePoints.first,width:50,height:50,child:const Icon(Icons.location_on,color:Colors.green,size:34)),
      if(fakeRoutePoints.length>1&&currentStep<fakeRoutePoints.length)Marker(point:fakeRoutePoints[currentStep],width:50,height:50,child:const Icon(Icons.adjust,color:Colors.orange,size:30)),
      if(fakeRoutePoints.isNotEmpty)Marker(point:fakeRoutePoints.last,width:50,height:50,child:const Icon(Icons.flag,color:Colors.red,size:34)),
      if(currentLocation!=null)Marker(point:currentLocation!,width:72,height:72,child:_LocMarker(heading:currentHeadingDegrees,active:gpsActive&&!simulatedMode)),
    ]),
  ];

  Widget researcherPanel() => _RPanel(
    isLastStep:currentStep>=currentRoute.points.length-1,
    speedText:simulatedMode?'Simulated':'${currentSpeedKmh.toStringAsFixed(1)} km/h${currentAccuracyMeters==null?'':' · ±${currentAccuracyMeters!.toStringAsFixed(1)} m'}',
    realtimeEnabled:realtimeEnabled, ctrlVisible:ctrlVisible,
    onToggleVis:()=>setState(()=>ctrlVisible=!ctrlVisible),
    onToggleRt:toggleRealtime, onReached:manualReached,
    onCueLeft:()=>manualCue('left'), onCueStraight:()=>manualCue('straight'),
    onCueWrong:()=>manualCue('wrong'), onCueRight:()=>manualCue('right'),
    onCenter:(){if(currentLocation!=null){mapCenter=currentLocation;currentZoom=20.5;mapController.move(currentLocation!,currentZoom);}},
    onTest:()=>manualCue(currentRoute.steps[currentStep].maneuver),
    onEnd:()=>endRoute(completed:false),
  );

  Widget startOverlay() => Center(child:Card(elevation:8,color:Colors.white,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
    child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(waitingGps?Icons.gps_not_fixed:Icons.gps_fixed,size:42,color:Colors.blue),
      const SizedBox(height:12),
      Text(waitingGps?'Waiting for GPS…':'Set study origin',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      const Text('Stand at the start point.\nFirst GPS fix becomes virtual (0, 0).',textAlign:TextAlign.center),
      const SizedBox(height:16),
      FilledButton(onPressed:waitingGps?null:startGps,child:const Text('Start Route & Set Origin')),
      const SizedBox(height:8),
      OutlinedButton(onPressed:simMode,child:const Text('Use Simulated Mode')),
    ]))));
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPERIMENT MAP SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class ExperimentMapScreen extends _BaseMapScreen {
  const ExperimentMapScreen({super.key, required super.participantId, required super.routeOrder,
    required super.conditionOrder, required super.routeIndex, required super.allSessionLogs});
  @override State<ExperimentMapScreen> createState()=>_ExpMapState();
}
class _ExpMapState extends BaseMapState<ExperimentMapScreen> {
  bool _peek=false; int _peekCount=0; double _peekMs=0; DateTime? _peekT;
  final List<Map<String,dynamic>> _glances=[];

  @override
  Widget nextScreenForMode({required String participantId, required List<StudyRoute> routeOrder,
    required List<FeedbackCondition> conditionOrder, required int routeIndex, required List<Map<String,dynamic>> allSessionLogs}) =>
    ExperimentMapScreen(participantId:participantId, routeOrder:routeOrder, conditionOrder:conditionOrder,
      routeIndex:routeIndex, allSessionLogs:allSessionLogs);

  void _peekStart(){if(_peek)return;_peek=true;_peekT=DateTime.now();_peekCount++;
    _glances.add({'event':'peek_start','timestamp':DateTime.now().toIso8601String(),'stepIndex':currentStep,'peekNumber':_peekCount});
    logEvent('experiment_peek_start'); setState((){});}

  void _peekEnd(){if(!_peek)return;_peek=false;
    final ms=_peekT!=null?DateTime.now().difference(_peekT!).inMilliseconds.toDouble():0.0;
    _peekMs+=ms; _peekT=null;
    _glances.add({'event':'peek_end','timestamp':DateTime.now().toIso8601String(),'durationMs':ms.round(),'stepIndex':currentStep});
    logEvent('experiment_peek_end'); setState((){});}

  @override void onBeforeEnd(){if(_peek)_peekEnd();}

  @override void addExtraSessionData(Map<String,dynamic> j){
    j['experimentMetrics']={'peekCount':_peekCount,'totalPeekMs':_peekMs.round(),
      'totalPeekSeconds':(_peekMs/1000).toStringAsFixed(1),'glanceEvents':_glances};
  }

  @override
  Widget build(BuildContext ctx){
    final center=currentLocation??origin??fallbackCenter;
    return Scaffold(body:Stack(children:[
      // Map always rendered; hidden behind dark overlay when not peeking
      FlutterMap(mapController:mapController,
        options:MapOptions(initialCenter:center,initialZoom:currentZoom,minZoom:3,maxZoom:22,
          interactionOptions:const InteractionOptions(flags:InteractiveFlag.all&~InteractiveFlag.rotate)),
        children:mapLayers()),
      if(!_peek) Container(color:Colors.grey.shade900),
      // GPS status card — no turn directions
      Positioned(top:48,left:16,right:16,child:SafeArea(child:_GpsCard(
        waitingGps:waitingGps, started:routeStarted, status:gpsStatus,
        rtEnabled:realtimeEnabled, cond:condText(_cond),
        routeId:currentRoute.id, stepText:'Step ${currentStep+1} of ${currentRoute.steps.length}'))),
      // Peek metrics
      Positioned(top:52,right:16,child:SafeArea(child:_PeekCard(count:_peekCount,totalSec:_peekMs/1000))),
      // Start overlay
      if(!routeStarted) startOverlay(),
      // Researcher controls
      if(routeStarted) Positioned(bottom:92,left:16,right:16,child:researcherPanel()),
      // Peek button
      Positioned(bottom:20,left:0,right:0,child:Center(child:GestureDetector(
        onTapDown:(_)=>_peekStart(), onTapUp:(_)=>_peekEnd(), onTapCancel:()=>_peekEnd(),
        child:AnimatedContainer(duration:const Duration(milliseconds:150),
          padding:const EdgeInsets.symmetric(horizontal:28,vertical:16),
          decoration:BoxDecoration(color:_peek?Colors.white.withOpacity(0.95):Colors.white.withOpacity(0.18),
            borderRadius:BorderRadius.circular(40),
            border:Border.all(color:_peek?Colors.blue:Colors.white54,width:2)),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            Icon(_peek?Icons.visibility:Icons.visibility_outlined,color:_peek?Colors.blue:Colors.white,size:26),
            const SizedBox(width:10),
            Text(_peek?'Viewing map…':'Hold to peek at map',
              style:TextStyle(color:_peek?Colors.blue.shade800:Colors.white,fontWeight:FontWeight.w600,fontSize:16)),
          ]))))),
    ]));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NORMAL MAP SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class NormalMapScreen extends _BaseMapScreen {
  const NormalMapScreen({super.key, required super.participantId, required super.routeOrder,
    required super.conditionOrder, required super.routeIndex, required super.allSessionLogs});
  @override State<NormalMapScreen> createState()=>_NormMapState();
}
class _NormMapState extends BaseMapState<NormalMapScreen> {
  String get _instr {
    if(!routeStarted)return waitingGps?'Waiting for GPS':'Set study origin';
    if(currentStep>=currentRoute.steps.length)return 'Arrive at destination';
    return currentRoute.steps[currentStep].instruction;
  }
  IconData get _icon {
    if(!routeStarted)return waitingGps?Icons.gps_not_fixed:Icons.gps_fixed;
    if(currentStep>=currentRoute.steps.length)return Icons.flag;
    return switch(currentRoute.steps[currentStep].maneuver){'left'=>Icons.turn_left,'right'=>Icons.turn_right,'arrive'=>Icons.flag,_=>Icons.straight};
  }

  void _zoomIn(){final c=mapCenter??currentLocation??fallbackCenter;currentZoom=(currentZoom+0.75).clamp(3.0,22.0);mapController.move(c,currentZoom);}
  void _zoomOut(){final c=mapCenter??currentLocation??fallbackCenter;currentZoom=(currentZoom-0.75).clamp(3.0,22.0);mapController.move(c,currentZoom);}

  @override
  Widget nextScreenForMode({required String participantId, required List<StudyRoute> routeOrder,
    required List<FeedbackCondition> conditionOrder, required int routeIndex, required List<Map<String,dynamic>> allSessionLogs}) =>
    NormalMapScreen(participantId:participantId, routeOrder:routeOrder, conditionOrder:conditionOrder,
      routeIndex:routeIndex, allSessionLogs:allSessionLogs);

  @override
  Widget build(BuildContext ctx){
    final center=currentLocation??origin??fallbackCenter;
    return Scaffold(body:Stack(children:[
      FlutterMap(mapController:mapController,
        options:MapOptions(initialCenter:center,initialZoom:currentZoom,minZoom:3,maxZoom:22,
          interactionOptions:const InteractionOptions(flags:InteractiveFlag.all&~InteractiveFlag.rotate),
          onMapEvent:(e){mapCenter=e.camera.center;currentZoom=e.camera.zoom;}),
        children:mapLayers()),
      Positioned(top:48,left:16,right:16,child:SafeArea(child:_ICard(
        instruction:_instr, routeId:currentRoute.id, cond:condText(_cond),
        stepText:'Step ${currentStep+1} of ${currentRoute.steps.length}',
        status:gpsStatus, icon:_icon, rtEnabled:realtimeEnabled))),
      Positioned(top:210,right:16,child:_MapBtns(onIn:_zoomIn,onOut:_zoomOut,onRecalc:recalcArea)),
      if(!routeStarted) startOverlay(),
      if(routeStarted) Positioned(bottom:20,left:16,right:16,child:researcherPanel()),
    ]));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════
class _LocMarker extends StatelessWidget {
  final double? heading; final bool active;
  const _LocMarker({required this.heading, required this.active});
  @override Widget build(BuildContext ctx){
    final r=((heading??0)*math.pi)/180;
    return Stack(alignment:Alignment.center,children:[
      Container(width:44,height:44,decoration:BoxDecoration(color:Colors.blue.withOpacity(0.18),shape:BoxShape.circle)),
      Container(width:24,height:24,decoration:BoxDecoration(color:active?Colors.blue:Colors.grey,shape:BoxShape.circle,
        border:Border.all(color:Colors.white,width:3),
        boxShadow:const [BoxShadow(blurRadius:8,spreadRadius:1,color:Colors.black26)])),
      if(heading!=null)Transform.rotate(angle:r,child:const Padding(padding:EdgeInsets.only(bottom:38),
        child:Icon(Icons.navigation,color:Colors.blue,size:26))),
    ]);
  }
}

class _ICard extends StatelessWidget {
  final String instruction, routeId, cond, stepText, status;
  final IconData icon; final bool rtEnabled;
  const _ICard({required this.instruction,required this.routeId,required this.cond,required this.stepText,required this.status,required this.icon,required this.rtEnabled});
  @override Widget build(BuildContext ctx)=>Card(elevation:8,color:Colors.white,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
    child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      Container(width:52,height:52,decoration:BoxDecoration(color:rtEnabled?Colors.blue.shade600:Colors.grey,shape:BoxShape.circle),
        child:Icon(icon,color:Colors.white,size:30)),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(instruction,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const SizedBox(height:3),
        Text('$routeId · $cond · $stepText',style:TextStyle(fontSize:12,color:Colors.grey.shade700)),
        const SizedBox(height:3),
        Row(children:[
          Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
            decoration:BoxDecoration(color:rtEnabled?Colors.green.shade100:Colors.red.shade100,borderRadius:BorderRadius.circular(6)),
            child:Text(rtEnabled?'Cues ON':'Cues OFF',style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,
              color:rtEnabled?Colors.green.shade800:Colors.red.shade800))),
          const SizedBox(width:8),
          Expanded(child:Text(status,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11,color:Colors.grey.shade600))),
        ]),
      ])),
    ])));
}

class _GpsCard extends StatelessWidget {
  final bool waitingGps, started, rtEnabled; final String status, cond, routeId, stepText;
  const _GpsCard({required this.waitingGps,required this.started,required this.status,required this.rtEnabled,required this.cond,required this.routeId,required this.stepText});
  @override Widget build(BuildContext ctx)=>Card(elevation:8,color:Colors.white,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),child:Row(children:[
      Icon(waitingGps?Icons.gps_not_fixed:(started?Icons.gps_fixed:Icons.location_searching),size:28,color:Colors.blue),
      const SizedBox(width:12),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('$routeId · $cond · $stepText',style:TextStyle(fontSize:12,color:Colors.grey.shade700)),
        const SizedBox(height:2),
        Text(status,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12)),
      ])),
      if(rtEnabled)Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
        decoration:BoxDecoration(color:Colors.green.shade100,borderRadius:BorderRadius.circular(10)),
        child:Text('Cues ON',style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:Colors.green.shade800))),
    ])));
}

class _PeekCard extends StatelessWidget {
  final int count; final double totalSec;
  const _PeekCard({required this.count,required this.totalSec});
  @override Widget build(BuildContext ctx)=>Card(elevation:4,color:Colors.black87,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12)),
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),child:Column(
      crossAxisAlignment:CrossAxisAlignment.end,mainAxisSize:MainAxisSize.min,children:[
        Text('Peeks: $count',style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.bold)),
        const SizedBox(height:2),
        Text('${totalSec.toStringAsFixed(1)} s visible',style:const TextStyle(color:Colors.white70,fontSize:11)),
      ])));
}

class _MapBtns extends StatelessWidget {
  final VoidCallback onIn, onOut, onRecalc;
  const _MapBtns({required this.onIn,required this.onOut,required this.onRecalc});
  @override Widget build(BuildContext ctx)=>Card(elevation:6,color:Colors.white,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      IconButton(tooltip:'Zoom in',onPressed:onIn,icon:const Icon(Icons.add)),
      const Divider(height:1),
      IconButton(tooltip:'Zoom out',onPressed:onOut,icon:const Icon(Icons.remove)),
      const Divider(height:1),
      IconButton(tooltip:'Recalculate area',onPressed:onRecalc,icon:const Icon(Icons.gps_fixed)),
    ]));
}

class _RPanel extends StatelessWidget {
  final bool isLastStep, realtimeEnabled, ctrlVisible;
  final String speedText;
  final VoidCallback onToggleVis, onToggleRt, onReached, onCueLeft, onCueStraight, onCueWrong, onCueRight, onCenter, onTest, onEnd;
  const _RPanel({required this.isLastStep,required this.speedText,required this.realtimeEnabled,required this.ctrlVisible,
    required this.onToggleVis,required this.onToggleRt,required this.onReached,
    required this.onCueLeft,required this.onCueStraight,required this.onCueWrong,required this.onCueRight,
    required this.onCenter,required this.onTest,required this.onEnd});
  @override Widget build(BuildContext ctx)=>Card(elevation:8,color:Colors.white,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),
    child:Padding(padding:const EdgeInsets.fromLTRB(14,8,14,12),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Text('Researcher · $speedText',style:TextStyle(fontSize:11,color:Colors.grey.shade600)),
        IconButton(tooltip:ctrlVisible?'Hide':'Show',onPressed:onToggleVis,
          icon:Icon(ctrlVisible?Icons.expand_more:Icons.expand_less,size:20),
          visualDensity:VisualDensity.compact,padding:EdgeInsets.zero,constraints:const BoxConstraints()),
      ]),
      if(ctrlVisible)...[
        const SizedBox(height:6),
        FilledButton(onPressed:onToggleRt,
          style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(40),backgroundColor:realtimeEnabled?Colors.green:Colors.red),
          child:Text(realtimeEnabled?'Disable Real-Time Cues':'Enable Real-Time Cues')),
        const SizedBox(height:6),
        FilledButton(onPressed:onReached,
          style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(44)),
          child:Text(isLastStep?'Finish Route':'Reached Point')),
        const SizedBox(height:6),
        // Cue row: LEFT | STRAIGHT | WRONG (red) | RIGHT
        Row(children:[
          Expanded(child:OutlinedButton(onPressed:onCueLeft,
            style:OutlinedButton.styleFrom(foregroundColor:Colors.blue,side:const BorderSide(color:Colors.blue)),
            child:const Text('Left'))),
          const SizedBox(width:6),
          Expanded(child:OutlinedButton(onPressed:onCueStraight,
            style:OutlinedButton.styleFrom(foregroundColor:Colors.green.shade700,side:BorderSide(color:Colors.green.shade700)),
            child:const Text('Straight'))),
          const SizedBox(width:6),
          Expanded(child:OutlinedButton(onPressed:onCueWrong,
            style:OutlinedButton.styleFrom(foregroundColor:Colors.red.shade700,backgroundColor:Colors.red.shade50,side:BorderSide(color:Colors.red.shade400)),
            child:const Text('Wrong'))),
          const SizedBox(width:6),
          Expanded(child:OutlinedButton(onPressed:onCueRight,
            style:OutlinedButton.styleFrom(foregroundColor:Colors.orange.shade700,side:BorderSide(color:Colors.orange.shade700)),
            child:const Text('Right'))),
        ]),
        Row(children:[
          Expanded(child:TextButton(onPressed:onCenter,child:const Text('Center'))),
          Expanded(child:TextButton(onPressed:onTest,child:const Text('Test'))),
          Expanded(child:TextButton(onPressed:onEnd,child:const Text('End'))),
        ]),
      ],
    ])));
}

// ═══════════════════════════════════════════════════════════════════════════
// SUMMARY SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class SummaryScreen extends StatelessWidget {
  final String participantId;
  final List<StudyRoute> routeOrder;
  final List<FeedbackCondition> conditionOrder;
  final int finishedRouteIndex;
  final List<Map<String, dynamic>> allSessionLogs;
  const SummaryScreen({super.key, required this.participantId, required this.routeOrder,
    required this.conditionOrder, required this.finishedRouteIndex, required this.allSessionLogs});

  bool get hasNext => finishedRouteIndex+1 < routeOrder.length;

  @override
  Widget build(BuildContext ctx){
    final j=const JsonEncoder.withIndent('  ').convert(allSessionLogs);
    return Scaffold(
      backgroundColor:Colors.grey.shade50,
      appBar:AppBar(title:const Text('Route Summary'),backgroundColor:Colors.white,elevation:1),
      body:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Card(color:Colors.white,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(hasNext?'Route saved. Ready for next route.':'Study complete.',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          Text('Participant: $participantId'),
          Text('Completed routes: ${allSessionLogs.length}'),
        ]))),
        const SizedBox(height:12),
        Expanded(child:Card(color:Colors.white,child:Padding(padding:const EdgeInsets.all(12),
          child:SingleChildScrollView(child:SelectableText(j,style:const TextStyle(fontSize:11)))))),
        const SizedBox(height:12),
        OutlinedButton(onPressed:()async{
          await Clipboard.setData(ClipboardData(text:j));
          if(!ctx.mounted)return;
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('JSON copied')));
        },child:const Text('Copy JSON')),
        const SizedBox(height:8),
        FilledButton(onPressed:()=>Navigator.pushAndRemoveUntil(ctx,MaterialPageRoute(builder:(_)=>const HomeScreen()),(_)=>false),
          child:Text(hasNext?'Home (start next route)':'Start New Participant')),
      ])),
    );
  }
}
