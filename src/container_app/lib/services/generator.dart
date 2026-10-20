// MIT License
//
// Copyright (c) 2026 iappyx
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// Flutter-side wrapper around the native build pipeline (MethodChannel).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BuildResult {
  final String packageName;
  final String apkPath;
  BuildResult({required this.packageName, required this.apkPath});
}

class Generator {
  static const _ch = MethodChannel('com.konprostart.applix/generator');
  static bool _building = false;

  static Future<BuildResult> generateFromTemplate({
    required String label,
    required String templateId,
    required void Function(String) onProgress,
    String? packageName,
    String? iconConfig,
    String? appTheme,
  }) async {
    if (_building) throw PlatformException(code: 'BUSY', message: 'A build is already in progress');
    _building = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') onProgress(call.arguments as String);
    });
    try {
      final result = await _ch.invokeMethod<Map>('generateApp', {
        'label': label,
        'templateId': templateId,
        if (packageName != null) 'packageName': packageName,
        if (iconConfig != null) 'iconConfig': iconConfig,
        if (appTheme != null && appTheme.isNotEmpty) 'appTheme': appTheme,
      });
      return BuildResult(
        packageName: result?['packageName'] as String? ?? '',
        apkPath: result?['apkPath'] as String? ?? '',
      );
    } finally {
      _ch.setMethodCallHandler(null);
      _building = false;
    }
  }

  static Future<BuildResult> injectHtml({
    required String label,
    required String htmlContent,
    required void Function(String) onProgress,
    String? packageName,
    String? iconConfig,
    String? appTheme,
    String? firebaseConfig,
    bool webOnly = false,
    Map<String, String>? bundleFiles,
    Map<String, String>? projectFiles,
  }) async {
    if (_building) throw PlatformException(code: 'BUSY', message: 'A build is already in progress');
    _building = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') onProgress(call.arguments as String);
    });
    try {
      final result = await _ch.invokeMethod<Map>('injectHtml', {
        'label': label,
        'html': htmlContent,
        if (packageName != null) 'packageName': packageName,
        if (iconConfig != null) 'iconConfig': iconConfig,
        if (appTheme != null && appTheme.isNotEmpty) 'appTheme': appTheme,
        if (firebaseConfig != null && firebaseConfig.isNotEmpty) 'firebaseConfig': firebaseConfig,
        'webOnly': webOnly,
        if (bundleFiles != null && bundleFiles.isNotEmpty) 'bundleFiles': bundleFiles,
        if (projectFiles != null && projectFiles.isNotEmpty) 'projectFiles': projectFiles,
      });
      return BuildResult(
        packageName: result?['packageName'] as String? ?? '',
        apkPath: result?['apkPath'] as String? ?? '',
      );
    } finally {
      _ch.setMethodCallHandler(null);
      _building = false;
    }
  }

  static Future<void> shareFile({
    required String path,
    String mimeType = 'application/vnd.android.package-archive',
  }) async {
    await _ch.invokeMethod('shareFile', {
      'path': path,
      'mimeType': mimeType,
    });
  }

  static Future<void> shareText({
    required String content,
    required String filename,
  }) async {
    await _ch.invokeMethod('shareText', {
      'content': content,
      'filename': filename,
    });
  }

  static Future<bool> launchApp({required String packageName}) async {
    final result = await _ch.invokeMethod<bool>('launchApp', {'packageName': packageName});
    return result ?? false;
  }

  static Future<void> openUrl(String url) async {
    await _ch.invokeMethod('openUrl', {'url': url});
  }

  static Future<void> uninstallApp({required String packageName}) async {
    await _ch.invokeMethod('uninstallApp', {'packageName': packageName});
  }

  static Future<String?> getInstalledApkPath(String packageName) async {
    final result = await _ch.invokeMethod<String>('getInstalledApkPath', {'packageName': packageName});
    return result;
  }

  /// Returns "not_installed", "same_signer", or "different_signer".
  static Future<String> checkSignature({required String packageName}) async {
    final result = await _ch.invokeMethod<String>('checkSignature', {'packageName': packageName});
    return result ?? 'not_installed';
  }

  /// The fingerprint of the installed app and of the master key - shown in the
  /// signature conflict dialog so the reason is visible.
  static String? _installedFingerprint;
  static String? _masterFingerprint;

  /// The fingerprint of the signer of an installed app (null when unknown).
  static Future<String?> getInstalledSigner({required String packageName}) async {
    final result = await _ch.invokeMethod<String>('getInstalledSigner', {'packageName': packageName});
    return result;
  }

  /// Checks for signature conflict and shows uninstall dialog if needed.
  /// Returns true if safe to proceed with install, false if user cancelled.
  static Future<bool> handleSignatureConflict({
    required String packageName,
    required BuildContext context,
  }) async {
    if (packageName.isEmpty) return true;
    final sig = await checkSignature(packageName: packageName);
    if (sig != 'different_signer') return true;

    // Show both fingerprints so the user can see that the key really differs.
    try {
      final info = await getKeyInfo();
      _masterFingerprint = info['fingerprint'] as String?;
    } catch (_) {}
    try {
      final installed = await getInstalledSigner(packageName: packageName);
      _installedFingerprint = installed;
    } catch (_) {}

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update required'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'The app on this device was signed with a different key than the one Applix uses now.\n\n'
            'Applix keeps ONE signing key inside the app and uses it for every app it builds. '
            'The key is lost when Applix is uninstalled or its data is cleared - after that the '
            'existing apps can no longer be updated and have to be replaced.\n\n'
            'Replace the app (its data will be deleted) and do not uninstall Applix again.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text('Installed:  ${_installedFingerprint ?? 'unknown'}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Colors.white38)),
          Text('Applix key: ${_masterFingerprint ?? 'unknown'}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Colors.white38)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () async {
              await uninstallApp(packageName: packageName);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Uninstall & replace', style: TextStyle(color: Color(0xFFEA5455))),
          ),
        ],
      ),
    );
    if (proceed != true) return false;

    // Poll until the app is really gone (30s - the uninstall is a system
    // dialog and can take a moment).
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final recheck = await checkSignature(packageName: packageName);
      if (recheck != 'different_signer') return true;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Existing app was not uninstalled')),
      );
    }
    return false;
  }

  /// Status of the durable key backup (it survives an uninstall of Applix).
  static Future<Map<String, dynamic>> getKeyBackupInfo() async {
    final result = await _ch.invokeMethod<Map>('getKeyBackupInfo', {});
    return result ?? {'exists': false, 'name': ''};
  }

  /// Writes the master key backup to the shared Downloads folder.
  static Future<bool> createKeyBackup() async {
    final result = await _ch.invokeMethod<Map>('createKeyBackup', {});
    return result != null;
  }

  /// Restores the master key from the shared backup.
  static Future<bool> restoreKeyBackup() async {
    final result = await _ch.invokeMethod<Map>('restoreKeyBackup', {});
    return result?['restored'] == true;
  }

  static Future<Map<String, dynamic>> getKeyInfo() async {
    final result = await _ch.invokeMethod<Map>('getKeyInfo', {});
    return Map<String, dynamic>.from(result ?? {});
  }
}
