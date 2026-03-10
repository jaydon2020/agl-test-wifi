import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connman_service.dart';

// ---------------------------------------------------------------------------
// Entry-point
// ---------------------------------------------------------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ConnmanService.init(); // Register the reverse MethodChannel handler.
  runApp(const MyApp());
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AGL Wi-Fi Demo',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const WifiPage(),
    );
  }
}

/// Global navigator key so that `ConnmanService.onRequestInput` can push a
/// dialog even though it is called outside of any widget context.
final _navigatorKey = GlobalKey<NavigatorState>();

// ---------------------------------------------------------------------------
// Password dialog — displayed when C++ agent calls requestInput.
// ---------------------------------------------------------------------------

Future<Map<String, String>?> _showPasswordDialog(
    String service, List<String> fields) async {
  final context = _navigatorKey.currentContext;
  if (context == null) return null;

  final ssidHint = service.split('/').last;
  final controllers = {for (final f in fields) f: TextEditingController()};

  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Wi-Fi Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Network: $ssidHint'),
            ...fields.map(
              (field) => TextField(
                controller: controllers[field],
                decoration: InputDecoration(labelText: field),
                obscureText: field.toLowerCase().contains('passphrase') ||
                    field.toLowerCase().contains('password'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(
              {for (final f in fields) f: controllers[f]!.text},
            ),
            child: const Text('Connect'),
          ),
        ],
      );
    },
  );

  for (final c in controllers.values) c.dispose();
  return result;
}

// ---------------------------------------------------------------------------
// Main Wi-Fi page
// ---------------------------------------------------------------------------

class WifiPage extends StatefulWidget {
  const WifiPage({super.key});

  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  // Wi-Fi state
  bool _isWifiPowered = false;
  List<Map<String, dynamic>> _wifiServices = [];

  // Async helpers
  bool _isRefreshing = false;
  bool _isBusy = false;
  bool _isToggling = false;
  StreamSubscription<dynamic>? _eventSub;
  static const _eventChannel = EventChannel('org.automotivelinux.connman/events');

  @override
  void initState() {
    super.initState();
    ConnmanService.onRequestInput = _showPasswordDialog;
    _initSystemWifi();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    ConnmanService.onRequestInput = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // System initialisation
  // ---------------------------------------------------------------------------

  Future<void> _initSystemWifi() async {
    try {
      await Process.run('rfkill', ['unblock', 'wifi']);
      await Process.run('ip', ['link', 'set', 'wlan0', 'up']);
    } catch (e) {
      debugPrint('System wifi setup error: $e');
    }
    await _startMonitoring();
    await _refreshWifiStatus();
  }

  Future<void> _startMonitoring() async {
    if (_eventSub != null) return;
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (err) => debugPrint('EventChannel error: $err'),
    );
  }

  Future<void> _stopMonitoring() async {
    await _eventSub?.cancel();
    _eventSub = null;
  }

  // ---------------------------------------------------------------------------
  // EventChannel — incoming events from C++
  // ---------------------------------------------------------------------------

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    final type = event['type'] as String? ?? '';

