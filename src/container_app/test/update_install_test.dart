import 'package:applix/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('update service helpers', () {
    test('the version comparison ignores the build suffix', () {
      expect(UpdateService.compareVersions('0.1.7', '0.1.7+8'), 0);
      expect(UpdateService.compareVersions('0.1.8', '0.1.7+8'), greaterThan(0));
      expect(UpdateService.parseVersion('0.1.7+8'), [0, 1, 7]);
    });

    test('the container asset is picked from a release payload', () {
      final release = {
        'tag_name': 'v9.9.9',
        'assets': [
          {'name': 'Applix-9.9.9-shell-web.apk'},
          {'name': 'Applix-9.9.9-container.apk'},
        ],
      };
      expect(UpdateService.pickContainerAsset(release), 'Applix-9.9.9-container.apk');
    });

    test('the checksum is read from a sha256 file', () {
      const content = 'abc123  Applix-0.1.3-container.apk\n';
      expect(
        UpdateService.extractChecksum(content, 'Applix-0.1.3-container.apk'),
        'abc123',
      );
      expect(UpdateService.extractChecksum(content, 'other.apk'), isNull);
    });
  });
}
