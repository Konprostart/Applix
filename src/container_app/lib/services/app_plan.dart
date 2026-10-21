// MIT License
//
// Copyright (c) 2026 iappyx
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// A compact, validated product plan produced before app generation.
///
/// The planner call is best-effort: when the model returns something unusable
/// [AppPlan.parse] returns null and generation continues without a plan.

import 'dart:convert';

class AppPlan {
  static const maxChars = 16000;
  static const maxScreens = 8;
  static const maxEntities = 8;

  final Map<String, dynamic> data;

  const AppPlan._(this.data);

  /// Parses a planner response. Accepts fenced JSON and surrounding prose.
  static AppPlan? parse(String raw) {
    if (raw.trim().isEmpty) return null;
    final json = _extractJson(raw);
    if (json == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = <String, dynamic>{};
    decoded.forEach((key, value) => map['$key'] = value);

    final screens = _cleanScreens(map['screens']);
    if (screens.isEmpty) return null;
    final entities = _cleanEntities(map['entities']);
    final acceptance = _cleanStrings(map['acceptance'], max: 8, itemMax: 220);

    final clean = <String, dynamic>{
      'name': _str(map['name'], max: 80),
      'pitch': _str(map['pitch'], max: 300),
      'screens': screens,
      'entities': entities,
      'flows': _cleanStrings(map['flows'], max: 10, itemMax: 220),
      'persistence': _str(map['persistence'], max: 40),
      'design': map['design'] is Map ? _cleanDesign(map['design']) : <String, dynamic>{},
      'acceptance': acceptance,
    };
    final encoded = jsonEncode(clean);
    if (encoded.length > maxChars) return null;
    return AppPlan._(clean);
  }

  bool get isEmpty => (data['screens'] as List?)?.isEmpty ?? true;

  /// The block appended to the generation request.
  String toPromptBlock() {
    const encoder = JsonEncoder.withIndent(' ');
    return '''APP PLAN (binding spec - implement every screen, entity, flow and acceptance item):
${encoder.convert(data)}

Use the plan's seed records as the app's first-run data. If the plan is silent on
something, choose the most useful concrete behaviour. Do not output the plan.''';
  }

  static String? _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    var candidate = raw.substring(start, end + 1).trim();
    if (candidate.length > maxChars * 2) return null;
    return candidate;
  }

  static String _str(Object? value, {int max = 200}) {
    final text = value is String ? value.trim() : (value == null ? '' : '$value');
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length <= max ? single : single.substring(0, max);
  }

  static List<String> _cleanStrings(Object? value, {required int max, int itemMax = 200}) {
    if (value is! List) return const [];
    final out = <String>[];
    for (final item in value) {
      final text = _str(item, max: itemMax);
      if (text.isNotEmpty) out.add(text);
      if (out.length >= max) break;
    }
    return out;
  }

  static List<Map<String, dynamic>> _cleanScreens(Object? value) {
    if (value is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is! Map) continue;
      final title = _str(item['title'], max: 60);
      var id = _str(item['id'], max: 40).toLowerCase();
      id = id.replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
      if (id.isEmpty) id = 'screen-${out.length + 1}';
      if (title.isEmpty && out.isNotEmpty) continue;
      out.add(<String, dynamic>{
        'id': id,
        'title': title.isEmpty ? 'Home' : title,
        'purpose': _str(item['purpose'], max: 240),
        'components': _cleanStrings(item['components'], max: 10, itemMax: 30),
        'actions': _cleanStrings(item['actions'], max: 10, itemMax: 80),
      });
      if (out.length >= maxScreens) break;
    }
    return out;
  }

  static List<Map<String, dynamic>> _cleanEntities(Object? value) {
    if (value is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is! Map) continue;
      final name = _str(item['name'], max: 50);
      if (name.isEmpty) continue;
      final fields = <Map<String, dynamic>>[];
      final rawFields = item['fields'];
      if (rawFields is List) {
        for (final field in rawFields) {
          if (field is! Map) continue;
          final fieldName = _str(field['name'], max: 40);
          if (fieldName.isEmpty) continue;
          fields.add(<String, dynamic>{
            'name': fieldName,
            'type': _str(field['type'], max: 20),
            'required': field['required'] == true,
          });
          if (fields.length >= 20) break;
        }
      }
      final seed = <Map<String, dynamic>>[];
      final rawSeed = item['seed'];
      if (rawSeed is List) {
        for (final row in rawSeed) {
          if (row is! Map) continue;
          final cleanRow = <String, dynamic>{};
          row.forEach((key, value) {
            final k = _str(key, max: 40);
            if (k.isEmpty) return;
            if (value is num || value is bool) {
              cleanRow[k] = value;
            } else {
              cleanRow[k] = _str(value, max: 160);
            }
          });
          if (cleanRow.isNotEmpty) seed.add(cleanRow);
          if (seed.length >= 8) break;
        }
      }
      out.add(<String, dynamic>{
        'name': name,
        'fields': fields,
        'seed': seed,
      });
      if (out.length >= maxEntities) break;
    }
    return out;
  }

  static Map<String, dynamic> _cleanDesign(Object? value) {
    if (value is! Map) return const {};
    return <String, dynamic>{
      'tone': _str(value['tone'], max: 80),
      'accent': _str(value['accent'], max: 40),
      'density': _str(value['density'], max: 20),
    };
  }
}
