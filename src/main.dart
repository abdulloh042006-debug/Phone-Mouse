import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ch = MethodChannel('mouse');

class Skin {
  final String name;
  final Color top, bottom, btn, accent, text;
  const Skin(this.name, this.top, this.bottom, this.btn, this.accent, this.text);
}

const skins = [
  Skin('Neon', Color(0xFF1E1E3A), Color(0xFF0A0A16), Color(0xFF2A2A52), Color(0xFF00E5FF), Colors.white),
  Skin('Klassik', Color(0xFFF5F5F7), Color(0xFFC9C9D1), Color(0xFFFFFFFF), Color(0xFF3D5AFE), Color(0xFF222222)),
  Skin('Oltin', Color(0xFF332A1A), Color(0xFF0F0C07), Color(0xFF45391F), Color(0xFFFFC107), Color(0xFFFFE9A8)),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MouseApp()));
}

class MouseApp extends StatefulWidget {
  const MouseApp({super.key});
  @override
  State<MouseApp> createState() => _S();
}

class _S extends State<MouseApp> {
  int skin = 0, mask = 0;
  bool connected = false, connecting = false, sound = true;
  double sens = 1.8, ax = 0, ay = 0, wacc = 0;
  Skin get k => skins[skin];
  bool gyroOn = false, gyroOk = true, held = false;
  double gsens = 1.0, gx = 0, gy = 0, gz = 9.8, _last = 0;
  final _sw = Stopwatch()..start();
  StreamSubscription? _sa, _sg;

