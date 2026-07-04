#!/usr/bin/env bash
set -e

cd "$(git rev-parse --show-toplevel)"

mkdir -p lib

cat > lib/main.dart <<'DART'
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

final Guid kServiceUuid = Guid("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
final Guid kCharUuid = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  @override
  void initState() {
    super.initState();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      if (!mounted) return;
      setState(() => _adapterState = s);
    });
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF050607),
      cardColor: const Color(0xFF11151A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF11161C),
        elevation: 8,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: baseTheme,
      home: _adapterState == BluetoothAdapterState.on
          ? const HomePage()
          : BluetoothOffPage(state: _adapterState),
    );
  }
}

class BluetoothOffPage extends StatelessWidget {
  final BluetoothAdapterState state;
  const BluetoothOffPage({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Peugeot 205 · BLE')),
      body: Center(
        child: Text(
          'Bluetooth: ${state.name}',
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<ScanResult> devices = [];
  bool scanning = false;

  String permissionDebug = '';
  String scanDebug = '';

  BluetoothDevice? connectedDevice;
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;

  BluetoothCharacteristic? jsonChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  Map<String, dynamic>? liveJson;
  String lastRawValue = '';

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;

    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();

    PermissionStatus locationStatus = PermissionStatus.granted;
    try {
      locationStatus = await Permission.locationWhenInUse.request();
    } catch (_) {}

    permissionDebug =
        'scan=$scanStatus | connect=$connectStatus | location=$locationStatus';

    if (mounted) setState(() {});
    return scanStatus.isGranted && connectStatus.isGranted;
  }

  Future<void> startScan() async {
    final ok = await _requestPermissions();
    if (!ok) return;

    setState(() {
      devices.clear();
      scanDebug = '';
      scanning = true;
      connectedDevice = null;
      connectionState = BluetoothConnectionState.disconnected;
      jsonChar = null;
      liveJson = null;
      lastRawValue = '';
    });

    await _scanSub?.cancel();

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (!mounted) return;

      final unique = <String, ScanResult>{};
      for (final r in results) {
        unique[r.device.remoteId.toString()] = r;
      }

      final sorted = unique.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));

      setState(() {
        devices
          ..clear()
          ..addAll(sorted);
        scanDebug = 'BLE trouvés: ${sorted.length}';
      });
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidScanMode: AndroidScanMode.lowLatency,
      );
      await FlutterBluePlus.isScanning.where((v) => v == false).first;
    } catch (e) {
      scanDebug = 'Erreur scan: $e';
    }

    if (!mounted) return;
    setState(() => scanning = false);
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      await _notifySub?.cancel();
      await _connSub?.cancel();

      _connSub = device.connectionState.listen((state) {
        if (!mounted) return;
        setState(() => connectionState = state);
      });

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      final found = await device.discoverServices();

      BluetoothCharacteristic? target;
      for (final s in found) {
        if (s.uuid == kServiceUuid) {
          for (final c in s.characteristics) {
            if (c.uuid == kCharUuid) {
              target = c;
              break;
            }
          }
        }
      }

