import 'dart:io';

import 'package:applix/services/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

late String _dir;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _dir = Directory.systemTemp.createTempSync('applix_project_test').path;
    ProjectStore.rootOverride = _dir;
  });

  tearDown(() {
    ProjectStore.rootOverride = null;
  });

  group('project store', () {
    test('stores the entry file and the extra files', () async {
      await ProjectStore.writeProject(
        appId: 'app1',
        packageName: 'applix.demo1',
        indexHtml: '<html><body>hi</body></html>',
        files: {'style.css': 'body{color:red}', 'script.js': 'console.log(1)'},
      );
      final files = await ProjectStore.readProject(
        appId: 'app1',
        packageName: 'applix.demo1',
      );
      expect(files['style.css'], 'body{color:red}');
      expect(files['script.js'], 'console.log(1)');
      final index = await ProjectStore.readIndexHtml(
        appId: 'app1',
        packageName: 'applix.demo1',
      );
      expect(index, contains('<body>hi</body>'));
    });

    test('uses the package folder once the package name is known', () async {
      await ProjectStore.writeProject(
        appId: 'app1',
        indexHtml: '<html></html>',
      );
      final before = await ProjectStore.projectDir(appId: 'app1');
      expect(before.path, contains('/projects/app1'));

      await ProjectStore.migrateToPackage(appId: 'app1', packageName: 'applix.demo1');
      final after = await ProjectStore.projectDir(appId: 'app1', packageName: 'applix.demo1');
      expect(after.path, contains('/apps/applix.demo1'));
      final index = await ProjectStore.readIndexHtml(
        appId: 'app1',
        packageName: 'applix.demo1',
      );
      expect(index, '<html></html>');
    });

    test('an app without a project folder still reads as empty (old apps)', () async {
      final files = await ProjectStore.readProject(appId: 'legacy', packageName: 'applix.legacy');
      expect(files, isEmpty);
      final index = await ProjectStore.readIndexHtml(appId: 'legacy', packageName: 'applix.legacy');
      expect(index, isNull);
      final paths = await ProjectStore.paths(appId: 'legacy', packageName: 'applix.legacy');
      expect(paths, isEmpty);
    });

    test('the build gets the extra files but not the entry file', () async {
      await ProjectStore.writeProject(
        appId: 'app1',
        packageName: 'applix.demo1',
        indexHtml: '<html></html>',
        files: {'style.css': 'a{}'},
      );
      final paths = await ProjectStore.paths(appId: 'app1', packageName: 'applix.demo1');
      expect(paths.keys.toList(), ['style.css']);
    });

    test('file names cannot escape the project folder', () async {
      await ProjectStore.addFile(
        appId: 'app1',
        packageName: 'applix.demo1',
        name: '../evil.js',
        content: 'x',
      );
      final files = await ProjectStore.listFiles(appId: 'app1', packageName: 'applix.demo1');
      expect(files.length, 1);
      expect((files.first['name'] as String).contains('/'), isFalse);
    });

    test('nested paths are stored and returned for the build', () async {
      await ProjectStore.writeProject(
        appId: 'app1',
        packageName: 'applix.demo1',
        indexHtml: '<html></html>',
        files: {'src/app.js': 'console.log(1)', 'src/lib/util.js': 'export {}'},
      );
      final files = await ProjectStore.readProject(
          appId: 'app1', packageName: 'applix.demo1');
      expect(files['src/app.js'], 'console.log(1)');
      expect(files['src/lib/util.js'], 'export {}');
      final paths = await ProjectStore.paths(
          appId: 'app1', packageName: 'applix.demo1');
      expect(paths.keys, containsAll(['src/app.js', 'src/lib/util.js']));
      expect(paths.keys, isNot(contains('index.html')));
      expect(File(paths['src/app.js']!).existsSync(), isTrue);
    });

    test('nested paths cannot escape the project folder either', () async {
      await ProjectStore.writeProject(
        appId: 'app1',
        packageName: 'applix.demo1',
        indexHtml: '<html></html>',
        files: {'src/../../evil.js': 'x', '/abs.js': 'x', 'src/ok.js': 'y'},
      );
      final files = await ProjectStore.listFiles(
          appId: 'app1', packageName: 'applix.demo1');
      final names = files.map((f) => f['name']).toList();
      expect(names, contains('src/ok.js'));
      expect(names, isNot(contains('evil.js')));
      expect(names.any((n) => (n as String).contains('..')), isFalse);
    });

    test('a file is deleted by its nested name', () async {
      await ProjectStore.writeProject(
        appId: 'app1',
        packageName: 'applix.demo1',
        indexHtml: '<html></html>',
        files: {'src/app.js': '1'},
      );
      await ProjectStore.removeFile(
          appId: 'app1', packageName: 'applix.demo1', name: 'src/app.js');
      final files = await ProjectStore.readProject(
          appId: 'app1', packageName: 'applix.demo1');
      expect(files.containsKey('src/app.js'), isFalse);
      expect(files.containsKey('index.html'), isTrue);
    });

    test('the project manifest is written and read back', () async {
      await ProjectStore.writeConfig(
        appId: 'app1',
        packageName: 'applix.demo1',
        config: {'name': 'Demo', 'entry': 'index.html'},
      );
      final config = await ProjectStore.readConfig(appId: 'app1', packageName: 'applix.demo1');
      expect(config!['name'], 'Demo');
    });
  });

  group('preview inlining', () {
    test('a stylesheet link becomes an inline style block', () {
      final out = ProjectStore.inlineProjectFiles(
        '<html><head><link rel="stylesheet" href="style.css"></head><body>x</body></html>',
        {'style.css': 'body{color:red}'},
      );
      expect(out, contains('<style>'));
      expect(out, contains('body{color:red}'));
      expect(out, isNot(contains('href="style.css"')));
    });

    test('a script tag becomes an inline script', () {
      final out = ProjectStore.inlineProjectFiles(
        '<html><head><script src="script.js"></script></head><body>x</body></html>',
        {'script.js': 'console.log("hi")'},
      );
      expect(out, contains('console.log("hi")'));
      expect(out, isNot(contains('src="script.js"')));
    });

    test('a module script keeps module semantics when inlined', () {
      final out = ProjectStore.inlineProjectFiles(
        '<script type="module" src="src/app.js"></script>',
        {'src/app.js': 'import "./x.js";'},
      );
      expect(out, contains('<script type="module">'));
      expect(out, contains('import "./x.js"'));
      expect(out, isNot(contains('src="src/app.js"')));
    });

    test('dollar signs in the file are kept as they are', () {
      final out = ProjectStore.inlineProjectFiles(
        '<script src="script.js"></script>',
        {'script.js': r'const a = "${1 + 1}";'},
      );
      expect(out, contains(r'${1 + 1}'));
    });

    test('html without project files is untouched', () {
      const html = '<html><head><link href="style.css"></head></html>';
      expect(ProjectStore.inlineProjectFiles(html, {}), html);
    });
  });
}
