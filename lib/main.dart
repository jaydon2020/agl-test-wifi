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
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: Brightness.dark),
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

  // Parse the readable SSID from the D-Bus path.
  // Paths look like: /net/connman/service/wifi_..._<hex-name>_managed_psk
  // We just show the last segment for brevity.
  final ssidHint = service.split('/').last;

  final controllers = {for (final f in fields) f: TextEditingController()};

  final result = await showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      // Track obscure state per field so each can be toggled independently.
      final obscureState = {
        for (final f in fields)
          f: f.toLowerCase().contains('passphrase') ||
              f.toLowerCase().contains('password'),
      };

      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Wi-Fi Password Required'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Network: $ssidHint',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                ...fields.map(
                  (field) {
                    final isSecret =
                        field.toLowerCase().contains('passphrase') ||
                            field.toLowerCase().contains('password');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: controllers[field],
                        obscureText: obscureState[field] ?? false,
                        decoration: InputDecoration(
                          labelText: field,
                          border: const OutlineInputBorder(),
                          suffixIcon: isSecret
                              ? IconButton(
                                  icon: Icon(
                                    obscureState[field] == true
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setDialogState(() {
                                    obscureState[field] =
                                        !(obscureState[field] ?? false);
                                  }),
                                )
                              : null,
                        ),
                        autofocus: true,
                        onSubmitted: (_) => Navigator.of(ctx).pop(
                          {for (final f in fields) f: controllers[f]!.text},
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null), // Cancel
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(
                  {for (final f in fields) f: controllers[f]!.text},
                ),
                child: const Text('Connect'),
              ),
            ],
          );
        },
      );
    },
  );

  for (final c in controllers.values) {
    c.dispose();
  }
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
  bool _isConnected = false;
  List<Map<String, dynamic>> _wifiServices = [];

  // Async helpers
  bool _isRefreshing = false; // guarded inside _refreshWifiStatus
  bool _isBusy = false;       // set by scan/connect/disconnect actions
  bool _showSavedExpanded = false;
  StreamSubscription<dynamic>? _eventSub;
  static const _eventChannel = EventChannel('io.github.jaydon2020/events');

  @override
  void initState() {
    super.initState();

    // Register the password dialog callback.
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

    // Subscribe to EventChannel BEFORE the first poll so we don't miss events.
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (err) => debugPrint('EventChannel error: $err'),
    );

    await _refreshWifiStatus();
  }

  // ---------------------------------------------------------------------------
  // EventChannel — incoming events from C++ (no polling needed)
  // ---------------------------------------------------------------------------

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    final type = event['type'] as String? ?? '';

    if (type == 'servicesChanged') {
      final rawList = event['services'] as List? ?? [];
      setState(() {
        _isBusy = false; // Action completed — clear busy flag.
        _wifiServices = rawList
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // Derive overall connected state.
        _isConnected = _wifiServices
            .any((s) => s['state'] == 'ready' || s['state'] == 'online');
      });
    } else if (type == 'technologyChanged') {
      // Update Wi-Fi powered state from D-Bus signal.
      final powered = event['powered'] as bool?;
      final connected = event['connected'] as bool?;
      setState(() {
        _isBusy = false;
        if (powered != null) _isWifiPowered = powered;
        if (connected != null) _isConnected = connected;
        if (_isWifiPowered == false) _wifiServices = [];
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Refresh helpers (used at startup & after explicit actions)
  // ---------------------------------------------------------------------------

  Future<void> _refreshWifiStatus() async {
    if (_isRefreshing) return;
    if (mounted) setState(() => _isRefreshing = true);

    final techInfo = await ConnmanService.getWifiTechnology();
    if (techInfo != null) {
      _isWifiPowered = techInfo['powered'] as bool? ?? false;
      _isConnected = techInfo['connected'] as bool? ?? false;
    } else {
      _isWifiPowered = false;
      _isConnected = false;
    }

    if (_isWifiPowered) {
      _wifiServices = await ConnmanService.getWifiServices();
    } else {
      _wifiServices = [];
    }

    if (mounted) setState(() {
      _isRefreshing = false;
      _isBusy = false; // clear busy flag once refresh completes
    });
  }

  // ---------------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------------

  Future<void> _toggleWifi(bool value) async {
    if (mounted) setState(() => _isBusy = true);

    // When enabling Wi-Fi, make sure the hardware is unblocked first.
    if (value) {
      try {
        await Process.run('rfkill', ['unblock', 'wifi']);
        await Process.run('ip', ['link', 'set', 'wlan0', 'up']);
      } catch (e) {
        debugPrint('Wi-Fi hw setup error: $e');
      }
    }

    final success = await ConnmanService.setWifiPowered(value);
    if (!success && mounted) {
      _showSnack('Failed to toggle Wi-Fi power.');
      setState(() => _isBusy = false);
      return;
    }
    // Lightweight fallback: fetch technology state in case no
    // technologyChanged event is emitted by the C++ plugin.
    final techInfo = await ConnmanService.getWifiTechnology();
    if (techInfo != null && mounted) {
      setState(() {
        _isWifiPowered = techInfo['powered'] as bool? ?? false;
        _isConnected = techInfo['connected'] as bool? ?? false;
        if (!_isWifiPowered) _wifiServices = [];
        _isBusy = false;
      });
    }
  }

  Future<void> _scanWifi() async {
    if (mounted) setState(() => _isBusy = true);
    final success = await ConnmanService.scanWifi();
    if (!success && mounted) {
      _showSnack('Failed to scan for Wi-Fi.');
      setState(() => _isBusy = false);
    }
    // EventChannel will deliver servicesChanged — no poll needed.
  }

  Future<void> _connectService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    final success = await ConnmanService.connectService(path);
    if (!success && mounted) {
      _showSnack('Failed to connect to network.');
      setState(() => _isBusy = false);
    }
    // EventChannel will deliver servicesChanged — no poll needed.
  }

  Future<void> _disconnectService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    final success = await ConnmanService.disconnectService(path);
    if (!success && mounted) {
      _showSnack('Failed to disconnect from network.');
      setState(() => _isBusy = false);
    }
    // EventChannel will deliver servicesChanged — no poll needed.
  }

  Future<void> _removeService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    final success = await ConnmanService.removeService(path);
    if (!success && mounted) {
      _showSnack('Failed to forget network.');
      setState(() => _isBusy = false);
    }
    // EventChannel will deliver servicesChanged — no poll needed.
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------------
  // Service options bottom sheet
  // ---------------------------------------------------------------------------

  void _showServiceOptions(BuildContext ctx, Map<String, dynamic> service) {
    final name = service['name'] as String? ?? 'Unknown network';
    final state = service['state'] as String? ?? 'idle';
    final path = service['path'] as String?;
    final isConnectedSvc = state == 'ready' || state == 'online';

    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('State: $state'),
            ),
            const Divider(),
            if (isConnectedSvc)
              ListTile(
                leading: const Icon(Icons.wifi_off, color: Colors.red),
                title: const Text('Disconnect'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (path != null) _disconnectService(path);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.wifi, color: Colors.green),
                title: const Text('Connect'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (path != null) _connectService(path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Forget Network'),
              onTap: () {
                Navigator.pop(ctx);
                if (path != null) _removeService(path);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final savedNetworks = _wifiServices
        .where((s) => s['favorite'] == true)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AGL Wi-Fi Demo'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        actions: [
          Row(
            children: [
              const Text('Wi-Fi'),
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
          // Status card + scan button
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                                : (_isConnected ? 'Connected' : 'Disconnected'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton.icon(
                    onPressed:
                        (_isWifiPowered && !_isBusy) ? _scanWifi : null,
                    icon: _isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Scan'),
                  ),
                ),
              ],
            ),
          ),

          // Saved Networks — expandable section
          if (_isWifiPowered && savedNetworks.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _showSavedExpanded = !_showSavedExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Saved Networks',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Icon(_showSavedExpanded
                        ? Icons.expand_less
                        : Icons.expand_more),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: savedNetworks.map((svc) {
                  final name = svc['name'] as String? ?? 'Unknown';
                  final state = svc['state'] as String? ?? 'idle';
                  final path = svc['path'] as String?;
                  final isConn = state == 'ready' || state == 'online';
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.wifi,
                        color: isConn ? Colors.green : null, size: 20),
                    title: Text(name),
                    subtitle: Text(isConn ? 'Connected' : 'Saved'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Forget',
                      onPressed: () {
                        if (path != null) _removeService(path);
                      },
                    ),
                    onTap: () => _showServiceOptions(context, svc),
                  );
                }).toList(),
              ),
              crossFadeState: _showSavedExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
            const Divider(height: 1),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Available Networks',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),

          Expanded(
            child: _isWifiPowered
                ? ListView.builder(
                    itemCount: _wifiServices.length,
                    itemBuilder: (ctx, i) {
                      final svc = _wifiServices[i];
                      final name =
                          svc['name'] as String? ?? 'Unknown network';
                      final state = svc['state'] as String? ?? 'idle';
                      final strength = svc['strength'] as int? ?? 0;
                      final security = svc['security'] as String? ?? '';
                      final isConn = state == 'ready' || state == 'online';

                      IconData wifiIcon;
                      if (isConn) {
                        wifiIcon = Icons.wifi;
                      } else if (strength >= 67) {
                        wifiIcon = Icons.network_wifi;
                      } else if (strength >= 34) {
                        wifiIcon = Icons.network_wifi_2_bar;
                      } else if (strength > 0) {
                        wifiIcon = Icons.network_wifi_1_bar;
                      } else {
                        wifiIcon = Icons.signal_wifi_0_bar;
                      }

                      return ListTile(
                        leading: Icon(
                          wifiIcon,
                          color: isConn ? Colors.green : null,
                        ),
                        title: Text(name,
                            style: TextStyle(
                                fontWeight: isConn
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        subtitle: Text(
                          '$state • '
                          '${security.isNotEmpty ? security : "Open"} • '
                          '$strength%',
                        ),
                        trailing: isConn
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () => _showServiceOptions(ctx, svc),
                      );
                    },
                  )
                : const Center(
                    child:
                        Text('Turn on Wi-Fi to see available networks.')),
          ),
        ],
      ),
    );
  }
}
