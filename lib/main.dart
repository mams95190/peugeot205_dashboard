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
      scaffoldBackgroundColor: const Color(0xFF040506),
      cardColor: const Color(0xFF11151A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1014),
        elevation: 0,
      ),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFD7A33F),
        secondary: Color(0xFFE7C27A),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF020304), Color(0xFF090C10)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Text(
            'Bluetooth: ${state.name}',
            style: const TextStyle(fontSize: 22),
          ),
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

  String _globalState() {
    final w = (liveJson?['water'] ?? 0) as num;
    final o = (liveJson?['oil'] ?? 0) as num;
    final p = (liveJson?['press'] ?? 0) as num;

    if (w >= 112 || o >= 120 || p < 0.5) return 'CRITIQUE';
    if (w >= 105 || o >= 110 || p < 0.7) return 'ALERTE';
    return 'NORMAL';
  }

  Color _globalStateColor(String state) {
    switch (state) {
      case 'CRITIQUE':
        return const Color(0xFFE44A32);
      case 'ALERTE':
        return const Color(0xFFFF8A00);
      default:
        return const Color(0xFFD7A33F);
    }
  }

  String _globalMessage() {
    final w = (liveJson?['water'] ?? 0) as num;
    final o = (liveJson?['oil'] ?? 0) as num;
    final p = (liveJson?['press'] ?? 0) as num;

    if (p < 0.5) return 'Pression huile très basse';
    if (w >= 112) return 'Température eau critique';
    if (o >= 120) return 'Température huile critique';
    if (p < 0.7) return 'Pression huile basse';
    if (w >= 105) return 'Température eau élevée';
    if (o >= 110) return 'Température huile élevée';
    return 'Tous les paramètres sont stables';
  }

  Widget _statusBanner() {
    final state = _globalState();
    final color = _globalStateColor(state);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.28),
            color.withOpacity(0.14),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.65)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            state == 'CRITIQUE'
                ? Icons.warning_amber_rounded
                : state == 'ALERTE'
                    ? Icons.priority_high_rounded
                    : Icons.check_circle_outline_rounded,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _globalMessage(),
                  style: const TextStyle(
                    color: Color(0xFFEFE7D7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFE7C27A)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFFF7E7D0)),
          ),
        ],
      ),
    );
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

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF030405), Color(0xFF090C10)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD7A33F).withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            top: 180,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE44A32).withOpacity(0.04),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _statusBanner(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Peugeot 205',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                              color: Color(0xFFFFF7EC),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Combiné auxiliaire · BLE + Wi‑Fi local',
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
                        _infoChip(Icons.wifi_tethering_rounded, 'peugeot 205'),
                        const SizedBox(height: 6),
                        _infoChip(Icons.bluetooth_rounded, 'Peugeot205-ESP32'),
                        const SizedBox(height: 6),
                        _infoChip(
                          sim == 'true'
                              ? Icons.science_outlined
                              : Icons.sensors_outlined,
                          sim == 'true' ? 'Simulation' : 'Capteurs live',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
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
                          mode: GaugeMode.temperature,
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
                          mode: GaugeMode.temperature,
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
                          mode: GaugeMode.pressure,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _bottomInfoCards(),
                const SizedBox(height: 14),
                if (lastRawValue.isNotEmpty)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Color(0x22FFFFFF)),
                    ),
                    color: const Color(0xFF101419),
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
        ],
      ),
    );
  }

  Widget _bottomInfoCards() {
    final water = (liveJson?['water'] ?? 0).toString();
    final oil = (liveJson?['oil'] ?? 0).toString();
    final press = (liveJson?['press'] ?? 0).toString();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _miniInfoCard('Eau', water, const Color(0xFF55BDE8)),
        _miniInfoCard('Huile', oil, const Color(0xFFD7A33F)),
        _miniInfoCard('Pression', press, const Color(0xFFE44A32)),
      ],
    );
  }

  Widget _miniInfoCard(String label, String value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101419),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 16,
            spreadRadius: 1,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                color: Color(0xFFA79E91),
                fontSize: 12,
              )),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
    required GaugeMode mode,
  }) {
    final angle = (-150.0 + pct * 300.0) * (pi / 180.0);

    return Container(
      width: size + 32,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x22FFFFFF)),
        gradient: const LinearGradient(
          colors: [Color(0xFF12171D), Color(0xFF0B0E12)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.10),
            blurRadius: 24,
            spreadRadius: 1,
          ),
          const BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: color.withOpacity(0.18),
                  border: Border.all(color: color.withOpacity(0.40)),
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
                mode: mode,
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0B0E12),
              border: Border(
                bottom: BorderSide(color: Color(0x22FFFFFF)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permissions: $permissionDebug',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFA79E91)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Scan: $scanDebug',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFA79E91)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Connecté: $connectedName · ${connectionState.name}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFD8D0C2)),
                ),
              ],
            ),
          ),
          Expanded(
            child: hasData
                ? _dashboard()
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF030405), Color(0xFF090C10)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: ListView(
                      children: [
                        const SizedBox(height: 8),
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
          ),
        ],
      ),
    );
  }
}

enum GaugeMode { temperature, pressure }

