import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ConnmanService {
  static const MethodChannel _channel = MethodChannel('com.toyota.connman');

  /// Gets the current Wi-Fi technology status
  static Future<Map<String, dynamic>?> getWifiTechnology() async {
    try {
      final result = await _channel.invokeMethod('getWifiTechnology');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('Failed to get Wi-Fi technology: ${e.message}');
      return null;
    }
  }

  /// Sets the Wi-Fi powered state
  static Future<bool> setWifiPowered(bool powered) async {
    try {
      final result = await _channel.invokeMethod('setWifiPowered', {
        'powered': powered,
      });
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to set Wi-Fi powered: ${e.message}');
      return false;
    }
  }

  /// Triggers a Wi-Fi scan
  static Future<bool> scanWifi() async {
    try {
      final result = await _channel.invokeMethod('scanWifi');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to scan Wi-Fi: ${e.message}');
      return false;
    }
  }

  /// Gets a list of available Wi-Fi services
  static Future<List<Map<String, dynamic>>> getWifiServices() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('getWifiServices');
      if (result != null) {
        return result.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } on PlatformException catch (e) {
      debugPrint('Failed to get Wi-Fi services: ${e.message}');
      return [];
    }
  }

  /// Connects to a specific Wi-Fi service
  static Future<bool> connectService(String path) async {
    try {
      final result = await _channel.invokeMethod('connectService', {
        'path': path,
      });
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to connect service: ${e.message}');
      return false;
    }
  }

  /// Disconnects from a specific Wi-Fi service
  static Future<bool> disconnectService(String path) async {
    try {
      final result = await _channel.invokeMethod('disconnectService', {
        'path': path,
      });
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to disconnect service: ${e.message}');
      return false;
    }
  }

  /// Removes (forgets) a specific Wi-Fi service
  static Future<bool> removeService(String path) async {
    try {
      final result = await _channel.invokeMethod('removeService', {
        'path': path,
      });
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('Failed to remove service: ${e.message}');
      return false;
    }
  }
}
