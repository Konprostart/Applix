import 'dart:convert';
import 'dart:io';

import 'package:applix/services/preview_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PreviewServer', () {
    late PreviewServer server;
    late HttpClient client;

    setUp(() async {
      server = await PreviewServer.start();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.dispose();
    });

    Future<HttpClientResponse> get(String path) async {
      final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}$path'));
      return request.close();
    }

    test('uses a loopback origin with an ephemeral port', () {
      expect(server.uri.scheme, 'http');
      expect(server.uri.host, '127.0.0.1');
      expect(server.port, greaterThan(0));
    });

    test('serves the preview document as utf-8 html', () async {
      server.update('<html><body><h1>Kalendar</h1></body></html>', const {});
      final response = await get('/index.html');
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(body, contains('Kalendar'));
    });

    test('serves the root path with the same document', () async {
      server.update('<html><body>root</body></html>', const {});
      final response = await get('/');
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200);
      expect(body, contains('root'));
    });

    test('serves project files with the right content type', () async {
      server.update('<html></html>', const {
        'app.js': 'console.log("hi");',
        'styles/app.css': 'body { color: red; }',
      });
      final js = await get('/app.js');
      expect(js.statusCode, 200);
      expect(js.headers.contentType?.mimeType, 'text/javascript');
      expect(await js.transform(utf8.decoder).join(), contains('console'));

      final css = await get('/styles/app.css');
      expect(css.statusCode, 200);
      expect(css.headers.contentType?.mimeType, 'text/css');
    });

    test('picks up the latest document without restarting', () async {
      server.update('<html><body>prva</body></html>', const {});
      await (await get('/index.html')).drain<void>();
      server.update('<html><body>druga</body></html>', const {});
      final body = await (await get('/index.html')).transform(utf8.decoder).join();
      expect(body, contains('druga'));
    });

    test('returns 404 for unknown files', () async {
      server.update('<html></html>', const {});
      final response = await get('/nema.js');
      expect(response.statusCode, 404);
      await response.drain<void>();
    });
  });
}
