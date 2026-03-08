import 'package:flutter/material.dart';
import 'dart:async';
import 'connman_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AGL Wi-Fi Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const WifiPage(),
    );
  }
}

class WifiPage extends StatefulWidget {
  const WifiPage({super.key});

  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  bool _isWifiPowered = false;
  bool _isConnected = false;
  List<Map<String, dynamic>> _wifiServices = [];
  bool _isRefreshing = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshWifiStatus();
    // Periodically refresh the Wi-Fi list and status
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _refreshWifiStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshWifiStatus() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });

    final techInfo = await ConnmanService.getWifiTechnology();
    if (techInfo != null) {
      _isWifiPowered = techInfo['powered'] ?? false;
      _isConnected = techInfo['connected'] ?? false;
    } else {
      _isWifiPowered = false;
      _isConnected = false;
    }

    if (_isWifiPowered) {
      _wifiServices = await ConnmanService.getWifiServices();
    } else {
      _wifiServices = [];
    }

    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _toggleWifi(bool value) async {
    await ConnmanService.setWifiPowered(value);
    await Future.delayed(const Duration(seconds: 1)); // Wait for state change
    _refreshWifiStatus();
  }

  Future<void> _scanWifi() async {
    setState(() {
      _isRefreshing = true;
    });
    await ConnmanService.scanWifi();
    await Future.delayed(const Duration(seconds: 2)); // Give it time to scan
    _refreshWifiStatus();
  }

  Future<void> _connectService(String path) async {
    setState(() {
      _isRefreshing = true;
    });
    await ConnmanService.connectService(path);
    await Future.delayed(const Duration(seconds: 2));
    _refreshWifiStatus();
  }

  Future<void> _disconnectService(String path) async {
    setState(() {
      _isRefreshing = true;
    });
    await ConnmanService.disconnectService(path);
    await Future.delayed(const Duration(seconds: 2));
    _refreshWifiStatus();
  }

  Future<void> _removeService(String path) async {
    setState(() {
      _isRefreshing = true;
    });
    await ConnmanService.removeService(path);
    await Future.delayed(const Duration(seconds: 1));
    _refreshWifiStatus();
  }

  Widget _buildScanButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ElevatedButton.icon(
        onPressed: (_isWifiPowered && !_isRefreshing) ? _scanWifi : null,
        icon: _isRefreshing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        label: const Text('Scan Wi-Fi'),
      ),
    );
  }

  void _showServiceOptions(BuildContext context, Map<String, dynamic> service) {
    final name = service['name'] ?? 'Unknown network';
    final state = service['state'] ?? 'idle';
    final path = service['path'];

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('State: ${state}'),
              ),
              const Divider(),
              if (state == 'ready' || state == 'online')
                ListTile(
                  leading: const Icon(Icons.wifi_off, color: Colors.red),
                  title: const Text('Disconnect'),
                  onTap: () {
                    Navigator.pop(context);
                    if (path != null) _disconnectService(path);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.wifi, color: Colors.green),
                  title: const Text('Connect'),
                  onTap: () {
                    Navigator.pop(context);
                    if (path != null) _connectService(path);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Forget Network'),
                onTap: () {
                  Navigator.pop(context);
                  if (path != null) _removeService(path);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AGL Wi-Fi Demo'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        actions: [
          Row(
            children: [
              const Text('Wi-Fi Power'),
              Switch(
                value: _isWifiPowered,
                onChanged: _isRefreshing ? null : _toggleWifi,
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Icon(
                            _isWifiPowered ? Icons.wifi : Icons.wifi_off,
                            size: 48,
                            color: _isWifiPowered
                                ? (_isConnected ? Colors.green : Colors.orange)
                                : Colors.grey,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            !_isWifiPowered
                                ? 'Wi-Fi is OFF'
                                : (!_isConnected ? 'Disconnected' : 'Connected'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildScanButton(),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Available Networks',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: _isWifiPowered
                ? ListView.builder(
                    itemCount: _wifiServices.length,
                    itemBuilder: (context, index) {
                      final service = _wifiServices[index];
                      final name = service['name'] ?? 'Unknown network';
                      final state = service['state'] ?? 'idle';
                      final strength = service['strength'] ?? 0;
                      final security = service['security'] ?? '';

                      final isConnected = state == 'ready' || state == 'online';

                      return ListTile(
                        leading: Icon(
                          isConnected ? Icons.wifi : Icons.signal_wifi_4_bar,
                          color: isConnected ? Colors.green : null,
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                            '${state} • Security: ${security.isNotEmpty ? security : "None"} • Strength: ${strength}%'),
                        trailing: isConnected
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () => _showServiceOptions(context, service),
                      );
                    },
                  )
                : const Center(
                    child: Text('Turn on Wi-Fi to see available networks.'),
                  ),
          ),
        ],
      ),
    );
  }
}
