import 'package:applix/services/update_service.dart';
import 'package:applix/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('version parsing', () {
    test('parses tagged and plain versions', () {
      expect(UpdateService.parseVersion('v0.1.3'), [0, 1, 3]);
      expect(UpdateService.parseVersion('0.1.3'), [0, 1, 3]);
      expect(UpdateService.parseVersion('1.2'), [1, 2, 0]);
      expect(UpdateService.parseVersion('v10.0.1'), [10, 0, 1]);
    });

    test('compares versions numerically, not lexically', () {
      expect(UpdateService.compareVersions('0.1.10', '0.1.9'), greaterThan(0));
      expect(UpdateService.compareVersions('0.2.0', '0.1.99'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(UpdateService.compareVersions('0.1.3', '0.1.3'), 0);
      expect(UpdateService.compareVersions('v0.1.2', '0.1.3'), lessThan(0));
    });
  });

  group('release payload', () {
    Map<String, dynamic> release({String tag = 'v9.9.9'}) => {
          'tag_name': tag,
          'assets': [
            {'name': 'Applix-9.9.9-shell-full.apk', 'browser_download_url': 'https://x/full.apk', 'size': 10},
            {'name': 'Applix-9.9.9-container.apk', 'browser_download_url': 'https://x/container.apk', 'size': 42},
            {'name': 'Applix-9.9.9-shell-web.apk', 'browser_download_url': 'https://x/web.apk', 'size': 5},
          ],
        };

    test('picks the container APK', () {
      expect(UpdateService.pickContainerAsset(release()), 'Applix-9.9.9-container.apk');
    });

    test('returns null when no container asset exists', () {
      final payload = release();
      (payload['assets'] as List).removeWhere((e) => (e as Map)['name'].toString().contains('container'));
      expect(UpdateService.pickContainerAsset(payload), isNull);
      expect(UpdateService.updateFromRelease(payload), isNull);
    });

    test('builds an update for a newer release', () {
      final info = UpdateService.updateFromRelease(release());
      expect(info, isNotNull);
      expect(info!.version, '9.9.9');
      expect(info.assetName, 'Applix-9.9.9-container.apk');
      expect(info.downloadUrl, 'https://x/container.apk');
      expect(info.size, 42);
    });

    test('ignores a release that is not newer than the running version', () {
      expect(UpdateService.updateFromRelease(release(tag: 'v$kAppVersion')), isNull);
      expect(UpdateService.updateFromRelease(release(tag: 'v0.0.1')), isNull);
    });
  });

  group('checksum file', () {
    test('extracts the hash for the asset', () {
      const content = 'abc123  Applix-0.1.3-container.apk\ndef456  Applix-0.1.3-shell-web.apk\n';
      expect(UpdateService.extractChecksum(content, 'Applix-0.1.3-container.apk'), 'abc123');
      expect(UpdateService.extractChecksum(content, 'Applix-0.1.3-shell-web.apk'), 'def456');
    });

    test('handles the ./ prefix and returns null for unknown assets', () {
      const content = 'abc123  ./Applix-0.1.3-container.apk\n';
      expect(UpdateService.extractChecksum(content, 'Applix-0.1.3-container.apk'), 'abc123');
      expect(UpdateService.extractChecksum(content, 'other.apk'), isNull);
      expect(UpdateService.extractChecksum('', 'other.apk'), isNull);
    });
  });

  group('update info', () {
    test('survives a json round trip', () {
      const info = UpdateInfo(
        tag: 'v0.1.3',
        version: '0.1.3',
        assetName: 'Applix-0.1.3-container.apk',
        downloadUrl: 'https://x/container.apk',
        size: 42,
      );
      final back = UpdateInfo.fromJson(info.toJson());
      expect(back.tag, info.tag);
      expect(back.version, info.version);
      expect(back.assetName, info.assetName);
      expect(back.downloadUrl, info.downloadUrl);
      expect(back.size, info.size);
    });
  });
}
