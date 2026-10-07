import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static const String _keyUsername = 'bio_saved_username';
  static const String _keyPassword = 'bio_saved_password';
  static const String _keyEnabled = 'bio_enabled';

  /// Check if device supports biometric authentication
  static Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      return false;
    }
  }

  /// Get list of available biometric hardware types (Face ID, Touch ID, Fingerprint, etc.)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Trigger biometric prompt (Face ID / Touch ID / Fingerprint)
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to log in to PIMS MCP',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      print('Biometric auth error: $e');
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Save user credentials locally for biometric login
  static Future<void> saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyPassword, password);
    await prefs.setBool(_keyEnabled, true);
  }

  /// Get saved credentials if biometric login is enabled
  static Future<Map<String, String>?> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isEnabled = prefs.getBool(_keyEnabled) ?? false;
    final String? username = prefs.getString(_keyUsername);
    final String? password = prefs.getString(_keyPassword);

    if (isEnabled && username != null && username.isNotEmpty && password != null && password.isNotEmpty) {
      return {
        'username': username,
        'password': password,
      };
    }
    return null;
  }

  /// Clear saved credentials
  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyPassword);
    await prefs.remove(_keyEnabled);
  }
}
