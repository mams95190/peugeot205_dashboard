import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ESP32 Dashboard',
      theme: ThemeData.dark(),
      home: const HomePage(),
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

  void startScan() async {
    setState(() {
      devices.clear();
      scanning = true;
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        devices = results;
      });
    });

    await Future.delayed(const Duration(seconds: 5));

    FlutterBluePlus.stopScan();

    setState(() {
      scanning = false;
    });
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connecté à ${device.name}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 BLE Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: startScan,
          )
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
                  title: Text(d.name.isEmpty ? "Device inconnu" : d.name),
                  subtitle: Text(d.id.toString()),
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