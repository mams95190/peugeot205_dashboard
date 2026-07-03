import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;

  @override
  void initState() {
    super.initState();
    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        _adapterState = state;
      });
    });
  }

  @override
  void dispose() {
    _adapterStateSub?.cancel();
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
        return "Bluetooth désactivé";
      case BluetoothAdapterState.unavailable:
        return "Bluetooth indisponible";
      case BluetoothAdapterState.unauthorized:
        return "Bluetooth non autorisé";
      case BluetoothAdapterState.turningOn:
        return "Activation du Bluetooth...";
      case BluetoothAdapterState.turningOff:
        return "Désactivation du Bluetooth...";
      default:
        return "Vérification du Bluetooth...";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 BLE Dashboard"),
      ),
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
  bool scanning = false;

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

  Future<void> startScan() async {
    setState(() {
      devices.clear();
      scanning = true;
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

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await Future.delayed(const Duration(seconds: 5));
    await FlutterBluePlus.stopScan();

    if (!mounted) return;
    setState(() {
      scanning = false;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();

      await _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (!mounted) return;
        setState(() {
          connectionState = state;
        });
      });

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      if (!mounted) return;
      setState(() {
        connectedDevice = device;
      });

      final name =
          device.platformName.isEmpty ? "Device inconnu" : device.platformName;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connecté à $name")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur connexion: $e")),
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Déconnecté")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur déconnexion: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectedName = connectedDevice == null
        ? "Aucune"
        : (connectedDevice!.platformName.isEmpty
            ? "Device inconnu"
            : connectedDevice!.platformName);

    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 BLE Dashboard"),
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text("Connecté : $connectedName"),
                ),
                const SizedBox(width: 12),
                Text(
                  "État : ${connectionState.name}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: scanning ? null : startScan,
            child: Text(scanning ? "Scan..." : "Scanner Bluetooth"),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final d = devices[index].device;
                final name =
                    d.platformName.isEmpty ? "Device inconnu" : d.platformName;

                return ListTile(
                  title: Text(name),
                  subtitle: Text(d.remoteId.toString()),
                  trailing: ElevatedButton(
                    onPressed: () => connectToDevice(d),
                    child: const Text("Connect"),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
