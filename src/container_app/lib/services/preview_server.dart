/// Real loopback HTTP origin for the in-app preview WebView.
///
/// Loading the app with `loadHtmlString` and a fake `https://*.localhost/` base
/// URL made relative requests (kit scripts, styles, icons) go to the network,
/// which fails with `net::ERR_CONNECTION_REFUSED` on devices and left the
/// preview blank. Serving the same document from 127.0.0.1 gives the page a
/// real, offline origin: relative files resolve, modules load and storage works
/// without touching the internet.
library;

import 'dart:convert';
import 'dart:io';

class PreviewServer {
  PreviewServer._(this._server) {
    _server.listen(_onRequest, onError: (_) {});
  }

  final HttpServer _server;
  String _html = '';
  Map<String, String> _files = const {};

  int get port => _server.port;

  /// Entry point loaded by the WebView.
  Uri get uri => Uri.parse('http://127.0.0.1:$port/index.html');

  static Future<PreviewServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return PreviewServer._(server);
  }

  /// Publishes the document and its project files for the next request.
  void update(String html, Map<String, String> files) {
    _html = html;
    _files = Map<String, String>.unmodifiable(files);
  }

  void _onRequest(HttpRequest request) {
    final path = _normalize(request.uri.path);
    final response = request.response
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      if (path.isEmpty || path == 'index.html') {
        _write(response, _html, 'text/html; charset=utf-8');
        return;
      }
      final body = _files[path];
      if (body != null) {
        _write(response, body, _contentTypeFor(path));
        return;
      }
      response.statusCode = HttpStatus.notFound;
      _write(response, 'Not found: /$path', 'text/plain; charset=utf-8');
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      response.close().catchError((_) {});
    }
  }

  void _write(HttpResponse response, String body, String contentType) {
    response.headers.contentType = ContentType.parse(contentType);
    final bytes = utf8.encode(body);
    response.headers.contentLength = bytes.length;
    response.add(bytes);
  }

  String _normalize(String raw) {
    var path = raw;
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path;
  }

  String _contentTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'html':
      case 'htm':
        return 'text/html; charset=utf-8';
      case 'css':
        return 'text/css; charset=utf-8';
      case 'js':
      case 'mjs':
        return 'text/javascript; charset=utf-8';
      case 'json':
        return 'application/json; charset=utf-8';
      case 'svg':
        return 'image/svg+xml';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'ico':
        return 'image/x-icon';
      case 'woff2':
        return 'font/woff2';
      default:
        return 'text/plain; charset=utf-8';
    }
  }

  Future<void> dispose() async {
    try {
      await _server.close(force: true);
    } catch (_) {}
  }
}
