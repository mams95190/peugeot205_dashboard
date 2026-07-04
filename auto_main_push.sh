#!/usr/bin/env bash
set -e

cd "$(git rev-parse --show-toplevel)"
mkdir -p lib

cat > lib/main.dart <<'DART'
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
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
      appBar: AppBar(title: const Text('ESP32 BLE Dashboard')),
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
  final List<BluetoothService> services = [];

  bool scanning = false;
  bool discovering = false;

  String permissionDebug = '';
  String scanDebug = '';
  String serviceDebug = '';
  String lastRawValue = '';

  BluetoothDevice? connectedDevice;
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;

  BluetoothCharacteristic? jsonChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  Map<String, dynamic>? liveJson;

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
      services.clear();
      scanDebug = '';
      serviceDebug = '';
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

      final uuids = found.map((s) => s.uuid.toString()).join('\n');

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
        services
          ..clear()
          ..addAll(found);
        jsonChar = target;
        serviceDebug = uuids.isEmpty ? 'Aucun service' : uuids;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        serviceDebug = 'Erreur connexion/services: $e';
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
        discovering = false;
        services.clear();
        jsonChar = null;
        liveJson = null;
        lastRawValue = '';
        serviceDebug = '';
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

  Widget _jsonCard() {
    if (liveJson == null && lastRawValue.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BLE JSON', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (liveJson != null) ...[
              Text('Water: ${liveJson!["water"] ?? "-"}'),
              Text('Oil: ${liveJson!["oil"] ?? "-"}'),
              Text('Press: ${liveJson!["press"] ?? "-"}'),
              Text('Water status: ${liveJson!["waterStatus"] ?? "-"}'),
              Text('Oil status: ${liveJson!["oilStatus"] ?? "-"}'),
              Text('Press status: ${liveJson!["pressStatus"] ?? "-"}'),
              Text('Sim: ${liveJson!["sim"] ?? "-"}'),
            ],
            if (lastRawValue.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(lastRawValue),
            ]
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 BLE Dashboard'),
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
            child: Text('Permissions: $permissionDebug'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Scan: $scanDebug'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Connecté: $connectedName | ${connectionState.name}'),
          ),
          const SizedBox(height: 8),
          _jsonCard(),
          if (serviceDebug.isNotEmpty)
            Expanded(
              child: Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      'Services découverts:\n$serviceDebug',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  for (final r in devices)
                    ListTile(
                      title: Text(_displayName(r)),
                      subtitle: Text(_subtitle(r)),
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
DART

git add lib/main.dart

if git diff --cached --quiet; then
  echo "Aucun changement à commit"
else
  git commit -m "debug BLE scan and service discovery"
  git push origin main
fi

if command -v gh >/dev/null 2>&1; then
  gh workflow run apk.yml || true
fi
