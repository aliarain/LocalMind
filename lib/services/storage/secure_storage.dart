import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for sensitive data like encryption keys
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _encryptionKeyKey = 'localmind_encryption_key';
  static const _settingsKeyPrefix = 'localmind_setting_';

  /// Get or create the encryption key for chat storage
  static Future<String> getEncryptionKey() async {
    String? key = await _storage.read(key: _encryptionKeyKey);

    if (key == null) {
      // Generate a new key
      key = _generateKey();
      await _storage.write(key: _encryptionKeyKey, value: key);
    }

    return key;
  }

  static String _generateKey() {
    // Generate a random 32-character key
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();

    for (var i = 0; i < 32; i++) {
      buffer.write(chars[(random + i * 17) % chars.length]);
    }

    return buffer.toString();
  }

  /// Store a secure setting
  static Future<void> setSecureSetting(String key, String value) async {
    await _storage.write(key: '$_settingsKeyPrefix$key', value: value);
  }

  /// Get a secure setting
  static Future<String?> getSecureSetting(String key) async {
    return await _storage.read(key: '$_settingsKeyPrefix$key');
  }

  /// Delete a secure setting
  static Future<void> deleteSecureSetting(String key) async {
    await _storage.delete(key: '$_settingsKeyPrefix$key');
  }

  /// Clear all secure storage (use with caution)
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
