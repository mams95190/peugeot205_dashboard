import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

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
      title: 'ESP32 Dashboard',
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

  String get message {
    switch (state) {
      case BluetoothAdapterState.off:
        return 'Bluetooth désactivé';
      case BluetoothAdapterState.unavailable:
        return 'Bluetooth indisponible';
      case BluetoothAdapterState.unauthorized:
        return 'Bluetooth non autorisé';
      case BluetoothAdapterState.turningOn:
        return 'Activation du Bluetooth...';
      case BluetoothAdapterState.turningOff:
        return 'Désactivation du Bluetooth...';
      default:
        return 'Vérification du Bluetooth...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 BLE Dashboard')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
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
  final List<BluetoothService> services = [];

  bool scanning = false;
  bool discovering = false;
  String permissionDebug = 'Pas encore testé';

  BluetoothDevice? connectedDevice;
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();

    PermissionStatus locationStatus = PermissionStatus.granted;
    try {
      locationStatus = await Permission.locationWhenInUse.request();
    } catch (_) {}

    final ok = scanStatus.isGranted && connectStatus.isGranted;

    permissionDebug =
        'scan=$scanStatus | connect=$connectStatus | location=$locationStatus';

    if (mounted) {
      setState(() {});
    }

    return ok;
  }

  Future<void> startScan() async {
    final ok = await _requestPermissions();

    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permissions Bluetooth refusées: $permissionDebug')),
      );
      return;
    }

    setState(() {
      devices.clear();
      services.clear();
      connectedDevice = null;
      connectionState = BluetoothConnectionState.disconnected;
      scanning = true;
      discovering = false;
    });

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        devices
          ..clear()
          ..addAll(results);
      });
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await Future.delayed(const Duration(seconds: 8));
      await FlutterBluePlus.stopScan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur scan: $e')),
      );
    }

    if (!mounted) return;
    setState(() => scanning = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${devices.length} périphérique(s) trouvé(s)')),
    );
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();

      await _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (!mounted) return;
        setState(() => connectionState = state);
      });

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      if (!mounted) return;
      setState(() {
        connectedDevice = device;
        services.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connecté à ${device.platformName.isEmpty ? "Device inconnu" : device.platformName}',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur connexion: $e')),
      );
    }
  }

  Future<void> disconnectDevice() async {
    try {
      if (connectedDevice == null) return;

      await connectedDevice!.disconnect();

      if (!mounted) return;
      setState(() {
        connectedDevice = null;
        connectionState = BluetoothConnectionState.disconnected;
        discovering = false;
        services.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Déconnecté')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur déconnexion: $e')),
      );
    }
  }

  Future<void> discoverDeviceServices() async {
    final device = connectedDevice;
    if (device == null) return;

    try {
      setState(() {
        discovering = true;
        services.clear();
      });

      final found = await device.discoverServices();

      if (!mounted) return;
      setState(() {
        services.addAll(found);
        discovering = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${found.length} service(s) trouvé(s)')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => discovering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur discoverServices: $e')),
      );
    }
  }

  String _bytesToText(List<int> bytes) {
    if (bytes.isEmpty) return '(vide)';
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    }
  }

  Future<void> readCharacteristic(BluetoothCharacteristic c) async {
    try {
      final value = await c.read();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Read ${c.uuid}: ${_bytesToText(value)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur read ${c.uuid}: $e')),
      );
    }
  }

  Future<void> openPermissions() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final connectedName = connectedDevice == null
        ? 'Aucune'
        : (connectedDevice!.platformName.isEmpty
            ? 'Device inconnu'
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
            icon: const Icon(Icons.settings),
            onPressed: openPermissions,
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            onPressed: connectedDevice == null ? null : disconnectDevice,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Text('Connecté : $connectedName')),
                const SizedBox(width: 12),
                Text(
                  'État : ${connectionState.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Permissions: $permissionDebug',
              style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: scanning ? null : startScan,
                child: Text(scanning ? 'Scan...' : 'Scanner Bluetooth'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (connectedDevice == null || discovering)
                    ? null
                    : discoverDeviceServices,
                child: Text(discovering ? 'Services...' : 'Discover services'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Appareils trouvés',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Aucun périphérique trouvé pour le moment'),
                  ),
                for (final result in devices)
                  ListTile(
                    title: Text(
                      result.device.platformName.isEmpty
                          ? 'Device inconnu'
                          : result.device.platformName,
                    ),
                    subtitle: Text(result.device.remoteId.toString()),
                    trailing: ElevatedButton(
                      onPressed: () => connectToDevice(result.device),
                      child: const Text('Connect'),
                    ),
                  ),
                if (services.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Services BLE',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final s in services)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Service: ${s.uuid}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            for (final c in s.characteristics)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(child: Text('Char: ${c.uuid}')),
                                    ElevatedButton(
                                      onPressed: () => readCharacteristic(c),
                                      child: const Text('Read'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
