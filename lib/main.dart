import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: initAndroid);

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'peugeot205_channel',
    'Peugeot 205',
    description: 'Notifications de test Peugeot 205',
    importance: Importance.max,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> showTestNotification(String body) async {
  const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'peugeot205_channel',
    'Peugeot 205',
    channelDescription: 'Notifications de test Peugeot 205',
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    1,
    'Test notification',
    body,
    details,
  );
}

Future<void> updateHomeScreenWidget(Map<String, dynamic> json) async {
  final sim = json['sim'] == true || json['sim'] == 'true';
  await HomeWidget.saveWidgetData<String>(
      'mode', sim ? 'SIMULATION' : 'REEL');
  await HomeWidget.saveWidgetData<String>(
      'water', '${json['water'] ?? '--'} °C');
  await HomeWidget.saveWidgetData<String>(
      'oil', '${json['oil'] ?? '--'} °C');
  await HomeWidget.saveWidgetData<String>(
      'press', '${json['press'] ?? '--'} bar');

  await HomeWidget.updateWidget(
    androidName: 'Peugeot205WidgetProvider',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Peugeot 205',
      theme: ThemeData.dark(useMaterial3: true),
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
  String status = 'Idle';
  Map<String, dynamic>? lastJson;

  Future<void> _scanAndConnect() async {
    setState(() => status = 'Scan...');
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await Future.delayed(const Duration(seconds: 5));
    FlutterBluePlus.stopScan();

    for (final r in FlutterBluePlus.lastScanResults) {
      if (r.device.name == 'Peugeot205-ESP32') {
        device = r.device;
        break;
      }
    }

    if (device == null) {
      setState(() => status = 'ESP32 introuvable');
      await showTestNotification('ESP32 introuvable');
      return;
    }

    setState(() => status = 'Connexion...');
    await device!.connect();
    setState(() => status = 'Connecté');
    await showTestNotification('Connecté au Peugeot205-ESP32');
  }

  Future<void> _readOnce() async {
    if (device == null) return;
    setState(() => status = 'Lecture...');

    final services = await device!.discoverServices();
    BluetoothCharacteristic? c;

    for (final s in services) {
      if (s.uuid.toString() ==
          '4fafc201-1fb5-459e-8fcc-c5c9c331914b') {
        for (final ch in s.characteristics) {
          if (ch.uuid.toString() ==
              'beb5483e-36e1-4688-b7f5-ea07361b26a8') {
            c = ch;
            break;
          }
        }
      }
    }

    if (c == null) {
      setState(() => status = 'Caractéristique introuvable');
      await showTestNotification('Caractéristique introuvable');
      return;
    }

    final bytes = await c.read();
    final str = utf8.decode(bytes);
    Map<String, dynamic> json;
    try {
      json = jsonDecode(str) as Map<String, dynamic>;
    } catch (_) {
      setState(() => status = 'JSON invalide');
      await showTestNotification('JSON invalide');
      return;
    }

    setState(() {
      lastJson = json;
      status = 'Lecture OK';
    });

    await updateHomeScreenWidget(json);

    final sim = json['sim'] == true || json['sim'] == 'true';
    await showTestNotification('Lecture OK · sim=${sim ? "ON" : "OFF"}');
  }

  Future<void> _testNotificationButton() async {
    await showTestNotification('Notif de test Peugeot 205');
  }

  @override
  Widget build(BuildContext context) {
    final simLabel = (lastJson?['sim'] == true ||
            lastJson?['sim'] == 'true')
        ? 'SIMULATION'
        : 'REEL';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peugeot 205 ESP32'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statut: $status'),
            const SizedBox(height: 12),
            Text('Mode: $simLabel'),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton(
                  onPressed: _scanAndConnect,
                  child: const Text('Scan / Connect'),
                ),
                ElevatedButton(
                  onPressed: _readOnce,
                  child: const Text('Lire une fois'),
                ),
                ElevatedButton(
                  onPressed: _testNotificationButton,
                  child: const Text('Test notification'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (lastJson != null)
              Text(
                'Dernier JSON:\n${jsonEncode(lastJson)}',
              ),
          ],
        ),
      ),
    );
  }
}