      if (target != null) {
        _notifySub = target.onValueReceived.listen((value) {
          final txt = _bytesToText(value);
          if (!mounted) return;

          setState(() {
            lastRawValue = txt;
          });

          try {
            final decoded = jsonDecode(txt);
            if (decoded is Map<String, dynamic>) {
              setState(() {
                liveJson = decoded;
              });
            }
          } catch (_) {}
        });

        await target.setNotifyValue(true);

        try {
          final first = await target.read();
          final txt = _bytesToText(first);
          lastRawValue = txt;
          final decoded = jsonDecode(txt);
          if (decoded is Map<String, dynamic>) {
            liveJson = decoded;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        connectedDevice = device;
        jsonChar = target;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        liveJson = null;
        lastRawValue = '';
        scanDebug = 'Erreur connexion/services: $e';
      });
    }
  }

  Future<void> disconnectDevice() async {
    try {
      await _notifySub?.cancel();
      _notifySub = null;

      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
      }

      if (!mounted) return;
      setState(() {
        connectedDevice = null;
        connectionState = BluetoothConnectionState.disconnected;
        jsonChar = null;
        liveJson = null;
        lastRawValue = '';
      });
    } catch (_) {}
  }

  String _bytesToText(List<int> bytes) {
    if (bytes.isEmpty) return '(vide)';
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  String _displayName(ScanResult r) {
    final adv = r.advertisementData.advName.trim();
    final plat = r.device.platformName.trim();
    if (adv.isNotEmpty) return adv;
    if (plat.isNotEmpty) return plat;
    return 'Device inconnu';
  }

  String _subtitle(ScanResult r) {
    return 'id=${r.device.remoteId} | rssi=${r.rssi} | adv="${r.advertisementData.advName}" | name="${r.device.platformName}"';
  }

  Color _tempColor(num? t) {
    final v = (t ?? 0).toDouble();
    if (v < 70) return const Color(0xFF55BDE8);
    if (v < 95) return const Color(0xFFD7A33F);
    if (v < 105) return const Color(0xFFFF8A00);
    return const Color(0xFFE44A32);
  }

  Color _pressureColor(num? p) {
    final v = (p ?? 0).toDouble();
    if (v < 0.7) return const Color(0xFF55BDE8);
    if (v < 4.5) return const Color(0xFFD7A33F);
    return const Color(0xFFE44A32);
  }

  double _tempPct(num? t) {
    final v = (t ?? 20).toDouble().clamp(20.0, 170.0);
    return ((v - 20.0) / 150.0).clamp(0.0, 1.0);
  }

  double _pressPct(num? p) {
    final v = (p ?? 0).toDouble().clamp(0.0, 6.9);
    return (v / 6.9).clamp(0.0, 1.0);
  }

  Widget _dashboard() {
    final data = liveJson ?? {};
    final water = data['water'] as num?;
    final oil = data['oil'] as num?;
    final press = data['press'] as num?;
    final waterStatus = (data['waterStatus'] ?? '-') as String;
    final oilStatus = (data['oilStatus'] ?? '-') as String;
    final pressStatus = (data['pressStatus'] ?? '-') as String;
    final sim = data['sim']?.toString() ?? 'false';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Peugeot 205',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Interface d\'origine · BLE + Wi‑Fi',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFA79E91),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _badge('Wi‑Fi : peugeot 205'),
                    const SizedBox(height: 6),
                    _badge('BLE : Peugeot205-ESP32'),
                    const SizedBox(height: 6),
                    _badge(sim == 'true' ? 'Simulation' : 'Capteurs live'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _gaugeCard(
                      title: 'Température eau',
                      value: water?.toStringAsFixed(1) ?? '--',
                      unit: '°C',
                      status: waterStatus,
                      pct: _tempPct(water),
                      color: _tempColor(water),
                      lowLabel: '20',
                      midLabel: '90',
                      highLabel: '170',
                      detail: 'Circuit eau',
                      size: isWide ? 260 : 230,
                    ),
                    _gaugeCard(
                      title: 'Température huile',
                      value: oil?.toStringAsFixed(1) ?? '--',
                      unit: '°C',
                      status: oilStatus,
                      pct: _tempPct(oil),
                      color: _tempColor(oil),
                      lowLabel: '20',
                      midLabel: '90',
                      highLabel: '170',
                      detail: 'Circuit huile',
                      size: isWide ? 260 : 230,
                    ),
                    _gaugeCard(
                      title: 'Pression huile',
                      value: press?.toStringAsFixed(2) ?? '--',
                      unit: 'bar',
                      status: pressStatus,
                      pct: _pressPct(press),
                      color: _pressureColor(press),
                      lowLabel: '0',
                      midLabel: '3.5',
                      highLabel: '6.9',
                      detail: 'VDO 0‑100 psi converti en bar',
                      size: isWide ? 260 : 230,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            if (lastRawValue.isNotEmpty)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    lastRawValue,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFA79E91),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFFF7E7D0),
        ),
      ),
    );
  }

  Widget _gaugeCard({
    required String title,
    required String value,
    required String unit,
    required String status,
    required double pct,
    required Color color,
    required String lowLabel,
    required String midLabel,
    required String highLabel,
    required String detail,
    required double size,
  }) {
    final angle = (-150.0 + pct * 300.0) * (pi / 180.0);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: Color(0x33FFFFFF)),
      ),
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFFF2E4CF),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: const Color(0x33FFFFFF),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _GaugePainter(
                  color: color,
                  value: value,
                  unit: unit,
                  lowLabel: lowLabel,
                  midLabel: midLabel,
                  highLabel: highLabel,
                  angle: angle,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFA79E91),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectedName = connectedDevice == null
        ? 'Aucune'
        : (connectedDevice!.platformName.isEmpty
            ? connectedDevice!.remoteId.toString()
            : connectedDevice!.platformName);

    final hasData = liveJson != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peugeot 205 · ESP32 BLE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: scanning ? null : startScan,
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            onPressed: connectedDevice == null ? null : disconnectDevice,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Permissions: $permissionDebug',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA79E91)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Scan: $scanDebug',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA79E91)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Connecté: $connectedName · ${connectionState.name}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFA79E91)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: hasData
                ? _dashboard()
                : ListView(
                    children: [
                      for (final r in devices)
                        ListTile(
                          title: Text(_displayName(r)),
                          subtitle: Text(
                            _subtitle(r),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => connectToDevice(r.device),
                            child: const Text('Connect'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final Color color;
  final String value;
  final String unit;
  final String lowLabel;
  final String midLabel;
  final String highLabel;
  final double angle;

  _GaugePainter({
    required this.color,
    required this.value,
    required this.unit,
    required this.lowLabel,
    required this.midLabel,
    required this.highLabel,
    required this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;

    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF141A21), Color(0xFF080B0F)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, bgPaint);

    final baseArcPaint = Paint()
      ..color = const Color(0xFF212937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final startAngle = -5 * pi / 6;
    final sweepAngleFull = 5 * pi / 3;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      startAngle,
      sweepAngleFull,
      false,
      baseArcPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      startAngle,
      angle - startAngle,
      false,
      progressPaint,
    );

    final ticksPaintMajor = Paint()
      ..color = const Color(0xFFFFF7EC)
      ..strokeWidth = 2;

    final ticksPaintMinor = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;

    for (int i = 0; i <= 12; i++) {
      final a = startAngle + sweepAngleFull * (i / 12.0);
      final inner = Offset(
        center.dx + (radius - 16) * cos(a),
        center.dy + (radius - 16) * sin(a),
      );
      final outer = Offset(
        center.dx + radius * cos(a),
        center.dy + radius * sin(a),
      );
      canvas.drawLine(inner, outer, ticksPaintMajor);
    }

    for (int i = 0; i <= 24; i++) {
      final a = startAngle + sweepAngleFull * (i / 24.0);
      final inner = Offset(
        center.dx + (radius - 10) * cos(a),
        center.dy + (radius - 10) * sin(a),
      );
      final outer = Offset(
        center.dx + radius * cos(a),
        center.dy + radius * sin(a),
      );
      canvas.drawLine(inner, outer, ticksPaintMinor);
    }

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.text = TextSpan(
      text: value,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: Color(0xFFFFF7EC),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - 22),
    );

    final unitPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: unit.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.5,
          color: Color(0xFFA79E91),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    unitPainter.layout();
    unitPainter.paint(
      canvas,
      Offset(center.dx - unitPainter.width / 2, center.dy + 8),
    );

    final labelStyle = const TextStyle(
      fontSize: 11,
      color: Color(0xFF7F8792),
      fontWeight: FontWeight.w800,
    );

    final lowPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      text: TextSpan(text: lowLabel, style: labelStyle),
    )..layout();
    final midPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      text: TextSpan(text: midLabel, style: labelStyle),
    )..layout();
    final highPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
      text: TextSpan(text: highLabel, style: labelStyle),
    )..layout();

    lowPainter.paint(
      canvas,
      Offset(center.dx - radius + 20, center.dy + radius - 40),
    );
    midPainter.paint(
      canvas,
      Offset(center.dx - midPainter.width / 2, center.dy + radius - 40),
    );
    highPainter.paint(
      canvas,
      Offset(center.dx + radius - 20 - highPainter.width,
          center.dy + radius - 40),
    );

    final hubPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFF6E7CD),
          Color(0xFFBB7B3C),
          Color(0xFF4A2B12),
          Color(0xFF120B07),
        ],
        stops: [0.0, 0.4, 0.8, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 12));

    canvas.drawCircle(center, 12, hubPaint);

    final needlePaint = Paint()
      ..shader = LinearGradient(
        colors: const [
          Color(0xFFFFF4D8),
          Color(0xFFFF9541),
          Color(0xFFC43B25),
        ],
        stops: const [0.0, 0.3, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final needleLen = radius - 26;
    final tip = Offset(
      center.dx + needleLen * cos(angle),
      center.dy + needleLen * sin(angle),
    );
    final baseLeft = Offset(
      center.dx + 12 * cos(angle + pi / 2),
      center.dy + 12 * sin(angle + pi / 2),
    );
    final baseRight = Offset(
      center.dx + 12 * cos(angle - pi / 2),
      center.dy + 12 * sin(angle - pi / 2),
    );

    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseLeft.dx, baseLeft.dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(baseRight.dx, baseRight.dy)
      ..close();

    canvas.drawPath(needlePath, needlePaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.unit != unit ||
        oldDelegate.color != color ||
        oldDelegate.angle != angle;
  }
}
DART

git add lib/main.dart
git commit -m "fix dashboard gauges import math"
git push origin main

flutter clean
flutter pub get
flutter run
