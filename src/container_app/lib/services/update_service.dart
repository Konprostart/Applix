/// Checks GitHub Releases for a newer Applix version, downloads it and
/// hands it to the Android package installer.
///
/// The whole flow is opt-in: the app never installs anything without the
/// user tapping through the system install dialog.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../version.dart';
import 'settings_service.dart';

/// A newer release that is available on GitHub.
class UpdateInfo {
  final String tag; // e.g. "v0.1.3"
  final String version; // e.g. "0.1.3"
  final String assetName; // e.g. "Applix-0.1.3-container.apk"
  final String downloadUrl;
  final int size; // bytes, 0 when unknown
  final String sha256; // published checksum, empty when the release has none

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    this.size = 0,
    this.sha256 = '',
  });

  UpdateInfo copyWith({String? sha256}) => UpdateInfo(
        tag: tag,
        version: version,
        assetName: assetName,
        downloadUrl: downloadUrl,
        size: size,
        sha256: sha256 ?? this.sha256,
      );

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'version': version,
        'assetName': assetName,
        'downloadUrl': downloadUrl,
        'size': size,
        'sha256': sha256,
      };

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        tag: json['tag'] as String? ?? '',
        version: json['version'] as String? ?? '',
        assetName: json['assetName'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
      );
}

class UpdateService {
  static const repo = 'Konprostart/Applix';
  static const api = 'https://api.github.com';
  static const checkInterval = Duration(hours: 24);
  static const _ch = MethodChannel('com.konprostart.applix/update');

  /// Newest release found by the last successful check (null when up to date).
  static UpdateInfo? latest;

  // ── Pure helpers (unit tested) ──

