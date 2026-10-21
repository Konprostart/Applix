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

/// The post-generation screen: a live Preview tab (first), a hidden Code tab,
/// and one fixed action bar that never scrolls away with the code.
library;

import 'package:flutter/material.dart';

class GenerateResultView extends StatefulWidget {
  static const previewTabKey = Key('result-tab-preview');
  static const codeTabKey = Key('result-tab-code');
  static const previewPaneKey = Key('result-preview-pane');
  static const codePaneKey = Key('result-code-pane');
  static const actionsKey = Key('result-sticky-actions');
  static const previewActionKey = Key('result-action-preview');
  static const buildActionKey = Key('result-action-build');
  static const regenerateActionKey = Key('result-action-regenerate');

  final String appName;
  final Widget preview;
  final String code;
  final bool generating;
  final VoidCallback onBack;
  final VoidCallback onOpenPreview;
  final VoidCallback onBuild;
  final VoidCallback onRegenerate;
  final VoidCallback onEditDetails;
  final Widget? aboveActions;

  const GenerateResultView({
    super.key,
    required this.appName,
    required this.preview,
    required this.code,
    required this.onBack,
    required this.onOpenPreview,
    required this.onBuild,
    required this.onRegenerate,
    required this.onEditDetails,
    this.generating = false,
    this.aboveActions,
  });

  @override
  State<GenerateResultView> createState() => _GenerateResultViewState();
}

class _GenerateResultViewState extends State<GenerateResultView> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      _tabs(),
      Expanded(
        child: _tab == 0
            ? Padding(
                key: GenerateResultView.previewPaneKey,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Stack(children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: widget.preview,
                    ),
                  ),
                  if (widget.generating)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xE60A0A14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(
                              width: 28, height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 3, color: Color(0xFF6C8CFF)),
                            ),
                            SizedBox(height: 12),
                            Text('Generating...',
                                style: TextStyle(fontSize: 13, color: Colors.white70)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              )
            : _codePane(),
      ),
      if (widget.aboveActions != null) widget.aboveActions!,
      _actions(),
    ]);
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(children: [
        IconButton(
          onPressed: widget.generating ? null : widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 20, color: Colors.white70),
          tooltip: 'Back',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Text('Preview first · code stays out of the way',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ]),
        ),
        TextButton.icon(
          onPressed: widget.generating ? null : widget.onEditDetails,
          icon: const Icon(Icons.tune, size: 16),
          label: const Text('Details', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF9DB2FF)),
        ),
      ]),
    );
  }

  Widget _tabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF12121C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        _tabButton(
          key: GenerateResultView.previewTabKey,
          index: 0,
          icon: Icons.phone_android,
          label: 'Preview',
        ),
        _tabButton(
          key: GenerateResultView.codeTabKey,
          index: 1,
          icon: Icons.code,
          label: 'Code',
        ),
      ]),
    );
  }

  Widget _tabButton({
    required Key key,
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _tab == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          key: key,
          onTap: () => setState(() => _tab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF23305C) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: selected ? const Color(0xFF6C8CFF) : Colors.transparent),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16,
                  color: selected ? Colors.white : Colors.white38),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.white38,
                  )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _codePane() {
    return Container(
      key: GenerateResultView.codePaneKey,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF080810),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.lock_outline, size: 14, color: Colors.white38),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Read-only code · change the app from the Preview tab',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ),
          Text('${(widget.code.length / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(fontSize: 10, color: Colors.white24)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: SelectableText(
                widget.code,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  fontFamily: 'monospace',
                  color: Colors.white60,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _actions() {
    return Container(
      key: GenerateResultView.actionsKey,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Color(0xFF222232))),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: _action(
              key: GenerateResultView.previewActionKey,
              label: 'Preview',
              icon: Icons.visibility,
              onPressed: widget.generating ? null : widget.onOpenPreview,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _action(
              key: GenerateResultView.buildActionKey,
              label: 'Build APK',
              icon: Icons.build,
              primary: true,
              onPressed: widget.generating ? null : widget.onBuild,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _action(
              key: GenerateResultView.regenerateActionKey,
              label: 'Regenerate',
              icon: Icons.refresh,
              onPressed: widget.generating ? null : widget.onRegenerate,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _action({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    return SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              primary ? const Color(0xFF6C8CFF) : const Color(0xFF1A1A2E),
          foregroundColor: primary ? Colors.white : Colors.white70,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
