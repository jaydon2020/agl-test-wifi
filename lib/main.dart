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

// ---------------------------------------------------------------------------
// Saved Networks Page
// ---------------------------------------------------------------------------

class SavedNetworksPage extends StatefulWidget {
  const SavedNetworksPage({super.key});

  @override
  State<SavedNetworksPage> createState() => _SavedNetworksPageState();
}

class _SavedNetworksPageState extends State<SavedNetworksPage> {
  List<Map<String, String>> _savedNetworks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedNetworks();
  }

  Future<void> _loadSavedNetworks() async {
    setState(() => _isLoading = true);
    final networks = <Map<String, String>>[];

    try {
      final dir = Directory('/var/lib/connman');
      if (await dir.exists()) {
        final entries = dir.listSync();
        for (final entry in entries) {
          if (entry is Directory) {
            final folderName = entry.path.split('/').last;
            if (folderName.startsWith('wifi_')) {
              final settingsFile = File('${entry.path}/settings');
              if (await settingsFile.exists()) {
                final content = await settingsFile.readAsLines();

                String? name;
                String? passphrase;
                String? autoconnect;
                String? modified;

                for (final line in content) {
                  if (line.startsWith('Name=')) name = line.substring(5);
                  else if (line.startsWith('Passphrase=')) passphrase = line.substring(11);
                  else if (line.startsWith('AutoConnect=')) autoconnect = line.substring(12);
                  else if (line.startsWith('Modified=')) modified = line.substring(9);
                }

                if (name != null) {
                  networks.add({
                    'id': folderName,
                    'path': '/net/connman/service/$folderName',
                    'name': name,
                    'passphrase': passphrase ?? '',
                    'autoconnect': autoconnect ?? 'false',
                    'modified': modified ?? '',
                  });
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading saved networks: $e');
    }

    if (mounted) {
      setState(() {
        _savedNetworks = networks;
        _isLoading = false;
      });
    }
  }

  Future<void> _forgetNetwork(String path, String name) async {
    try {
      final success = await ConnmanService.removeService(path);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Forgot network: $name')),
          );
          _loadSavedNetworks(); // refresh
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to forget network: $name'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Error forgetting network $path: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Networks'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedNetworks.isEmpty
              ? const Center(child: Text('No saved networks found', style: TextStyle(fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _savedNetworks.length,
                  itemBuilder: (context, index) {
                    final net = _savedNetworks[index];
                    return _SavedNetworkCard(
                      network: net,
                      onForget: () => _forgetNetwork(net['path']!, net['name']!),
                    );
                  },
                ),
    );
  }
}

class _SavedNetworkCard extends StatefulWidget {
  final Map<String, String> network;
  final VoidCallback onForget;

  const _SavedNetworkCard({
    required this.network,
    required this.onForget,
  });

  @override
  State<_SavedNetworkCard> createState() => _SavedNetworkCardState();
}

class _SavedNetworkCardState extends State<_SavedNetworkCard> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.network['name']!;
    final passphrase = widget.network['passphrase']!;
    final autoconnect = widget.network['autoconnect'] == 'true';
    final hasPassword = passphrase.isNotEmpty;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Name and AutoConnect icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (autoconnect)
                  const Tooltip(
                    message: 'Auto-connects',
                    child: Icon(Icons.autorenew, color: Colors.blue),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Password Section
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasPassword
                        ? (_showPassword ? passphrase : '•' * passphrase.length)
                        : 'No password',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: hasPassword ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ),
                if (hasPassword)
                  IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                  ),
              ],
            ),

            const Divider(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Forget', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                  onPressed: widget.onForget,
                ),
              ],
            ),
          ],
        ),
      ),
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
  bool _obscureText = true;

  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Wi-Fi Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Network: $ssidHint', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...fields.map((field) {
                  final isPassword = field.toLowerCase().contains('passphrase') ||
                      field.toLowerCase().contains('password');
                  return TextField(
                    controller: controllers[field],
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: field,
                      border: const OutlineInputBorder(),
                      suffixIcon: isPassword
                          ? IconButton(
                              icon: Icon(
                                _obscureText ? Icons.visibility : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureText = !_obscureText;
                                });
                              },
                            )
                          : null,
                    ),
                    obscureText: isPassword && _obscureText,
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(
                  {for (final f in fields) f: controllers[f]!.text},
                ),
                child: const Text('Connect'),
              ),
            ],
          );
        }
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
      // Ensure hardware is enabled at startup
      await Process.run('rfkill', ['unblock', 'wifi']);
      await Process.run('ip', ['link', 'set', 'wlan0', 'up']);
      // Brief delay for the wireless interface to register with ConnMan
      await Future.delayed(const Duration(seconds: 1));
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

    try {
      final techInfo = await ConnmanService.getWifiTechnology();
      if (techInfo != null) {
        _isWifiPowered = (techInfo['powered'] ?? techInfo['Powered']) == true;
      }

      if (_isWifiPowered) {
        final results = await ConnmanService.getWifiServices();
        // ... (normalization logic)
        final mapped = results.map((svc) {
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

        // Filter out hidden or unknown networks where the name is empty or missing
        _wifiServices = mapped.where((svc) {
          final name = svc['name'] as String?;
          return name != null && name.trim().isNotEmpty;
        }).toList();
      } else {
        _wifiServices = [];
      }
    } finally {
      if (mounted) setState(() {
        _isRefreshing = false;
        _isBusy = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------------

  Future<void> _toggleWifi(bool value) async {
    if (mounted) setState(() => _isToggling = true);
    
    if (value) {
      try {
        // Force hardware up before enabling in ConnMan
        await Process.run('rfkill', ['unblock', 'wifi']);
        await Process.run('ip', ['link', 'set', 'wlan0', 'up']);
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        debugPrint('Wi-Fi hw setup error: $e');
      }
    }

    try {
      // Call ConnMan to set power state
      final success = await ConnmanService.setWifiPowered(value);
      
      if (!success) {
        debugPrint('Failed to set Wi-Fi powered state to $value');
        await _refreshWifiStatus();
        return;
      }

      if (value) {
        await _startMonitoring();
        // Wait a bit and refresh status
        await Future.delayed(const Duration(seconds: 1));
        await _refreshWifiStatus();
      } else {
        await _stopMonitoring();
        if (mounted) {
          setState(() {
            _isWifiPowered = false;
            _wifiServices = [];
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling Wi-Fi: $e');
      await _refreshWifiStatus();
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  Future<void> _scanWifi() async {
    if (mounted) setState(() => _isBusy = true);

    try {
      bool success = await ConnmanService.scanWifi();
      if (!success) {
        debugPrint('Wi-Fi scan failed or not implemented, attempting hardware re-init...');
        // Attempt to unblock and bring the link up
        await Process.run('rfkill', ['unblock', 'wifi']);
        await Process.run('ip', ['link', 'set', 'wlan0', 'up']);

        // Give it a moment to settle
        await Future.delayed(const Duration(seconds: 1));

        // Retry the scan
        success = await ConnmanService.scanWifi();
      }

      // If still not successful, try to refresh the status anyway as it might have recovered
      if (!success) {
        await _refreshWifiStatus();
      }
    } catch (e) {
      debugPrint('Error during scan handle: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _connectService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    try {
      final success = await ConnmanService.connectService(path);
      if (!success && mounted) {
        debugPrint('Failed to connect to service');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to network. Check password or try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      // It is important to wait a short moment or check state from DBus.
      // We rely on servicesChanged event to clear `_isBusy` on success,
      // but we should clear it here if it fails, or after a timeout
      // to avoid getting stuck. The underlying method has a timeout,
      // so if it completes without the event clearing `_isBusy`, we
      // should clear it.
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _disconnectService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    try {
      await ConnmanService.disconnectService(path);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _removeService(String path) async {
    if (mounted) setState(() => _isBusy = true);
    try {
      await ConnmanService.removeService(path);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Service options
  // ---------------------------------------------------------------------------

  void _showServiceOptions(BuildContext ctx, Map<String, dynamic> service) {
    final name = service['name'] as String? ?? 'Unknown';
    final state = service['state'] as String? ?? 'idle';
    final path = service['path'] as String?;
    final isConnectedSvc = state == 'ready' || state == 'online';
    final isFavorite = service['favorite'] == true;
    final strength = (service['strength'] as num?)?.toInt() ?? 0;
    final security = (service['security'] as List?)?.join(', ') ?? 'none';

    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _getWifiIcon(strength, security, connected: isConnectedSvc),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: Text('Status: ${_formatState(state)}\nSignal: $strength%\nSecurity: $security'),
              isThreeLine: true,
            ),
            const Divider(),
            if (isConnectedSvc)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Disconnect'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (path != null) _disconnectService(path);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Connect'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (path != null) _connectService(path);
                },
              ),
            if (isFavorite) // Only show 'Forget' if it's a saved network
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Forget Network', style: TextStyle(color: Colors.red)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi'),
        actions: [
          if (_isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Switch(
            value: _isWifiPowered,
            onChanged: (_isRefreshing || _isToggling) ? null : _toggleWifi,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan for networks',
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
                        builder: (context) => const SavedNetworksPage(),
                      ),
                    ).then((_) => _refreshWifiStatus());
                  }
                : null,
          ),
          const SizedBox(width: 8),
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
    // Separate into Connected, Saved, and Available networks.
    final connected = _wifiServices.where((s) => s['state'] == 'ready' || s['state'] == 'online').toList();
    // Exclude connected from saved to avoid duplication.
    final saved = _wifiServices.where((s) => s['favorite'] == true && s['state'] != 'ready' && s['state'] != 'online').toList();
    // Available: neither connected nor saved.
    final available = _wifiServices.where((s) => s['favorite'] != true && s['state'] != 'ready' && s['state'] != 'online').toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      children: [
        if (connected.isNotEmpty) ...[
          _buildSectionHeader('CONNECTED'),
          ...connected.map((svc) => _buildConnectedCard(svc)),
          const SizedBox(height: 16),
        ],
        if (saved.isNotEmpty) ...[
          _buildSectionHeader('SAVED NETWORKS'),
          ...saved.map((svc) => _buildServiceTile(svc)),
          const Divider(height: 32),
        ],
        if (available.isNotEmpty) ...[
          _buildSectionHeader('AVAILABLE NETWORKS'),
          ...available.map((svc) => _buildServiceTile(svc)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _getWifiIcon(int strength, String security, {bool connected = false}) {
    final isSecure = security != 'none' && security != '';
    IconData iconData;

    if (strength > 75) {
      iconData = isSecure ? Icons.signal_wifi_4_bar_lock : Icons.signal_wifi_4_bar;
    } else if (strength > 50) {
      iconData = isSecure ? Icons.network_wifi_3_bar : Icons.network_wifi_3_bar; // fallback lock handling
    } else if (strength > 25) {
      iconData = isSecure ? Icons.network_wifi_2_bar : Icons.network_wifi_2_bar;
    } else {
      iconData = isSecure ? Icons.network_wifi_1_bar : Icons.network_wifi_1_bar;
    }

    // For Material Icons, standard "signal_wifi_X_bar" icons look best.
    // We can simulate the lock with a badge if preferred, or just rely on standard icons.
    if (isSecure && strength <= 75) {
       iconData = Icons.wifi_lock; // Generic fallback if precise bar+lock isn't available
    }

    return Icon(
      iconData,
      color: connected ? Theme.of(context).colorScheme.primary : Colors.grey[700],
      size: 28,
    );
  }

  String _formatState(String state) {
    switch (state) {
      case 'idle':
        return 'Not connected';
      case 'association':
      case 'configuration':
        return 'Connecting...';
      case 'ready':
      case 'online':
        return 'Connected';
      case 'failure':
        return 'Failed to connect';
      case 'disconnect':
        return 'Disconnecting...';
      default:
        return state[0].toUpperCase() + state.substring(1);
    }
  }

  Widget _buildConnectedCard(Map<String, dynamic> svc) {
    final name = svc['name'] as String? ?? 'Unknown';
    final state = svc['state'] as String? ?? 'idle';
    final strength = (svc['strength'] as num?)?.toInt() ?? 100;
    final security = (svc['security'] as List?)?.join(', ') ?? 'none';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        leading: _getWifiIcon(strength, security, connected: true),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          _formatState(state),
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => _showServiceOptions(context, svc),
        ),
        onTap: () => _showServiceOptions(context, svc),
      ),
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> svc) {
    final name = svc['name'] as String? ?? 'Unknown';
    final state = svc['state'] as String? ?? 'idle';
    final isFavorite = svc['favorite'] == true;
    final strength = (svc['strength'] as num?)?.toInt() ?? 100;
    final security = (svc['security'] as List?)?.join(', ') ?? 'none';

    String subtitleText = isFavorite && state == 'idle' ? 'Saved' : _formatState(state);
    if (state == 'idle' && !isFavorite) {
       subtitleText = security != 'none' ? 'Secured' : 'Open';
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      leading: _getWifiIcon(strength, security),
      title: Text(name, style: const TextStyle(fontSize: 16)),
      subtitle: Text(subtitleText),
      trailing: isFavorite
          ? const Icon(Icons.bookmark, color: Colors.grey, size: 20)
          : null,
      onTap: () => _showServiceOptions(context, svc),
    );
  }
}

