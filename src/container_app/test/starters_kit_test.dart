import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('starter apps use the UI kit contract', () {
    final starters = Directory('assets/starters')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.html'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    test('all eight starters are present', () {
      expect(starters, hasLength(8));
    });

    for (final file in starters) {
      final name = file.uri.pathSegments.last;
      final html = file.readAsStringSync();

      test('$name is themed with kit tokens and a modern font', () {
        expect(html, contains('viewport-fit=cover'), reason: name);
        expect(html, contains('system-ui'), reason: name);
        expect(html, isNot(contains('-apple-system')), reason: name);
        expect(html, contains('var(--ax-'), reason: name);
        expect(html, isNot(contains('#0d0d1a')), reason: name);
        expect(html, isNot(contains('#0f3460')), reason: name);
      });
    }

    test('todo and notes ship realistic seed data and kit components', () {
      final todo = File('assets/starters/todo.html').readAsStringSync();
      final notes = File('assets/starters/notes.html').readAsStringSync();
      expect(todo, contains('SEED'));
      expect(todo, contains('ax-check'));
      expect(todo, contains('ax-empty'));
      expect(todo, contains('iappyx.save'));
      expect(notes, contains('SEED'));
      expect(notes, contains('ax-row'));
      expect(notes, contains('ax-search'));
      expect(notes, contains('iappyx.save'));
    });
  });
}
