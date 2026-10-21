/// Best-effort repair of the malformed JSON models sometimes emit.
///
/// Only delimiters and raw control characters are touched. Smart quotes that
/// wrap a value are turned into `"`, trailing commas before `}`/`]` are
/// dropped, and raw line breaks or tabs inside a string are escaped: models
/// emit them often, and a raw one is invalid JSON. Everything else inside a
/// JSON string - CSS `1fr,`, a query with `", "`, user copy with curly quotes -
/// is left byte-for-byte intact. That is why this cannot be a global replace.
library;

class JsonRepair {
  static String simplify(String text) {
    final out = StringBuffer();
    var inString = false;
    var escaped = false;
    var closing = 0x22; // "
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          // The backslash is already written. A raw control character after
          // it is a line break the model meant as an escape: write the escape
          // letter (n, r, t, uXXXX) so the pair stays a valid JSON escape.
          if (c < 0x20) {
            out.write(_controlEscape(c).substring(1));
          } else {
            out.writeCharCode(c);
          }
          escaped = false;
        } else if (c == 0x5C) {
          out.writeCharCode(c);
          escaped = true;
        } else if (c == closing || (closing == 0x201D && c == 0x22)) {
          out.write('"');
          inString = false;
        } else if (c < 0x20) {
          out.write(_controlEscape(c));
        } else {
          out.writeCharCode(c);
        }
        continue;
      }
      if (c == 0x22) {
        out.write('"');
        inString = true;
        closing = 0x22;
      } else if (c == 0x201C || c == 0x201D) {
        out.write('"');
        inString = true;
        closing = 0x201D;
      } else if (c == 0x2C) {
        var j = i + 1;
        while (j < text.length) {
          final next = text.codeUnitAt(j);
          if (next == 0x20 || next == 0x09 || next == 0x0A || next == 0x0D) {
            j++;
          } else {
            break;
          }
        }
        final next = j < text.length ? text.codeUnitAt(j) : -1;
        if (next != 0x7D && next != 0x5D) out.writeCharCode(c);
      } else {
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }

  /// The JSON escape for a control character (U+0000 to U+001F).
  static String _controlEscape(int c) {
    switch (c) {
      case 0x0A:
        return r'\n';
      case 0x0D:
        return r'\r';
      case 0x09:
        return r'\t';
      default:
        return '\\u${c.toRadixString(16).padLeft(4, '0')}';
    }
  }
}