  /// Split "v0.1.3" or "0.1.3" into [major, minor, patch].
  static List<int> parseVersion(String version) {
    final clean = version.trim().replaceFirst(RegExp('^v'), '');
    final parts = clean.split('.');
    return List<int>.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i].replaceAll(RegExp('[^0-9]'), '')) ?? 0;
    });
  }

  /// > 0 when [a] is newer than [b], 0 when equal, < 0 when older.
  static int compareVersions(String a, String b) {
    final pa = parseVersion(a);
    final pb = parseVersion(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return 0;
  }

  /// Find the signed container APK inside a release payload.
  static String? pickContainerAsset(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return null;
    for (final entry in assets) {
      if (entry is! Map) continue;
      final name = entry['name'];
      if (name is String && name.endsWith('-container.apk')) return name;
    }
    return null;
  }

  /// Pull the hash for [assetName] out of a `sha256sum` file
  /// ("<hash>  <filename>").
  static String? extractChecksum(String content, String assetName) {
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final file = parts.last;
      if (file == assetName || file == './$assetName') {
        return parts.first.toLowerCase();
      }
    }
    return null;
  }

  /// Build the update descriptor from a release payload, or null when the
  /// release is not newer than the running version.
  static UpdateInfo? updateFromRelease(Map<String, dynamic> release) {
    final asset = pickContainerAsset(release);
    if (asset == null) return null;
    final tag = release['tag_name'] as String? ?? '';
    if (tag.isEmpty) return null;
    final version = parseVersion(tag).join('.');
    if (compareVersions(version, kAppVersion) <= 0) return null;
    String url = '';
    int size = 0;
    final assets = release['assets'];
    if (assets is List) {
      for (final entry in assets) {
        if (entry is! Map) continue;
        if (entry['name'] == asset) {
          url = entry['browser_download_url'] as String? ?? '';
          size = (entry['size'] as num?)?.toInt() ?? 0;
        }
      }
    }
    if (url.isEmpty) return null;
    return UpdateInfo(
      tag: tag,
      version: version,
      assetName: asset,
      downloadUrl: url,
      size: size,
    );
  }

  // ── Network ──

  /// Look for a newer release on GitHub.
  ///
  /// Throws on network/API errors so the caller can decide whether to show
  /// anything. Returns null when the app is up to date.
  static Future<UpdateInfo?> check({bool force = false}) async {
    if (!force) {
      final last = await Settings.getLastUpdateCheck();
      final cached = await _cachedInfo();
      if (last != null && DateTime.now().difference(last) < checkInterval) {
        return cached;
      }
    }

    final headers = <String, String>{'Accept': 'application/vnd.github+json'};
    final token = await Settings.getGithubToken();
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    final etag = await Settings.getUpdateEtag();
    if (etag.isNotEmpty) headers['If-None-Match'] = etag;

    final uri = Uri.parse('$api/repos/$repo/releases/latest');
    final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 304) {
      // Not modified - cached result stays valid and the quota is not used.
      await Settings.setLastUpdateCheck(DateTime.now());
      final cached = await _cachedInfo();
      latest = cached;
      return cached;
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub API returned HTTP ${resp.statusCode}');
    }
    final newEtag = resp.headers['etag'];
    if (newEtag != null && newEtag.isNotEmpty) {
      await Settings.setUpdateEtag(newEtag);
    }
    await Settings.setLastUpdateCheck(DateTime.now());

    final release = jsonDecode(resp.body);
    if (release is! Map<String, dynamic>) return null;
    var info = updateFromRelease(release);
    if (info != null) {
      // Grab the published checksum once - it is verified before the install
      // and handed to the native installer as well.
      final sum = await fetchChecksum(info);
      if (sum != null) info = info.copyWith(sha256: sum);
    }
    await Settings.setCachedUpdate(info?.toJson());
    latest = info;
    return info;
  }

  /// Cached update descriptor as an UpdateInfo (null when up to date).
  static Future<UpdateInfo?> _cachedInfo() async {
    final cached = await Settings.getCachedUpdate();
    if (cached == null) return null;
    try {
      return UpdateInfo.fromJson(cached);
    } catch (_) {
      return null;
    }
  }

  /// Download the release APK into the app cache and verify its SHA-256 when
  /// the release publishes a checksum file.
  static Future<File> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    // The app's private files directory - not the cache directory, which the
    // system is free to purge at any time (that is what broke the install).
    final dir = await getApplicationSupportDirectory();
    final updates = Directory('${dir.path}/updates');
    if (!await updates.exists()) await updates.create(recursive: true);
    final target = File('${updates.path}/${info.assetName}');
    if (await target.exists()) await target.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? info.size;
      final sink = target.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      // A truncated download must never reach the installer.
      final expected = response.contentLength;
      if (expected != null && expected > 0 && received != expected) {
        await target.delete();
        throw Exception('Download was incomplete ($received of $expected bytes)');
      }
    } finally {
      client.close();
    }

    final expected = info.sha256.isNotEmpty ? info.sha256 : await fetchChecksum(info);
    if (expected != null && expected.isNotEmpty) {
      final actual = await sha256File(target);
      if (actual.toLowerCase() != expected.toLowerCase()) {
        await target.delete();
        throw Exception('Checksum mismatch - the download was corrupted');
      }
    }
    return target;
  }

  /// Fetch the published checksum for the release asset (null when absent).
  static Future<String?> fetchChecksum(UpdateInfo info) async {
    try {
      final resp = await http
          .get(Uri.parse('${info.downloadUrl}.sha256'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      return extractChecksum(resp.body, info.assetName);
    } catch (_) {
      return null;
    }
  }

  /// SHA-256 of a file, streamed so a 40 MB APK does not need to fit in RAM.
  static Future<String> sha256File(File file) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.digest.toString();
  }

  /// Opens this app's system settings page (for the "install unknown apps"
  /// permission the system asks for).
  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod('openAppSettings');
    } catch (_) {
    }
  }

  /// Hand the downloaded APK to the Android package installer.
  ///
  /// The native side re-checks the checksum of the very file it installs and
  /// refuses to commit a session that did not receive every byte.
  static Future<void> install(File apk, {String expectedSha256 = ''}) async {
    await _ch.invokeMethod('installUpdateApk', {
      'path': apk.path,
      'sha256': expectedSha256,
    });
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}

  Digest get digest => _digest ?? sha256.convert(const <int>[]);
}
