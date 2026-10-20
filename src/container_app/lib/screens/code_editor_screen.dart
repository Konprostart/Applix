// MIT License — Copyright (c) 2026 iappyx

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/project_store.dart';

/// The result of a text change (the new text and the new cursor offset).
class TextEdit {
  final String text;
  final int offset;
  const TextEdit(this.text, this.offset);
}

/// Pure text transformations of the editor (covered by unit tests).
class CodeEdits {
  /// Inserts [snippet] between [start] and [end].
  static TextEdit insert(String text, int start, int end, String snippet) {
    final before = text.substring(0, start);
    final after = text.substring(end);
    return TextEdit('$before$snippet$after', start + snippet.length);
  }

  /// Wraps the selection between [start] and [end] with [open] and [close].
  /// With an empty selection the pair is inserted and the cursor lands between them.
  static TextEdit wrap(String text, int start, int end, String open, String close) {
    final before = text.substring(0, start);
    final selected = text.substring(start, end);
    final after = text.substring(end);
    return TextEdit(
      '$before$open$selected$close$after',
      start + open.length + selected.length,
    );
  }
}

/// A small, dependency-free code editor for the files of an app project.
///
/// It is deliberately built from plain Flutter widgets (no heavy editor
/// package): a monospace text field, a line number gutter that follows the
/// scroll, mobile friendly insert buttons and a file tab bar. That keeps the
/// app fast and stable on mid-range phones.
class CodeEditorScreen extends StatefulWidget {
  /// The app the files belong to.
  final String appId;
  final String? packageName;
  /// The file that is opened first.
  final String? initialFile;
  /// Called after a file was saved (the app reloads its preview with it).
  final void Function(String fileName, String content)? onSaved;