class _GaugePainter extends CustomPainter {
  final Color color;
  final String value;
  final String unit;
  final String lowLabel;
  final String midLabel;
  final String highLabel;
  final double angle;
  final GaugeMode mode;

  _GaugePainter({
    required this.color,
    required this.value,
    required this.unit,
    required this.lowLabel,
    required this.midLabel,
    required this.highLabel,
    required this.angle,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;

    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF171D25), Color(0xFF080B0F)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, bgPaint);

    final ringGlow = Paint()
      ..color = color.withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, radius - 4, ringGlow);

    final startAngle = -5 * pi / 6;
    final sweepAngleFull = 5 * pi / 3;
    final arcRect = Rect.fromCircle(center: center, radius: radius - 6);

    final zonePaintBlue = Paint()
      ..color = const Color(0xFF55BDE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final zonePaintGold = Paint()
      ..color = const Color(0xFFD7A33F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final zonePaintOrange = Paint()
      ..color = const Color(0xFFFF8A00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final zonePaintRed = Paint()
      ..color = const Color(0xFFE44A32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    if (mode == GaugeMode.temperature) {
      canvas.drawArc(arcRect, startAngle, sweepAngleFull * 0.37, false, zonePaintBlue);
      canvas.drawArc(arcRect, startAngle + sweepAngleFull * 0.37, sweepAngleFull * 0.35, false, zonePaintGold);
      canvas.drawArc(arcRect, startAngle + sweepAngleFull * 0.72, sweepAngleFull * 0.12, false, zonePaintOrange);
      canvas.drawArc(arcRect, startAngle + sweepAngleFull * 0.84, sweepAngleFull * 0.16, false, zonePaintRed);
    } else {
      canvas.drawArc(arcRect, startAngle, sweepAngleFull * 0.12, false, zonePaintBlue);
      canvas.drawArc(arcRect, startAngle + sweepAngleFull * 0.12, sweepAngleFull * 0.55, false, zonePaintGold);
      canvas.drawArc(arcRect, startAngle + sweepAngleFull * 0.67, sweepAngleFull * 0.33, false, zonePaintRed);
    }

    final progressPaint = Paint()
      ..color = const Color(0xFFF8F1E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 16),
      startAngle,
      angle - startAngle,
      false,
      progressPaint,
    );

    final ticksPaintMajor = Paint()
      ..color = const Color(0xE6FFF7EC)
      ..strokeWidth = 2;

    final ticksPaintMinor = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1;

    for (int i = 0; i <= 12; i++) {
      final a = startAngle + sweepAngleFull * (i / 12.0);
      final inner = Offset(
        center.dx + (radius - 18) * cos(a),
        center.dy + (radius - 18) * sin(a),
      );
      final outer = Offset(
        center.dx + (radius - 2) * cos(a),
        center.dy + (radius - 2) * sin(a),
      );
      canvas.drawLine(inner, outer, ticksPaintMajor);
    }

    for (int i = 0; i <= 24; i++) {
      final a = startAngle + sweepAngleFull * (i / 24.0);
      final inner = Offset(
        center.dx + (radius - 12) * cos(a),
        center.dy + (radius - 12) * sin(a),
      );
      final outer = Offset(
        center.dx + (radius - 2) * cos(a),
        center.dy + (radius - 2) * sin(a),
      );
      canvas.drawLine(inner, outer, ticksPaintMinor);
    }

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: value,
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
          color: Color(0xFFFFF7EC),
        ),
      ),
    )..layout();

    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - 26),
    );

    final unitPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: unit.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.8,
          color: Color(0xFFA79E91),
          fontWeight: FontWeight.w800,
        ),
      ),
    )..layout();

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
      Offset(center.dx - radius + 18, center.dy + radius - 42),
    );
    midPainter.paint(
      canvas,
      Offset(center.dx - midPainter.width / 2, center.dy + radius - 42),
    );
    highPainter.paint(
      canvas,
      Offset(center.dx + radius - 18 - highPainter.width, center.dy + radius - 42),
    );

    final centerGlow = Paint()
      ..color = color.withOpacity(0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, 16, centerGlow);

    final hubPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFFF6E7CD),
          Color(0xFFE0B97B),
          Color(0xFF6A3F1D),
          Color(0xFF120B07),
        ],
        stops: [0.0, 0.35, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 14));

    final needlePaint = Paint()
      ..shader = LinearGradient(
        colors: const [
          Color(0xFFFFF4D8),
          Color(0xFFFFA24E),
          Color(0xFFC43B25),
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final needleLen = radius - 28;
    final tip = Offset(
      center.dx + needleLen * cos(angle),
      center.dy + needleLen * sin(angle),
    );
    final baseLeft = Offset(
      center.dx + 11 * cos(angle + pi / 2),
      center.dy + 11 * sin(angle + pi / 2),
    );
    final baseRight = Offset(
      center.dx + 11 * cos(angle - pi / 2),
      center.dy + 11 * sin(angle - pi / 2),
    );

    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseLeft.dx, baseLeft.dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(baseRight.dx, baseRight.dy)
      ..close();

    canvas.drawPath(needlePath, needlePaint);
    canvas.drawCircle(center, 12, hubPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.unit != unit ||
        oldDelegate.color != color ||
        oldDelegate.angle != angle ||
        oldDelegate.mode != mode;
  }
}
