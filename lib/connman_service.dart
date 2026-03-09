import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Dart wrapper around the C++ `com.toyota.connman` MethodChannel.
///
/// * Regular calls (getWifiTechnology, scanWifi, …) are invoked from Dart → C++.
/// * The `requestInput` callback is invoked FROM C++ → Dart when ConnMan needs
///   a passphrase.  Register [onRequestInput] before using the service.
class ConnmanService {
  static const MethodChannel _channel = MethodChannel('com.toyota.connman');

  /// Optional callback invoked when C++ asks for user credentials.
  ///
  /// The callback receives the service D-Bus path and the field names that
  /// ConnMan requires (usually just `"Passphrase"`).
  /// It must return a map of `fieldName → value` (e.g. `{"Passphrase": "s3cr3t"}`),
  /// or `null` / throw to cancel the connection attempt.
  static Future<Map<String, String>?> Function(
    String service,
    List<String> fields,
  )? onRequestInput;

  /// Initialise the channel — call this once from `main()` or `initState`.
  ///
  /// This registers the method-call handler so Flutter can receive incoming
  /// calls from C++ (e.g. `requestInput`).
  static void init() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  // ---------------------------------------------------------------------------
  // Incoming calls from C++
  // ---------------------------------------------------------------------------

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'requestInput') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final service = args['service'] as String? ?? '';
      final fieldsMap = args['fields'] as Map? ?? {};
      final fields = fieldsMap.keys.cast<String>().toList();

      debugPrint('ConnmanService: requestInput for $service, fields=$fields');

      if (onRequestInput != null) {
        final result = await onRequestInput!(service, fields);
        if (result != null) {
          return result; // {"Passphrase": "..."}
        }
      }
      // Returning null or throwing causes C++ to cancel the connection.
      throw PlatformException(
        code: 'CANCELLED',
        message: 'User cancelled credential input',
      );
    }
    throw MissingPluginException(
        'ConnmanService: no handler for ${call.method}');
  }

  // ---------------------------------------------------------------------------
  // Outgoing calls to C++
  // ---------------------------------------------------------------------------

  /// Gets the current Wi-Fi technology status.
  static Future<Map<String, dynamic>?> getWifiTechnology() async {
    try {
      final result = await _channel.invokeMethod('getWifiTechnology');
      if (result != null) return Map<String, dynamic>.from(result);
      return null;
    } on PlatformException catch (e) {
      debugPrint('Failed to get Wi-Fi technology: ${e.message}');
      return null;
    }
  }

  /// Sets the Wi-Fi powered state.
  static Future<bool> setWifiPowered(bool powered) async {
    try {
      final result =
          await _channel.invokeMethod('setWifiPowered', {'powered': powered});
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to set Wi-Fi powered: ${e.message}');
      return false;
    }
  }

  /// Triggers a Wi-Fi scan.
  static Future<bool> scanWifi() async {
    try {
      final result = await _channel.invokeMethod('scanWifi');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to scan Wi-Fi: ${e.message}');
      return false;
    }
  }

  /// Gets a list of available Wi-Fi services.
  static Future<List<Map<String, dynamic>>> getWifiServices() async {
    try {
      final result =
          await _channel.invokeListMethod<dynamic>('getWifiServices');
      if (result != null) {
        return result
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return [];
    } on PlatformException catch (e) {
      debugPrint('Failed to get Wi-Fi services: ${e.message}');
      return [];
    }
  }

  /// Connects to a specific Wi-Fi service.
  static Future<bool> connectService(String path) async {
    try {
      final result =
          await _channel.invokeMethod('connectService', {'path': path});
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to connect service: ${e.message}');
      return false;
    }
  }

  /// Disconnects from a specific Wi-Fi service.
  static Future<bool> disconnectService(String path) async {
    try {
      final result =
          await _channel.invokeMethod('disconnectService', {'path': path});
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to disconnect service: ${e.message}');
      return false;
    }
  }

  /// Removes (forgets) a specific Wi-Fi service.
  static Future<bool> removeService(String path) async {
    try {
      final result =
          await _channel.invokeMethod('removeService', {'path': path});
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to remove service: ${e.message}');
      return false;
    }
  }
}