  void _setGyro(bool on) {
    gyroOn = on;
    _sa?.cancel();
    _sg?.cancel();
    if (!on) return;
    void bad(Object _) {
      if (mounted) setState(() { gyroOk = false; gyroOn = false; });
    }
    _sa = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
        .listen((e) { gx = e.x; gy = e.y; gz = e.z; }, onError: bad);
    _sg = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_gyro, onError: bad);
  }

  void _gyro(GyroscopeEvent e) {
    final now = _sw.elapsedMicroseconds / 1e6;
    final dt = (now - _last).clamp(0.0, 0.05);
    _last = now;
    if (!held) return;
    final n = sqrt(gx * gx + gy * gy + gz * gz);
    if (n < 1) return;
    final yaw = (e.x * gx + e.y * gy + e.z * gz) / n; // aylanish: gorizont
    double dx = -yaw, dy = -e.x;                      // egilish: vertikal
    if (dx.abs() < .03) dx = 0;
    if (dy.abs() < .03) dy = 0;
    moveRaw(dx * dt * gsens * 700, dy * dt * gsens * 700);
  }

  @override
  void dispose() {
    _tm?.cancel();
    _sa?.cancel();
    _sg?.cancel();
    super.dispose();
  }
  final _pl = {for (final n in ['down.wav', 'up.wav', 'tick.wav']) n: AudioPlayer()};
  void play(String n) => _pl[n]!.play(AssetSource(n), volume: 1);

  @override
  void initState() {
    super.initState();
    _tm = Timer.periodic(const Duration(milliseconds: 16), (_) => _flush());
    for (final p in _pl.values) {
      p.setPlayerMode(PlayerMode.lowLatency);
    }
    ch.setMethodCallHandler((c) async {
      if (c.method == 'key') {
        final a = c.arguments as List;
        btn(a[0] as int, a[1] as bool);
      }
      if (c.method == 'state' && mounted) {
        final st = c.arguments as int;
        setState(() {
          connected = st == 2;
          connecting = st == 1;
        });
      }
    });
    _init();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      sound = p.getBool('sound') ?? true;
      skin = (p.getInt('skin') ?? 0).clamp(0, skins.length - 1);
      _setGyro(p.getBool('gyro') ?? false);
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('sound', sound);
    await p.setInt('skin', skin);
    await p.setBool('gyro', gyroOn);
  }

  Future<void> _init() async {
    await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.bluetoothAdvertise].request();
    await ch.invokeMethod('start');
  }

  void send(int dx, int dy, int w) => ch.invokeMethod('send', [mask, dx, dy, w]);

  // Harakat va g'ildirak yig'ilib, soniyasiga ~60 marta yuboriladi (Bluetooth to'lib qolmasligi uchun)
  int px = 0, py = 0, pw = 0;
  Timer? _tm;

  void _flush() {
    if (px == 0 && py == 0 && pw == 0) return;
    final x = px.clamp(-127, 127), y = py.clamp(-127, 127), w = pw.clamp(-127, 127);
    px -= x;
    py -= y;
    pw -= w;
    send(x, y, w);
  }

  void move(Offset d) => moveRaw(d.dx * sens, d.dy * sens);

  void moveRaw(double dx, double dy) {
    ax += dx;
    ay += dy;
    final x = ax.truncate(), y = ay.truncate();
    ax -= x;
    ay -= y;
    px = (px + x).clamp(-600, 600);
    py = (py + y).clamp(-600, 600);
  }

  void btn(int bit, bool down) {
    mask = down ? mask | bit : mask & ~bit;
    HapticFeedback.selectionClick();
    if (sound) play(down ? 'down.wav' : 'up.wav');
    send(0, 0, 0);
  }

  Future<void> tap() async {
    btn(1, true);
    await Future.delayed(const Duration(milliseconds: 40));
    btn(1, false);
  }

  void wheel(double dy) {
    wacc += dy;
    while (wacc.abs() >= 10) {
      final s = wacc > 0 ? -1 : 1;
      pw = (pw + s).clamp(-20, 20);
      wacc -= wacc > 0 ? 10 : -10;
      if (sound) play('tick.wav');
      HapticFeedback.selectionClick();
    }
  }

  Future<void> pick() async {
    final List l = await ch.invokeMethod('devices');
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: k.top,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("Kompyuterni tanlang (avval Bluetooth'da juftlang)", style: TextStyle(color: k.text)),
          ),
          for (final d in l)
            ListTile(
              leading: Icon(Icons.computer, color: k.accent),
              title: Text(d['name'], style: TextStyle(color: k.text)),
              onTap: () {
                Navigator.pop(context);
                ch.invokeMethod('connect', d['addr']).then((ok) {
                  if (ok != true && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ilova hali tayyor emas. Bluetooth'ni yoqib, qayta urining")));
                  }
                });
              },
            ),
          if (l.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text("Juftlangan qurilma yo'q", style: TextStyle(color: k.text))),
        ],
      ),
    );
  }

  Widget key(String t, int bit) => Expanded(
        flex: 5,
        child: Listener(
          onPointerDown: (_) => btn(bit, true),
          onPointerUp: (_) => btn(bit, false),
          onPointerCancel: (_) => btn(bit, false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            decoration: BoxDecoration(
              color: (mask & bit) != 0 ? k.accent.withOpacity(.35) : k.btn,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(bit == 1 ? 120 : 14),
                topRight: Radius.circular(bit == 2 ? 120 : 14),
                bottomLeft: const Radius.circular(14),
                bottomRight: const Radius.circular(14),
              ),
              border: Border.all(color: k.accent.withOpacity(.5)),
            ),
            alignment: Alignment.center,
            child: Text(t, style: TextStyle(color: k.text, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget wheelW() => Expanded(
        flex: 2,
        child: GestureDetector(
          onVerticalDragUpdate: (d) => wheel(d.delta.dy),
          onTap: () {
            btn(4, true);
            Future.delayed(const Duration(milliseconds: 40), () => btn(4, false));
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
            decoration: BoxDecoration(
              color: k.accent.withOpacity(.85),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [BoxShadow(color: k.accent.withOpacity(.4), blurRadius: 12)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (_) => Container(height: 3, width: 22, color: Colors.black26)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: k.bottom,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              Icon(Icons.circle, size: 12, color: connected ? Colors.greenAccent : (connecting ? Colors.amber : Colors.redAccent)),
              const SizedBox(width: 8),
              Expanded(child: Text(connected ? 'Ulangan' : (connecting ? 'Ulanmoqda' : 'Ulanmagan'), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: TextStyle(color: k.text, fontSize: 13))),
              for (int i = 0; i < skins.length; i++)
                GestureDetector(
                  onTap: () {
                    setState(() => skin = i);
                    _save();
                  },
                  child: Container(
                    width: 24, height: 24,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [skins[i].top, skins[i].accent]),
                      border: Border.all(color: i == skin ? k.text : Colors.transparent, width: 2),
                    ),
                  ),
                ),
              if (gyroOk)
                IconButton(
                  style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
tooltip: 'Giroskop',
                  icon: Icon(Icons.screen_rotation, color: gyroOn ? k.accent : k.text.withOpacity(.4)),
                  onPressed: () {
                    setState(() => _setGyro(!gyroOn));
                    _save();
                  },
                ),
              IconButton(style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
icon: Icon(sound ? Icons.volume_up : Icons.volume_off, color: k.accent),
                onPressed: () {
                  setState(() => sound = !sound);
                  _save();
                },
              ),
              IconButton(style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
tooltip: "Telefonni ko'rinadigan qilish",
                icon: Icon(Icons.visibility, color: k.accent),
                onPressed: () => ch.invokeMethod('discoverable'),
              ),
              IconButton(style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
icon: Icon(Icons.bluetooth, color: k.accent), onPressed: pick),
            ]),
          ),
          Row(children: [
            const SizedBox(width: 16),
            Icon(Icons.speed, size: 18, color: k.text),
            Expanded(child: Slider(value: sens, min: .6, max: 4, activeColor: k.accent, onChanged: (v) => setState(() => sens = v))),
          ]),
          if (gyroOn)
            Row(children: [
              const SizedBox(width: 16),
              Icon(Icons.screen_rotation, size: 18, color: k.text),
              Expanded(child: Slider(value: gsens, min: .3, max: 3, activeColor: k.accent, onChanged: (v) => setState(() => gsens = v))),
            ]),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [k.top, k.bottom]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(160), bottom: Radius.circular(70)),
                border: Border.all(color: k.accent.withOpacity(.4), width: 1.5),
              ),
              child: Column(children: [
                Expanded(flex: 4, child: Row(children: [key('CHAP', 1), wheelW(), key('O\'NG', 2)])),
                Expanded(
                  flex: 6,
                  child: GestureDetector(
                    onPanDown: (_) => held = true,
                    onPanEnd: (_) => held = false,
                    onPanCancel: () => held = false,
                    onPanUpdate: (d) => move(d.delta),
                    onTap: tap,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(14, 6, 14, 22),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(.12), borderRadius: BorderRadius.circular(40)),
                      alignment: Alignment.center,
                      child: Text('TOUCHPAD', style: TextStyle(color: k.text.withOpacity(.3), letterSpacing: 4)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
