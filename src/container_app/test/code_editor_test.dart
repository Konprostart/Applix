import 'package:applix/screens/code_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('code edits', () {
    test('inserts a snippet at the cursor', () {
      final edit = CodeEdits.insert('hello world', 5, 5, ' there');
      expect(edit.text, 'hello there world');
      expect(edit.offset, 11);
    });

    test('replaces the selection with the snippet', () {
      final edit = CodeEdits.insert('hello world', 0, 5, 'bye');
      expect(edit.text, 'bye world');
      expect(edit.offset, 3);
    });

    test('wraps a selection in a pair', () {
      final edit = CodeEdits.wrap('foo', 0, 3, '{', '}');
      expect(edit.text, '{foo}');
      expect(edit.offset, 4);
    });

    test('inserts an empty pair and keeps the cursor between them', () {
      final edit = CodeEdits.wrap('ab', 1, 1, '(', ')');
      expect(edit.text, 'a()b');
      expect(edit.offset, 2);
    });

    test('handles an empty document', () {
      final edit = CodeEdits.insert('', 0, 0, 'x');
      expect(edit.text, 'x');
      expect(edit.offset, 1);
    });
  });
}