  const CodeEditorScreen({
    super.key,
    required this.appId,
    this.packageName,
    this.initialFile,
    this.onSaved,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  static const _fontSize = 12.0;
  static const _lineHeight = 1.5;
  static const _linePx = _fontSize * _lineHeight;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _gutter = ScrollController();

  String _active = 'index.html';
  final Map<String, String> _buffers = {}; // file -> content
  final Set<String> _dirty = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncGutter);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncGutter);
    _scroll.dispose();
    _gutter.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final project = await ProjectStore.readProject(
      appId: widget.appId,
      packageName: widget.packageName,
    );
    final index = await ProjectStore.readIndexHtml(
      appId: widget.appId,
      packageName: widget.packageName,
    );
    if (!mounted) return;
    setState(() {
      _buffers.clear();
      if (index != null) _buffers['index.html'] = index;
      project.forEach((name, content) => _buffers[name] = content);
      final wanted = widget.initialFile;
      _active = (wanted != null && _buffers.containsKey(wanted))
          ? wanted
          : (_buffers.containsKey('index.html') ? 'index.html' : (_buffers.keys.isEmpty ? 'index.html' : _buffers.keys.first));
      _controller.text = _buffers[_active] ?? '';
      _loading = false;
    });
  }

  void _syncGutter() {
    if (!_gutter.hasClients || !_scroll.hasClients) return;
    final max = _gutter.position.maxScrollExtent;
    final offset = _scroll.offset.clamp(0.0, max);
    if ((_gutter.offset - offset).abs() > 0.5) _gutter.jumpTo(offset);
  }

  void _selectFile(String name) {
    if (_active == name) return;
    // Remember what was typed before switching.
    _buffers[_active] = _controller.text;
    setState(() {
      _active = name;
      _controller.text = _buffers[name] ?? '';
      _controller.selection = TextSelection.collapsed(offset: 0);
    });
  }

  void _onChanged(String value) {
    _buffers[_active] = value;
    if (!_dirty.contains(_active)) {
      setState(() => _dirty.add(_active));
    } else {
      setState(() {});
    }
  }

  /// Inserts text at the cursor (used by the mobile toolbar).
  void _insert(String text) {
    final value = _controller.value;
    final start = value.selection.start < 0 ? value.text.length : value.selection.start;
    final end = value.selection.end < 0 ? value.text.length : value.selection.end;
    final edit = CodeEdits.insert(value.text, start, end, text);
    _controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.offset),
    );
    _onChanged(edit.text);
  }

  /// Wraps the selection with a pair of characters.
  void _wrap(String open, String close) {
    final value = _controller.value;
    final start = value.selection.start < 0 ? value.text.length : value.selection.start;
    final end = value.selection.end < 0 ? value.text.length : value.selection.end;
    final edit = CodeEdits.wrap(value.text, start, end, open, close);
    _controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.offset),
    );
    _onChanged(edit.text);
  }

  Future<void> _save() async {
    final content = _controller.text;
    try {
      if (_active == 'index.html') {
        await ProjectStore.writeProject(
          appId: widget.appId,
          packageName: widget.packageName,
          indexHtml: content,
        );
      } else {
        await ProjectStore.addFile(
          appId: widget.appId,
          packageName: widget.packageName,
          name: _active,
          content: content,
        );
      }
      if (!mounted) return;
      setState(() => _dirty.remove(_active));
      widget.onSaved?.call(_active, content);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$_active saved'),
        backgroundColor: const Color(0xFF1A1A2E),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save: $e'),
        backgroundColor: const Color(0xFF1A1A2E),
      ));
    }
  }

  /// The line and column of the cursor.
  String get _cursorInfo {
    final sel = _controller.selection;
    final offset = sel.baseOffset < 0 ? _controller.text.length : sel.baseOffset;
    final text = _controller.text.substring(0, offset);
    final lines = text.split('\n');
    final line = lines.length;
    final col = lines.isEmpty ? 1 : lines.last.length + 1;
    return 'Ln $line, Col $col';
  }

  @override
  Widget build(BuildContext context) {
    final names = _buffers.keys.toList()..sort((a, b) {
        if (a == 'index.html') return -1;
        if (b == 'index.html') return 1;
        return a.compareTo(b);
      });
    final lineCount = '\n'.allMatches(_controller.text).length + 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text('Edit Code', style: TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _dirty.isEmpty ? null : _save,
            child: Text(
              _dirty.isEmpty ? 'Saved' : 'Save',
              style: TextStyle(
                color: _dirty.isEmpty ? Colors.white24 : const Color(0xFF4FC3F7),
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7)))
          : SafeArea(
              child: Column(children: [
                // File tabs
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: names.map((name) {
                      final active = name == _active;
                      return GestureDetector(
                        onTap: () => _selectFile(name),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6, top: 6, bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: active ? const Color(0xFF0F3460) : const Color(0xFF12121F),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: active ? const Color(0xFF4FC3F7) : Colors.white12,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(name,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: active ? Colors.white : Colors.white54)),
                            if (_dirty.contains(name)) ...[
                              const SizedBox(width: 5),
                              const Text('•', style: TextStyle(color: Color(0xFFFF8A65), fontSize: 14)),
                            ],
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Mobile insert bar
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: [
                      _tool('⇥ Tab', () => _insert('  ')),
                      _tool('{ }', () => _wrap('{', '}')),
                      _tool('( )', () => _wrap('(', ')')),
                      _tool('[ ]', () => _wrap('[', ']')),
                      _tool('< >', () => _wrap('<', '>')),
                      _tool('" "', () => _wrap('"', '"')),
                      _tool("' '", () => _wrap("'", "'")),
                      _tool('= =', () => _wrap('=', '=')),
                    ],
                  ),
                ),
                // Editor
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Line numbers
                    Container(
                      width: 42,
                      color: const Color(0xFF07070E),
                      child: SingleChildScrollView(
                        controller: _gutter,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(
                              lineCount,
                              (i) => SizedBox(
                                height: _linePx,
                                child: Text(
                                  '${i + 1}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: _fontSize,
                                    height: _lineHeight,
                                    fontFamily: 'monospace',
                                    color: Color(0xFF3A3A4A),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        scrollController: _scroll,
                        onChanged: _onChanged,
                        maxLines: null,
                        expands: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          fontSize: _fontSize,
                          height: _lineHeight,
                          fontFamily: 'monospace',
                          color: Color(0xFFD8D8E4),
                        ),
                        cursorColor: const Color(0xFF4FC3F7),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.fromLTRB(10, 8, 10, 8),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ]),
                ),
                // Status bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: const Color(0xFF0D0D1A),
                  child: Row(children: [
                    Text(_cursorInfo,
                        style: const TextStyle(
                            fontSize: 10, fontFamily: 'monospace', color: Colors.white38)),
                    const Spacer(),
                    Text('${_controller.text.length} chars',
                        style: const TextStyle(fontSize: 10, color: Colors.white24)),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _tool(String label, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF12121F),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: Colors.white70)),
        ),
      );
}
