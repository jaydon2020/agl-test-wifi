import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Dart wrapper around the C++ `com.toyota.connman` MethodChannel.
///
/// * Regular calls (getWifiTechnology, scanWifi, …) are invoked from Dart → C++.
/// * The `requestInput` callback is invoked FROM C++ → Dart when ConnMan needs
///   a passphrase.  Register [onRequestInput] before using the service.
class ConnmanService {
  static const MethodChannel _channel = MethodChannel('io.github.jaydon2020');

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

  /// Helper to invoke a method with a timeout to avoid hanging the UI.
  static Future<T?> _safeInvokeMethod<T>(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('ConnmanService: Method "$method" timed out after 10s');
          throw TimeoutException('Method "$method" timed out');
        },
      );
    } on TimeoutException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('ConnmanService: Failed to $method: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('ConnmanService: Unexpected error in $method: $e');
      return null;
    }
  }

  /// Gets the current Wi-Fi technology status.
  static Future<Map<String, dynamic>?> getWifiTechnology() async {
    final result = await _safeInvokeMethod('getWifiTechnology');
    if (result != null) return Map<String, dynamic>.from(result as Map);
    return null;
  }

  /// Sets the Wi-Fi powered state.
  static Future<bool> setWifiPowered(bool powered) async {
    final result = await _safeInvokeMethod('setWifiPowered', {'powered': powered});
    return result == true;
  }

  /// Triggers a Wi-Fi scan.
  static Future<bool> scanWifi() async {
    final result = await _safeInvokeMethod('scanWifi');
    return result == true;
  }

  /// Gets a list of available Wi-Fi services.
  static Future<List<Map<String, dynamic>>> getWifiServices() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('getWifiServices').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('ConnmanService: getWifiServices timed out');
          return [];
        },
      );
      if (result != null) {
        return result
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Failed to get Wi-Fi services: $e');
      return [];
    }
  }

  /// Connects to a specific Wi-Fi service.
  static Future<bool> connectService(String path) async {
    final result = await _safeInvokeMethod('connectService', {'path': path});
    return result == true;
  }

  /// Disconnects from a specific Wi-Fi service.
  static Future<bool> disconnectService(String path) async {
    final result = await _safeInvokeMethod('disconnectService', {'path': path});
    return result == true;
  }

  /// Removes (forgets) a specific Wi-Fi service.
  static Future<bool> removeService(String path) async {
    final result = await _safeInvokeMethod('removeService', {'path': path});
    return result == true;
  }
}