    if (type == 'servicesChanged') {
      final rawList = event['services'] as List? ?? [];
      setState(() {
        _isBusy = false;
        _wifiServices = rawList.map((e) {
          final svc = Map<String, dynamic>.from(e as Map);
          // Normalize keys to handle both lowercase and standard D-Bus casing
          return {
            'name': svc['name'] ?? svc['Name'],
            'state': svc['state'] ?? svc['State'],
            'favorite': svc['favorite'] ?? svc['Favorite'],
            'path': svc['path'] ?? svc['Path'],
            'type': svc['type'] ?? svc['Type'],
            'security': svc['security'] ?? svc['Security'],
            'strength': svc['strength'] ?? svc['Strength'],
            ...svc, // Keep original keys too
          };
        }).toList();
      });
    } else if (type == 'technologyChanged') {
      final powered = event['powered'] ?? event['Powered'];
      setState(() {
        _isBusy = false;
        if (powered is bool) _isWifiPowered = powered;
        if (_isWifiPowered == false) _wifiServices = [];
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Refresh helpers
  // ---------------------------------------------------------------------------

  Future<void> _refreshWifiStatus() async {
    if (_isRefreshing) return;
    if (mounted) setState(() => _isRefreshing = true);

    final techInfo = await ConnmanService.getWifiTechnology();
    if (techInfo != null) {
      _isWifiPowered = techInfo['powered'] as bool? ?? false;
    }

    if (_isWifiPowered) {
      final results = await ConnmanService.getWifiServices();
      _wifiServices = results.map((svc) {
        // Normalize keys here as well
        return {
          'name': svc['name'] ?? svc['Name'],
          'state': svc['state'] ?? svc['State'],
          'favorite': svc['favorite'] ?? svc['Favorite'],
          'path': svc['path'] ?? svc['Path'],
          'type': svc['type'] ?? svc['Type'],
          'security': svc['security'] ?? svc['Security'],
          'strength': svc['strength'] ?? svc['Strength'],
          ...svc,
        };
      }).toList();

      if (_wifiServices.isNotEmpty) {
        debugPrint('First wifi service keys: ${_wifiServices.first.keys}');
        debugPrint('First wifi service: ${_wifiServices.first}');
      }
    } else {
      _wifiServices = [];
    }

    if (mounted) setState(() {
      _isRefreshing = false;
      _isBusy = false;
    });
  }

  // ---------------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------------

  Future<void> _toggleWifi(bool value) async {
    if (mounted) setState(() => _isToggling = true);
    if (value) {
      try {
        await Process.run('rfkill', ['unblock', 'wifi']);
        await Process.run('ip', ['link', 'set', 'wlan0', 'up']);
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('Wi-Fi hw setup error: $e');
      }
    }

    try {
      await ConnmanService.setWifiPowered(value);
      if (value) {
        await _startMonitoring();
        final techInfo = await ConnmanService.getWifiTechnology();
        if (techInfo != null && mounted) {
          setState(() {
            _isWifiPowered = techInfo['powered'] as bool? ?? false;
          });
          if (_isWifiPowered) {
            _wifiServices = await ConnmanService.getWifiServices();
          }
        }
      } else {
        await _stopMonitoring();
        if (mounted) {
          setState(() {
            _isWifiPowered = false;
            _wifiServices = [];
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  Future<void> _scanWifi() async {
    if (mounted) setState(() => _isBusy = true);
    await ConnmanService.scanWifi();
  }

  Future<void> _connectService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    await ConnmanService.connectService(path);
  }

  Future<void> _disconnectService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    await ConnmanService.disconnectService(path);
  }

  Future<void> _removeService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    await ConnmanService.removeService(path);
  }

  // ---------------------------------------------------------------------------
  // Service options
  // ---------------------------------------------------------------------------

  void _showServiceOptions(BuildContext ctx, Map<String, dynamic> service) {
    final name = service['name'] as String? ?? 'Unknown';
    final state = service['state'] as String? ?? 'idle';
    final path = service['path'] as String?;
    final isConnectedSvc = state == 'ready' || state == 'online';

    showModalBottomSheet(
      context: ctx,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(name), subtitle: Text('State: $state')),
          if (isConnectedSvc)
            ListTile(
              title: const Text('Disconnect'),
              onTap: () {
                Navigator.pop(ctx);
                if (path != null) _disconnectService(path);
              },
            )
          else
            ListTile(
              title: const Text('Connect'),
              onTap: () {
                Navigator.pop(ctx);
                if (path != null) _connectService(path);
              },
            ),
          ListTile(
            title: const Text('Forget'),
            onTap: () {
              Navigator.pop(ctx);
              if (path != null) _removeService(path);
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi'),
        actions: [
          if (_isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator()),
            ),
          Switch(
            value: _isWifiPowered,
            onChanged: (_isRefreshing || _isToggling) ? null : _toggleWifi,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_isWifiPowered && !_isBusy) ? _scanWifi : null,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark),
            tooltip: 'Saved Networks',
            onPressed: _isWifiPowered
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SavedNetworksPage(
                          services: _wifiServices,
                          onRemove: (path) => _removeService(path),
                          onConnect: (path) => _connectService(path),
                          onDisconnect: (path) => _disconnectService(path),
                        ),
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
      body: _isWifiPowered
          ? _wifiServices.isEmpty
              ? const Center(child: Text('No networks found'))
              : _buildGroupedList()
          : const Center(child: Text('Wi-Fi is disabled')),
    );
  }

  Widget _buildGroupedList() {
    final saved = _wifiServices.where((s) => s['favorite'] == true).toList();
    final available = _wifiServices.where((s) => s['favorite'] != true).toList();

    return ListView(
      children: [
        if (saved.isNotEmpty) ...[
          const ListTile(
            title: Text('SAVED NETWORKS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ...saved.map((svc) => _buildServiceTile(svc)),
          const Divider(),
        ],
        if (available.isNotEmpty) ...[
          const ListTile(
            title: Text('AVAILABLE NETWORKS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ...available.map((svc) => _buildServiceTile(svc)),
        ],
      ],
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> svc) {
    final name = svc['name'] as String? ?? 'Unknown';
    final state = svc['state'] as String? ?? 'idle';
    final isConn = state == 'ready' || state == 'online';
    final isFavorite = svc['favorite'] == true;

    return ListTile(
      leading: Icon(isConn
          ? Icons.wifi
          : (isFavorite ? Icons.wifi_protected_setup : Icons.wifi_lock)),
      title: Text(name),
      subtitle: Text(state),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFavorite) const Icon(Icons.star, color: Colors.amber, size: 16),
          if (isConn) const Icon(Icons.check, color: Colors.green),
        ],
      ),
      onTap: () => _showServiceOptions(context, svc),
    );
  }
}

// ---------------------------------------------------------------------------
// Saved Networks Page
// ---------------------------------------------------------------------------

class SavedNetworksPage extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final Function(String) onRemove;
  final Function(String) onConnect;
  final Function(String) onDisconnect;

  const SavedNetworksPage({
    super.key,
    required this.services,
    required this.onRemove,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final savedServices = services.where((s) => s['favorite'] == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Networks'),
      ),
      body: savedServices.isEmpty
          ? const Center(child: Text('No saved networks'))
          : ListView.builder(
              itemCount: savedServices.length,
              itemBuilder: (context, index) {
                final svc = savedServices[index];
                final name = svc['name'] as String? ?? 'Unknown';
                final state = svc['state'] as String? ?? 'idle';
                final path = svc['path'] as String? ?? '';
                final isConn = state == 'ready' || state == 'online';

                return ListTile(
                  leading: const Icon(Icons.wifi_protected_setup),
                  title: Text(name),
                  subtitle: Text('State: $state'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isConn) const Icon(Icons.check, color: Colors.green),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          onRemove(path);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    if (isConn) {
                      onDisconnect(path);
                    } else {
                      onConnect(path);
                    }
                    Navigator.pop(context);
                  },
                );
              },
            ),
    );
  }
}
