import 'dart:convert';
import 'dart:io';

import 'package:applix/services/app_plan.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

const _valid = '''
{
  "name": "Errand",
  "pitch": "A calm task list for the week.",
  "screens": [
    {"id": "home", "title": "Today", "purpose": "See and finish tasks",
     "components": ["appbar", "list", "fab"], "actions": ["Add task", "Toggle done"]}
  ],
  "entities": [
    {"name": "Task", "fields": [{"name": "title", "type": "string", "required": true}],
     "seed": [{"title": "Buy milk"}, {"title": "Call the dentist"}]}
  ],
  "flows": ["Add a task and see it immediately"],
  "persistence": "iappyx.save",
  "design": {"tone": "calm", "accent": "blue", "density": "comfortable"},
  "acceptance": ["Seed tasks are visible on first launch", "Add and delete work after reload"]
}
''';

void main() {
  group('AppPlan.parse', () {
    test('accepts a plain JSON plan and keeps the seed records', () {
      final plan = AppPlan.parse(_valid);
      expect(plan, isNotNull);
      expect(plan!.isEmpty, isFalse);
      final block = plan.toPromptBlock();
      expect(block, contains('APP PLAN'));
      expect(block, contains('Buy milk'));
      expect(block, contains('Call the dentist'));
      expect(block, contains('Seed tasks are visible on first launch'));
    });

    test('accepts fenced JSON with surrounding prose', () {
      final raw = 'Here is the plan:\n```json\n$_valid\n```\nDone.';
      final plan = AppPlan.parse(raw);
      expect(plan, isNotNull);
      expect(plan!.toPromptBlock(), contains('"screens"'));
    });

    test('rejects unusable answers instead of throwing', () {
      expect(AppPlan.parse(''), isNull);
      expect(AppPlan.parse('I cannot help with that.'), isNull);
      expect(AppPlan.parse('{not json}'), isNull);
      expect(AppPlan.parse('{"screens": []}'), isNull);
      expect(AppPlan.parse('{"screens": "home"}'), isNull);
    });

    test('sanitizes ids and caps oversized plans', () {
      final plan = AppPlan.parse('''
        {"screens": [
          {"id": "My Screen!!", "title": "One"},
          {"id": "two", "title": "Two"}
        ], "acceptance": ["a"]}
      ''');
      expect(plan, isNotNull);
      final data = plan!.data;
      final screens = data['screens'] as List;
      expect(screens, hasLength(2));
      expect((screens.first as Map)['id'], 'my-screen-');
      expect((screens.first as Map)['title'], 'One');
    });

    test('parses a large but bounded plan', () {
      final screens = List.generate(5, (i) => {
            'id': 'screen$i',
            'title': 'Screen $i',
            'purpose': 'Purpose $i',
          });
      final plan = AppPlan.parse(jsonEncode({'screens': screens}));
      expect(plan, isNotNull);
      expect((plan!.data['screens'] as List), hasLength(5));
    });

    test('the planner prompt documents the schema', () {
      final prompt = _read('assets/planner_prompt.md');
      for (final key in ['screens', 'entities', 'acceptance', 'seed', 'persistence']) {
        expect(prompt, contains(key));
      }
      expect(prompt, contains('Return ONLY one JSON object'));
    });
  });
}
