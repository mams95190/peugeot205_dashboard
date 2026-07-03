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
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
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
  List<ScanResult> devices = [];
  bool scanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> startScan() async {
    setState(() {
      devices.clear();
      scanning = true;
    });

    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        devices = results;
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

  void connectToDevice(BluetoothDevice device) {
    final name = device.platformName.isEmpty
        ? "Device inconnu"
        : device.platformName;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Appareil sélectionné : $name")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 BLE Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: scanning ? null : startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: scanning ? null : startScan,
            child: Text(scanning ? "Scan..." : "Scanner Bluetooth"),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final d = devices[index].device;

                return ListTile(
                  title: Text(
                    d.platformName.isEmpty
                        ? "Device inconnu"
                        : d.platformName,
                  ),
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
