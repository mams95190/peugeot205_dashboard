import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String bleDeviceName = 'Peugeot205-ESP32';
const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const String characteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

Future<void> initNotifications() async {
  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: initAndroid);

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'peugeot205_channel',
    'Peugeot 205',
    description: 'Notifications Peugeot 205',
    importance: Importance.max,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> showInfoNotification(String body) async {
  const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'peugeot205_channel',
    'Peugeot 205',
    channelDescription: 'Notifications Peugeot 205',
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    1,
    'Peugeot 205',
    body,
    details,
  );
}

Color tempColor(num value) {
  final t = value.toDouble();
  if (t < 70) return const Color(0xFF55BDE8);
  if (t < 95) return const Color(0xFFD7A33F);
  if (t < 105) return const Color(0xFFFF8A00);
  return const Color(0xFFE44A32);
}

Color pressureColor(num value) {
  final p = value.toDouble();
  if (p < 0.7) return const Color(0xFF55BDE8);
  if (p < 4.5) return const Color(0xFFD7A33F);
  return const Color(0xFFE44A32);
}

String colorToHex(Color c) =>
    '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

Future<void> updateHomeScreenWidget(Map<String, dynamic> json) async {
  final water = (json['water'] ?? '--').toString();
  final oil = (json['oil'] ?? '--').toString();
  final press = (json['press'] ?? '--').toString();
  final sim = json['sim'] == true || json['sim'] == 'true';

  final waterNum = num.tryParse(water) ?? 0;
  final oilNum = num.tryParse(oil) ?? 0;
  final pressNum = num.tryParse(press) ?? 0;

  await HomeWidget.saveWidgetData<String>(
      'mode', sim ? 'SIMULATION' : 'REEL');
  await HomeWidget.saveWidgetData<String>('water', '$water °C');
  await HomeWidget.saveWidgetData<String>('oil', '$oil °C');
  await HomeWidget.saveWidgetData<String>('press', '$press bar');
  await HomeWidget.saveWidgetData<String>(
      'waterColor', colorToHex(tempColor(waterNum)));
  await HomeWidget.saveWidgetData<String>(
      'oilColor', colorToHex(tempColor(oilNum)));
  await HomeWidget.saveWidgetData<String>(
      'pressColor', colorToHex(pressureColor(pressNum)));

  await HomeWidget.updateWidget(
    androidName: 'Peugeot205WidgetProvider',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  runApp(const MyApp());
}

class SensorData {
  final double water;
  final double oil;
  final double press;
  final String waterStatus;
  final String oilStatus;
  final String pressStatus;
  final bool sim;

  const SensorData({
    required this.water,
    required this.oil,
    required this.press,
    required this.waterStatus,
    required this.oilStatus,
    required this.pressStatus,
    required this.sim,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    bool sim = json['sim'] == true || json['sim'] == 'true';
    return SensorData(
      water: (json['water'] as num?)?.toDouble() ?? 0,
      oil: (json['oil'] as num?)?.toDouble() ?? 0,
      press: (json['press'] as num?)?.toDouble() ?? 0,
      waterStatus: (json['waterStatus'] ?? '').toString(),
      oilStatus: (json['oilStatus'] ?? '').toString(),
      pressStatus: (json['pressStatus'] ?? '').toString(),
      sim: sim,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peugeot 205',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF060708),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD7A33F),
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? targetCharacteristic;
  String status = 'Prêt';
  SensorData? data;
  String rawJson = '';
  Timer? pollTimer;
  bool isConnecting = false;

  @override
  void dispose() {
    pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _scanAndConnect() async {
    if (isConnecting) return;
    setState(() {
      isConnecting = true;
      status = 'Scan BLE...';
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      await Future.delayed(const Duration(seconds: 5));
      await FlutterBluePlus.stopScan();

      BluetoothDevice? found;
      for (final r in FlutterBluePlus.lastScanResults) {
        if (r.device.name == bleDeviceName) {
          found = r.device;
          break;
        }
      }

      if (found == null) {
        setState(() => status = 'ESP32 introuvable');
        await showInfoNotification('ESP32 introuvable');
        return;
      }

      device = found;
      setState(() => status = 'Connexion...');
      await device!.connect(timeout: const Duration(seconds: 10));

      final services = await device!.discoverServices();
      for (final s in services) {
        if (s.uuid.toString() == serviceUuid) {
          for (final ch in s.characteristics) {
            if (ch.uuid.toString() == characteristicUuid) {
              targetCharacteristic = ch;
              break;
            }
          }
        }
      }

      if (targetCharacteristic == null) {
        setState(() => status = 'Caractéristique introuvable');
        await showInfoNotification('Caractéristique BLE introuvable');
        return;
      }

      setState(() => status = 'Connecté');
      await _readOnce();
      _startPolling();
      await showInfoNotification('Connecté au Peugeot205-ESP32');
    } catch (e) {
      setState(() => status = 'Erreur connexion');
    } finally {
      setState(() => isConnecting = false);
    }
  }

  void _startPolling() {
    pollTimer?.cancel();
    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _readOnce(silent: true);
    });
  }

  Future<void> _readOnce({bool silent = false}) async {
    if (targetCharacteristic == null) return;

    try {
      if (!silent) {
        setState(() => status = 'Lecture...');
      }

      final bytes = await targetCharacteristic!.read();
      final str = utf8.decode(bytes);
      final json = jsonDecode(str) as Map<String, dynamic>;
      final parsed = SensorData.fromJson(json);

      await updateHomeScreenWidget(json);

      if (!mounted) return;
      setState(() {
        data = parsed;
        rawJson = const JsonEncoder.withIndent('  ').convert(json);
        status = 'Lecture OK';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'Erreur lecture');
    }
  }

  Widget _hero() {
    final mode = data?.sim == true ? 'SIMULATION' : 'REEL';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(.08)),
        gradient: const LinearGradient(
          colors: [Color(0xFF13181E), Color(0xFF0A0D10)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFF1B2128),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.speed, color: Color(0xFFD7A33F), size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Peugeot 205',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Color(0xFFF7F0E3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ESP32 · BLE · Widget Android',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.62),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF181D23),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(.06)),
            ),
            child: Text(
              mode,
              style: const TextStyle(
                color: Color(0xFFD7A33F),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gaugeCard({
    required String title,
    required double value,
    required String unit,
    required double min,
    required double max,
    required Color color,
    required String statusText,
  }) {
    final pct = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final angle = -math.pi * 0.75 + (math.pi * 1.5 * pct);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(.08)),
        gradient: const LinearGradient(
          colors: [Color(0xFF11161C), Color(0xFF090C10)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 24,
            offset: Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFF2E4CF),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: .6,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.05),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 250,
            height: 250,
            child: CustomPaint(
              painter: GaugePainter(
                value: value,
                min: min,
                max: max,
                color: color,
                angle: angle,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value.toStringAsFixed(unit == 'bar' ? 2 : 1),
                      style: const TextStyle(
                        color: Color(0xFFFFF7EC),
                        fontWeight: FontWeight.w900,
                        fontSize: 46,
                      ),
                    ),
                    Text(
                      unit,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.58),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final water = data?.water ?? 0;
    final oil = data?.oil ?? 0;
    final press = data?.press ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peugeot 205'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hero(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _scanAndConnect,
                  child: const Text('Scan / Connect'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _readOnce(),
                  child: const Text('Lire'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _gaugeCard(
            title: 'Température eau',
            value: water,
            unit: '°C',
            min: 20,
            max: 170,
            color: tempColor(water),
            statusText: data?.waterStatus ?? '--',
          ),
          const SizedBox(height: 16),
          _gaugeCard(
            title: 'Température huile',
            value: oil,
            unit: '°C',
            min: 20,
            max: 170,
            color: tempColor(oil),
            statusText: data?.oilStatus ?? '--',
          ),
          const SizedBox(height: 16),
          _gaugeCard(
            title: 'Pression huile',
            value: press,
            unit: 'bar',
            min: 0,
            max: 6.9,
            color: pressureColor(press),
            statusText: data?.pressStatus ?? '--',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFF11161C),
              border: Border.all(color: Colors.white.withOpacity(.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Statut: $status',
                    style: const TextStyle(color: Color(0xFFF2E4CF))),
                const SizedBox(height: 12),
                Text(
                  rawJson.isEmpty ? 'Aucune donnée JSON' : rawJson,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.75),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final Color color;
  final double angle;

  GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;

    final base = Paint()
      ..color = const Color(0xFF252C38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final tick = Paint()
      ..color = const Color(0xCCFFF7EC)
      ..strokeWidth = 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      base,
    );

    final pct = ((value - min) / (max - min)).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5 * pct,
      false,
      progress,
    );

    for (int i = 0; i <= 10; i++) {
      final a = math.pi * 0.75 + (math.pi * 1.5 / 10) * i;
      final p1 = Offset(
        center.dx + math.cos(a) * (radius - 18),
        center.dy + math.sin(a) * (radius - 18),
      );
      final p2 = Offset(
        center.dx + math.cos(a) * (radius + 2),
        center.dy + math.sin(a) * (radius + 2),
      );
      canvas.drawLine(p1, p2, tick);
    }

    final needleStart = center;
    final needleEnd = Offset(
      center.dx + math.cos(angle) * (radius - 28),
      center.dy + math.sin(angle) * (radius - 28),
    );

    final needle = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF4D8), Color(0xFFC43B25)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(needleStart, needleEnd, needle);
    canvas.drawCircle(center, 11, Paint()..color = const Color(0xFFBB7B3C));
    canvas.drawCircle(center, 5, Paint()..color = const Color(0xFFF6E7CD));
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.angle != angle;
  }
}
