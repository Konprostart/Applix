import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readFirst(List<String> paths) {
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail('none of the files exist: $paths');
}

void main() {
  final bridgeIndex = jsonDecode(
    File('assets/bridge_index.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final prompt = File('assets/system_prompt.md').readAsStringSync();
  final vault = _readFirst([
    '../shell_apk/app/src/main/java/com/applix/generated/placeholder/SecureVault.java',
    'shell_apk/app/src/main/java/com/applix/generated/placeholder/SecureVault.java',
  ]);
  final shell = _readFirst([
    '../shell_apk/app/src/main/java/com/applix/generated/placeholder/ShellActivity.java',
    'shell_apk/app/src/main/java/com/applix/generated/placeholder/ShellActivity.java',
  ]);
  final tasks = _readFirst([
    '../shell_apk/app/src/main/java/com/applix/generated/placeholder/TaskService.java',
    'shell_apk/app/src/main/java/com/applix/generated/placeholder/TaskService.java',
  ]);

  group('secure vault bridge contract', () {
    test('the bridge index exposes every documented vault method', () {
      final secure = (bridgeIndex['modules'] as Map)['secure'] as List;
      expect(
        secure.map((m) => m.toString()).toSet(),
        containsAll({
          'set', 'get', 'has', 'remove', 'clear', 'keys', 'size', 'isAvailable',
        }),
      );
    });

    test('the prompt documents Keystore encryption and secret handling', () {
      expect(prompt, contains('iappyx.secure.set'));
      expect(prompt, contains('iappyx.secure.get'));
      expect(prompt, contains('Android Keystore'));
      expect(prompt, contains('AES-256-GCM'));
      expect(prompt, contains('Never put them in `iappyx.save`'));
      expect(prompt, contains('256 KB'));
    });

    test('the vault stores ciphertext, never plaintext', () {
      expect(vault, contains('AndroidKeyStore'));
      expect(vault, contains('AES/GCM/NoPadding'));
      expect(vault, contains('setUserAuthenticationRequired(false)'));
      expect(vault, contains('putString(key, seal('));
      expect(vault, isNot(contains('putString(key, value)')));
      expect(vault, contains('Base64'));
      expect(vault, contains('MAX_VALUE_BYTES'));
    });

    test('the shell registers the vault for pages and background tasks', () {
      expect(shell, contains('new SecureVault(this)'));
      expect(shell, contains('"iappyxVault"'));
      expect(shell, contains('secure:iappyxVault'));
      expect(tasks, contains('new SecureVault(ctx)'));
      expect(tasks, contains('secure:iappyxVault'));
    });

    test('local storage and IndexedDB are enabled in the shell', () {
      expect(shell, contains('setDomStorageEnabled(true)'));
      expect(shell, contains('setDatabaseEnabled(true)'));
      expect(tasks, contains('setDomStorageEnabled(true)'));
      expect(tasks, contains('setDatabaseEnabled(true)'));
    });
  });
}
