/// Shared UI for the in-app update flow: check, download, install.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_service.dart';
import '../version.dart';

class UpdatePrompt {
  /// Manual check (Settings -> About -> Check for updates).
  static Future<void> checkForUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    UpdateInfo? info;
    try {
      info = await UpdateService.check(force: true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not check for updates: $e'),
        backgroundColor: const Color(0xFF1A1A2E),
      ));
      return;
    }
    if (!context.mounted) return;
    if (info == null) {
      messenger.showSnackBar(SnackBar(
        content: Text('Applix $kAppVersion is up to date'),
        backgroundColor: const Color(0xFF1A1A2E),
      ));
      return;
    }
    await showUpdateDialog(context, info);
  }

  /// Ask the user whether to install [info].
  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update available',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'Applix ${info.version} is out. You are running $kAppVersion.\n\n'
          'The update is signed with the same key, so your apps and settings stay exactly as they are.',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: const Text('Later', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'install'),
            child: const Text('Download & install',
                style: TextStyle(color: Color(0xFF4FC3F7))),
          ),
        ],
      ),
    );
    if (action != 'install' || !context.mounted) return;
    await downloadAndInstall(context, info);
  }

  /// Download the APK (with progress) and hand it to the system installer.
  static Future<void> downloadAndInstall(BuildContext context, UpdateInfo info) async {
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('Starting download...');
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (ctx, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloading ${info.assetName}',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: value <= 0 ? null : value,
                  color: const Color(0xFF4FC3F7),
                  backgroundColor: Colors.white12,
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (ctx, text, _) => Text(text,
                      style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ),
              ],
            ),
          ),
        );
      },
    );

    File? apk;
    try {
      // The progress is throttled: a 40 MB download delivers thousands of
      // chunks and every one of them would rebuild the dialog.
      var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
      apk = await UpdateService.download(info, onProgress: (received, total) {
        final now = DateTime.now();
        if (now.difference(lastPaint).inMilliseconds < 100) return;
        lastPaint = now;
        if (total > 0) progress.value = (received / total).clamp(0.0, 1.0).toDouble();
        final mb = (received / 1048576).toStringAsFixed(1);
        status.value = total > 0
            ? '$mb / ${(total / 1048576).toStringAsFixed(1)} MB'
            : '$mb MB';
      });
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).pop();
      }
      status.value = 'Installing...';
      messenger.showSnackBar(SnackBar(
        content: const Text('Installing update...'),
        backgroundColor: const Color(0xFF1A1A2E),
      ));
      await UpdateService.install(apk, expectedSha256: info.sha256);
      // Android restarts the app after the package is replaced.
    } catch (e) {
      final ctx = dialogContext;
      if (ctx != null && ctx.mounted) {
        Navigator.of(ctx).pop();
      }
      if (!context.mounted) return;
      // The downloaded APK is kept on disk so the user can retry, and the
      // release page is offered as a manual fallback.
      await _showInstallFailure(context, info, '$e');
    } finally {
      // Give the closing dialog animation time before the notifiers go away.
      Future.delayed(const Duration(milliseconds: 600), () {
        progress.dispose();
        status.dispose();
      });
    }
  }

  /// Explains a failed install and offers the manual fallback.
  static Future<void> _showInstallFailure(
      BuildContext context, UpdateInfo info, String error) async {
    final needsPermission = error.contains('ALLOW_INSTALL_UNKNOWN');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Update failed',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          needsPermission
              ? 'Android needs your permission before Applix can install the update.\n\n'
                  'Open the app settings, allow "Install unknown apps" for Applix, then try again.'
              : 'The system refused the package.\n\n$error\n\n'
                  'The downloaded file is kept on the device, so you can install it '
                  'manually from the browser - it is the same file that was just verified.',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (needsPermission) {
                UpdateService.openAppSettings();
              } else {
                UpdateService.openUrl(info.downloadUrl);
              }
            },
            child: Text(needsPermission ? 'Open settings' : 'Open in browser',
                style: const TextStyle(color: Color(0xFF4FC3F7))),
          ),
        ],
      ),
    );
  }
}

/// Slim banner shown on My Apps when a newer release exists.
class UpdateBanner extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onDismiss;

  const UpdateBanner({super.key, required this.info, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10233A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4FC3F7)),
      ),
      child: Row(children: [
        const Icon(Icons.system_update_alt, size: 18, color: Color(0xFF4FC3F7)),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => UpdatePrompt.showUpdateDialog(context, info),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Applix ${info.version} is available',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 2),
                const Text('Tap to download and install',
                    style: TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () => UpdatePrompt.showUpdateDialog(context, info),
          child: const Text('Update',
              style: TextStyle(fontSize: 12, color: Color(0xFF4FC3F7))),
        ),
        GestureDetector(
          onTap: onDismiss,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.close, size: 14, color: Colors.white38),
          ),
        ),
      ]),
    );
  }
}
