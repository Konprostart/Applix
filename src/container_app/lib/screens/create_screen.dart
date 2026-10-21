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

/// Screen for creating new apps via AI prompt, web URL, or demo template.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/generator.dart';
import '../services/bundle_storage.dart';
import '../services/prompt_builder.dart';
import '../services/app_storage.dart';
import '../services/ai_service.dart';
import '../services/bridge_linter.dart';
import '../version.dart';
import '../services/project_store.dart';
import '../services/ui_auditor.dart';
import '../services/settings_service.dart';
import '../widgets/build_log.dart';
import '../models/app_theme.dart';
import '../models/icon_config.dart';
import '../models/ai_provider.dart';
import 'code_editor_screen.dart';
import 'preview_screen.dart';
import 'splash_settings_screen.dart';
import 'icon_editor_screen.dart';
import '../services/error_helper.dart';
import 'flows/create_helpers.dart' as h;
import 'showcase_screen.dart';
import '../services/dev_text_sanitizer.dart';

class CreateScreen extends StatefulWidget {
  final VoidCallback? onAppSaved;
  final VoidCallback? onViewMyApps;
  const CreateScreen({super.key, this.onAppSaved, this.onViewMyApps});
  @override
  State<CreateScreen> createState() => CreateScreenState();
}

class CreateScreenState extends State<CreateScreen> {
  String? _mode;
  bool _isBuilding = false;
  bool _showBuildLog = false;
  final List<String> _log = [];

  final _nameController = TextEditingController();
  IconConfig _iconConfig = IconConfig();
  AppTheme _appTheme = const AppTheme();
  String? _editingId;
  String? _existingPackageName;
  String _firebaseConfig = '';

  final _urlController = TextEditingController();
  String? _urlError;
  final _descController = TextEditingController();
  final _htmlController = TextEditingController();
  String _generatedPrompt = '';
  bool _descExpanded = true;
  bool _promptVisible = false;
  bool _promptExpanded = false;
  bool _promptCopied = false;
  bool _htmlExpanded = false;

  String? _selectedDemoId;
  final _demoFilterController = TextEditingController();
  String _demoFilter = '';

  // Manual-flow prompt variant: 'full' (~45KB, works anywhere) or
  // 'linked' (~600 chars, references the hosted SPEC.md — needs an AI that can fetch URLs).
  String _promptVariant = 'full';
  String _generatedLinkedPrompt = '';

  // Bundled app files (databases, JSON, images, etc.)
  List<Map<String, dynamic>> _bundleFiles = [];
  List<Map<String, dynamic>> _projectFiles = [];
  bool _projectExpanded = false;
  bool _bundleExpanded = false;
  String? _pendingShowcaseBundleId; // set when loading a showcase app with resources

  // AI generation
  String _genMethod = ''; // 'api', 'manual'
  AiProvider? _activeProvider;
  bool _loadingProvider = false;
  List<ChatMessage> _conversation = [];
  bool _aiGenerating = false;
  bool _promptGenerating = false;
  DateTime? _genStartTime;
  int _genId = 0;
  final _followUpController = TextEditingController();
  String? _selectedHtml; // HTML selected via "Use This"
  final _formScrollController = ScrollController();
  List<BridgeIssue> _bridgeIssues = [];

  @override
  void initState() {
    super.initState();
    _restorePromptDraft();
  }

  /// The manual prompt is kept on the device, so it survives leaving the screen
  /// or restarting the app.
  Future<void> _restorePromptDraft() async {
    final draft = await Settings.getPromptDraft();
    if (!mounted) return;
    final full = draft['full'] ?? '';
    if (full.isEmpty) return;
    setState(() {
      _generatedPrompt = full;
      _generatedLinkedPrompt = draft['linked'] ?? '';
      _promptVisible = true;
      _promptExpanded = true;
      final desc = draft['description'] ?? '';
      if (desc.isNotEmpty && _descController.text.trim().isEmpty) {
        _descController.text = desc;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _descController.dispose();
    _htmlController.dispose();
    _followUpController.dispose();
    _formScrollController.dispose();
    _demoFilterController.dispose();
    super.dispose();
  }

  void _addLog(String msg) { if (mounted) setState(() => _log.add(msg)); }

  /// Keeps the AI conversation bounded - every message carries the full app code.
  void _trimConversation() {
    _conversation = AiService.trimConversation(_conversation);
  }

  void loadApp(AppData app) {
    _nameController.text = app.name;
    _descController.text = app.description;
    _htmlController.text = app.html;
    _generatedPrompt = app.prompt;
    _editingId = app.id;
    _existingPackageName = app.packageName;
    _firebaseConfig = app.firebaseConfig;
    _selectedDemoId = null;
    _isBuilding = false;
    _showBuildLog = false;
    _log.clear();
    _genMethod = 'manual';
    _descExpanded = true;
    _htmlExpanded = true;
    _conversation.clear();
    _loadBundleFiles();
    _loadProjectFiles();
    _aiGenerating = false;
    _selectedHtml = null;
    _bridgeIssues = [];
    _followUpController.clear();

    if (app.iconConfig.isNotEmpty) {
      try {
        _iconConfig = IconConfig.fromJsonString(app.iconConfig);
      _appTheme = AppTheme.fromJsonString(app.appTheme);
      } catch (_) {
        _iconConfig = IconConfig.defaultFor(app.name);
      }
    } else {
      _iconConfig = IconConfig.fromLegacy(
        emoji: app.emoji, emojiScale: app.emojiScale,
        emojiOffsetX: app.emojiOffsetX, emojiOffsetY: app.emojiOffsetY,
        appName: app.name,
      );
    }

    final type = app.appType.isNotEmpty ? app.appType
        : app.templateId.isNotEmpty ? 'demo'
        : app.description.startsWith('Web app: ') ? 'web' : 'ai';

    if (type == 'web') {
      _urlController.text = app.description.replaceFirst('Web app: ', '');
      _urlError = null;
      setState(() => _mode = 'web');
    } else if (type == 'demo') {
      _selectedDemoId = app.templateId;
      setState(() => _mode = 'demo');
    } else {
      _promptVisible = app.prompt.isNotEmpty;
      _htmlExpanded = true;
      _descExpanded = true;
      setState(() => _mode = 'ai');
    }
  }

  void _reset() {
    setState(() {
      _mode = null;
      _isBuilding = false;
      _showBuildLog = false;
      _nameController.clear();
      _urlController.clear(); _urlError = null;
      _descController.clear();
      _htmlController.clear();
      _generatedPrompt = '';
      _editingId = null;
      _existingPackageName = null;
      _firebaseConfig = '';
      _selectedDemoId = null;
      _iconConfig = IconConfig();
    _appTheme = const AppTheme();
      _descExpanded = true;
      _promptVisible = false;
      _promptExpanded = false;
      _promptCopied = false;
      _htmlExpanded = false;
      _genMethod = '';
      _conversation.clear();
      _aiGenerating = false;
      _selectedHtml = null;
      _followUpController.clear();
      _log.clear();
    });
  }

  IconConfig _ensureIconConfig(String label) {
    if (_iconConfig.elements.isEmpty) _iconConfig = IconConfig.defaultFor(label);
    return _iconConfig;
  }

  /// Opens the splash / system bar settings.
  Future<void> _openSplashSettings() async {
    _ensureIconConfig(_nameController.text.trim());
    final result = await Navigator.push<AppTheme>(
      context,
      MaterialPageRoute(
        builder: (_) => SplashSettingsScreen(theme: _appTheme, icon: _iconConfig),
      ),
    );
    if (result != null) setState(() => _appTheme = result);
  }

  /// Selects the AI API mode. When no provider is configured yet, the setup
  /// screen opens - the key the user types there is saved and handed back, so
  /// the app never sends the user to the key screen in a loop.
  Future<void> _selectAiApi() async {
    if (_activeProvider == null || !_activeProvider!.isConfigured) {
      final provider = _activeProvider ?? AiProvider.anthropic();
      final result = await Navigator.push<AiProvider>(
        context,
        MaterialPageRoute(builder: (_) => ProviderSetupPage(provider: provider)),
      );
      if (result == null) {
        // The user left the setup screen without a usable provider.
        await _loadActiveProvider();
        if (!mounted) return;
        final ready = _activeProvider?.isConfigured == true;
        setState(() => _genMethod = ready ? 'api' : '');
        if (!ready) {
          _snack('Set an API key (or a base URL and a model) to use the AI.');
        }
        return;
      }
      await Settings.setActiveProvider(result);
      _activeProvider = result;
      if (!result.isConfigured) {
        if (mounted) {
          setState(() => _genMethod = '');
          _snack('The provider still needs a valid API key and a model.');
        }
        return;
      }
    }
    if (mounted) setState(() => _genMethod = 'api');
  }

  Future<void> _openIconEditor() async {
    _ensureIconConfig(_nameController.text.trim());
    final result = await Navigator.push<IconConfig>(
      context, MaterialPageRoute(builder: (_) => IconEditorScreen(config: _iconConfig)),
    );
    if (result != null) setState(() => _iconConfig = result);
  }

  String _stripMarkdownFences(String text) {
    var s = text.trim();
    final m = RegExp(r'^```(?:html)?\s*\n?([\s\S]*?)\n?\s*```$').firstMatch(s);
    if (m != null) s = m.group(1)!.trim();
    final i = s.indexOf('<');
    if (i > 0) s = s.substring(i);
    return s;
  }

  Future<DateTime?> _getExistingCreatedAt(String id) async {
    try { return (await AppStorage.loadAll()).firstWhere((a) => a.id == id).createdAt; }
    catch (_) { return null; }
  }

  Future<void> _loadActiveProvider() async {
    _loadingProvider = true;
    try {
      _activeProvider = await Settings.getActiveProvider();
    } catch (_) {
      _activeProvider = null;
    }
    _loadingProvider = false;
    if (mounted) setState(() {});
  }

  /// Called when the Create tab becomes visible (e.g. after Settings change).
  void refreshProvider() => _loadActiveProvider();

  bool get isEditing => _isEditing;
  bool get hasMode => _mode != null;
  bool get isShowingBuildLog => _showBuildLog;

  void dismissBuildLog() {
    if (!_isBuilding) setState(() => _showBuildLog = false);
  }

  /// Called when user taps the Create tab while already on it or from another tab while editing.
  void handleCreateTap() {
    if (_editingId != null || _mode != null) {
      _confirmExit(_reset);
    }
  }

  /// When editing an existing app via API, seed the conversation with the current code
  /// so the user can ask for changes directly without re-generating from scratch.
  void _startEditConversation() {
    final existingHtml = _htmlController.text.trim();
    if (existingHtml.isEmpty || !existingHtml.startsWith('<')) return;
    setState(() {
      _genMethod = 'api';
      _conversation = [
        ChatMessage(role: 'assistant', content: existingHtml),
      ];
      _selectedHtml = existingHtml;
    });
  }

  Future<void> _generateWithAI(AiProvider provider) async {
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();
    if (name.isEmpty || desc.isEmpty) { _snack('Fill in name and description.'); return; }

    final thisGenId = ++_genId;
    setState(() {
      _genMethod = 'api';
      _aiGenerating = true; _genStartTime = DateTime.now();
      _conversation = [ChatMessage(role: 'user', content: 'App name: $name\nDescription: $desc')];
      _bridgeIssues = [];
    });

    try {
      final systemPrompt = await PromptBuilder.getSystemPrompt();
      final response = await AiService.generate(
        provider: provider,
        systemPrompt: systemPrompt,
        messages: _conversation,
      );
      if (!mounted || thisGenId != _genId) return;
      var cleaned = _stripMarkdownFences(response);
      _conversation.add(ChatMessage(role: 'assistant', content: cleaned));
      _trimConversation();
      setState(() => _aiGenerating = false);
      if (cleaned.trim().startsWith('<')) {
        cleaned = await _repairBridgeIssues(cleaned, thisGenId);
        if (!mounted || thisGenId != _genId) return;
        cleaned = await _polishUi(cleaned, thisGenId);
        if (!mounted || thisGenId != _genId) return;
        _useThisHtml(cleaned);
      } else {
        setState(() => _bridgeIssues = []);
      }
    } catch (e) {
      if (!mounted || thisGenId != _genId) return;
      setState(() => _aiGenerating = false);
      _snack(friendlyError(e.toString()).toString());
    }
  }

  Future<void> _sendFollowUp() async {
    final msg = _followUpController.text.trim();
    if (msg.isEmpty || _activeProvider == null) return;

    final thisGenId = ++_genId;
    final provider = _activeProvider!;
    setState(() {
      _conversation.add(ChatMessage(role: 'user', content: msg));
      _trimConversation();
      _followUpController.clear();
      _aiGenerating = true; _genStartTime = DateTime.now();
    });

    try {
      final systemPrompt = await PromptBuilder.getSystemPrompt();
      final response = await AiService.generate(
        provider: provider,
        systemPrompt: systemPrompt,
        messages: _conversation,
      );
      if (!mounted || thisGenId != _genId) return;
      var cleaned = _stripMarkdownFences(response);
      _conversation.add(ChatMessage(role: 'assistant', content: cleaned));
      _trimConversation();
      setState(() => _aiGenerating = false);
      if (cleaned.trim().startsWith('<')) {
        cleaned = await _repairBridgeIssues(cleaned, thisGenId);
        if (!mounted || thisGenId != _genId) return;
        cleaned = await _polishUi(cleaned, thisGenId);
        if (!mounted || thisGenId != _genId) return;
        _useThisHtml(cleaned);
      } else {
        setState(() => _bridgeIssues = []);
      }
    } catch (e) {
      if (!mounted || thisGenId != _genId) return;
      setState(() => _aiGenerating = false);
      _snack(friendlyError(e.toString()).toString());
    }
  }

  bool get _hasUnsavedChanges {
    if (_selectedHtml == null) return false;
    // If editing and the HTML matches what's saved, no unsaved changes
    if (_editingId != null && _selectedHtml == _htmlController.text.trim()) return false;
    // If conversation produced HTML that hasn't been built
    return _conversation.any((m) => m.role == 'assistant' && m.content.trim().startsWith('<'));
  }

  bool get _isEditing => _editingId != null;

  Future<void> _confirmExit(VoidCallback onConfirm) async {
    if (!_hasUnsavedChanges && !_isEditing) { onConfirm(); return; }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Discard changes?'),
        content: Text(_isEditing
          ? 'You\'re currently editing ${_nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'this app'}. Discard and start fresh?'
          : 'You have unsaved changes. Discard and start fresh?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard changes', style: TextStyle(color: Color(0xFFFF6B6B)))),
        ],
      ),
    );
    if (result == true && mounted) onConfirm();
  }

  void _useThisHtml(String html) {
    final clean = DevTextSanitizer.removeDevText(html);
    setState(() {
      _selectedHtml = clean;
      _htmlController.text = clean;
      _htmlExpanded = false;
    });
    _refreshBridgeIssues(clean);
    _snack('HTML loaded. Preview or build below.');
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_formScrollController.hasClients) {
        _formScrollController.animateTo(
          _formScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<List<BridgeIssue>> _lintBridge(String html) async {
    try {
      final linter = await BridgeLinter.load();
      return linter.lint(html);
    } catch (_) {
      return [];
    }
  }

  Future<void> _refreshBridgeIssues(String html) async {
    final issues = await _lintBridge(html);
    if (mounted) setState(() => _bridgeIssues = issues);
  }

  /// One automatic repair pass when the AI uses undocumented bridge calls.
  Future<String> _repairBridgeIssues(String html, int genId) async {
    BridgeLinter linter;
    try {
      linter = await BridgeLinter.load();
    } catch (_) {
      return html;
    }
    final issues = linter.lint(html);
    if (issues.isEmpty) {
      if (mounted && genId == _genId) setState(() => _bridgeIssues = []);
      return html;
    }
    if (!mounted || genId != _genId) return html;
    setState(() {
      _bridgeIssues = issues;
      _aiGenerating = true;
      _genStartTime = DateTime.now();
    });
    final provider = _activeProvider;
    if (provider == null || !provider.isConfigured) {
      setState(() => _aiGenerating = false);
      return html;
    }
    try {
      if (_conversation.isEmpty) {
        _conversation.add(ChatMessage(role: 'assistant', content: html));
      }
      _conversation.add(ChatMessage(
        role: 'user',
        content: BridgeLinter.buildRepairMessage(issues),
      ));
      final systemPrompt = await PromptBuilder.getSystemPrompt();
      final response = await AiService.generate(
        provider: provider,
        systemPrompt: systemPrompt,
        messages: _conversation,
      );
      final repaired = _stripMarkdownFences(response);
      final isHtml = repaired.trim().startsWith('<');
      final remaining = isHtml ? linter.lint(repaired) : issues;
      if (!mounted || genId != _genId) return html;
      if (isHtml) {
        _conversation.add(ChatMessage(role: 'assistant', content: repaired));
      }
      setState(() {
        _bridgeIssues = remaining;
        _aiGenerating = false;
      });
      return isHtml ? repaired : html;
    } catch (_) {
      if (mounted && genId == _genId) {
        setState(() => _aiGenerating = false);
      }
      return html;
    }
  }

  /// One automatic polish pass: fixes the things that make a generated app
  /// look like a web page (missing UI Kit classes, no touch targets, no theme
  /// color, content under the status bar, ...).
  Future<String> _polishUi(String html, int genId) async {
    final issues = UiAuditor.audit(html);
    if (issues.isEmpty) return html;
    if (!mounted || genId != _genId) return html;
    final provider = _activeProvider;
    if (provider == null || !provider.isConfigured) return html;
    setState(() {
      _aiGenerating = true;
      _genStartTime = DateTime.now();
    });
    try {
      final messages = <ChatMessage>[
        ChatMessage(role: 'user', content: 'Current app code:\n```html\n$html\n```'),
        ChatMessage(role: 'user', content: UiAuditor.buildPolishMessage(issues)),
      ];
      final systemPrompt = await PromptBuilder.getSystemPrompt();
      final response = await AiService.generate(
        provider: provider,
        systemPrompt: systemPrompt,
        messages: messages,
      );
      final polished = _stripMarkdownFences(response);
      if (!polished.trim().startsWith('<')) return html;
      if (mounted && genId == _genId) {
        _conversation.add(ChatMessage(role: 'assistant', content: polished));
      }
      return polished;
    } catch (_) {
      return html;
    } finally {
      if (mounted && genId == _genId) setState(() => _aiGenerating = false);
    }
  }

  Future<void> _fixBridgeIssues() async {
    final html = _htmlController.text.trim();
    if (html.isEmpty || _bridgeIssues.isEmpty || _aiGenerating) return;
    final thisGenId = ++_genId;
    final fixed = await _repairBridgeIssues(html, thisGenId);
    if (!mounted || thisGenId != _genId) return;
    if (fixed != html && fixed.trim().startsWith('<')) _useThisHtml(fixed);
  }

  Widget _bridgeWarningCard() {
    if (_bridgeIssues.isEmpty) return const SizedBox.shrink();
    final shown = _bridgeIssues.take(5).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF6B6B)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFFF6B6B)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            '${_bridgeIssues.length} unknown bridge call${_bridgeIssues.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFF6B6B)),
          )),
          GestureDetector(
            onTap: () => setState(() => _bridgeIssues = []),
            child: const Icon(Icons.close, size: 14, color: Colors.white38),
          ),
        ]),
        const SizedBox(height: 6),
        ...shown.map((issue) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            'Line ${issue.line}: ${issue.call}',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white54),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        )),
        if (_bridgeIssues.length > shown.length)
          Text('+ ${_bridgeIssues.length - shown.length} more',
              style: const TextStyle(fontSize: 10, color: Colors.white30)),
        const SizedBox(height: 6),
        Row(children: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: BridgeLinter.formatIssues(_bridgeIssues)));
              _snack('Bridge errors copied.');
            },
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copy errors', style: TextStyle(fontSize: 11)),
          ),
          if (_activeProvider != null && _activeProvider!.isConfigured && !_aiGenerating)
            TextButton.icon(
              onPressed: () { _fixBridgeIssues(); },
              icon: const Icon(Icons.auto_fix_high, size: 14),
              label: const Text('Fix with AI', style: TextStyle(fontSize: 11)),
            ),
        ]),
      ]),
    );
  }

  static const _channel = MethodChannel('com.konprostart.applix/generator');

  Future<void> _voiceInput() async {
    try {
      final result = await _channel.invokeMethod<String>('speechToText');
      if (result != null && result.isNotEmpty && mounted) {
        setState(() {
          _descController.text = _descController.text.isEmpty
            ? result
            : '${_descController.text} $result';
          _descController.selection = TextSelection.collapsed(offset: _descController.text.length);
        });
      }
    } catch (e) {
      _snack('Speech recognition not available');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A2E), duration: const Duration(seconds: 4)));
  }

  // ── Builds ──

  Future<void> _buildWebApp() async {
    final label = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (label.isEmpty || url.isEmpty) { _snack('Please fill in name and URL.'); return; }
    if (label.length > 37 || label.codeUnits.length > 37) { _snack('Name too long (max 37 characters).'); return; }
    if (!url.startsWith('http://') && !url.startsWith('https://')) { _snack('URL must start with http:// or https://'); return; }
    final safeLabel = label.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final safeUrl = url.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('<', '\\x3c');
    final html = '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>$safeLabel</title><style>*{margin:0;padding:0}body{background:#0d0d1a;display:flex;align-items:center;justify-content:center;height:100vh;font-family:-apple-system,sans-serif}.loader{color:#4FC3F7;font-size:14px}.spinner{width:24px;height:24px;border:3px solid #1a1a2e;border-top-color:#4FC3F7;border-radius:50%;animation:spin .8s linear infinite;margin:0 auto 12px}@keyframes spin{to{transform:rotate(360deg)}}</style></head><body><div class="loader"><div class="spinner"></div>Loading...</div><script>window.location.href="$safeUrl";</script></body></html>';
    await _doBuild(label, html, 'web', description: 'Web app: $url');
  }

  Future<void> _buildAiApp() async {
    final label = _nameController.text.trim();
    final html = _htmlController.text.trim();
    if (label.isEmpty || html.isEmpty) { _snack('Fill in name and paste HTML.'); return; }
    if (label.length > 37 || label.codeUnits.length > 37) { _snack('Name too long (max 37 characters).'); return; }
    if (!html.startsWith('<')) { _snack('HTML must start with < (e.g., <!DOCTYPE html>).'); return; }
    final issues = await _lintBridge(html);
    if (issues.isNotEmpty) {
      if (!mounted) return;
      setState(() => _bridgeIssues = issues);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Unknown bridge calls'),
          content: Text('${issues.length} bridge call${issues.length == 1 ? ' is' : 's are'} not documented and may fail at runtime.\n\nBuild anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Build anyway', style: TextStyle(color: Color(0xFFFF8A65))),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    await _doBuild(label, html, 'ai', description: _descController.text.trim(), prompt: _generatedPrompt);
  }

  Future<void> _buildDemo() async {
    if (_selectedDemoId == null) return;
    final t = [...h.starterTemplates, ...h.demoTemplates].where((t) => t.$1 == _selectedDemoId).firstOrNull;
    if (t == null) { _snack('Demo template not found.'); return; }
    final label = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : t.$3;
    if (label.length > 37 || label.codeUnits.length > 37) { _snack('Name too long (max 37 characters).'); return; }
    if (_iconConfig.elements.isEmpty) {
      _iconConfig = IconConfig(bgColor: IconConfig.colorForString(t.$2), elements: [IconElement(content: t.$2)]);
    }
    if (_existingPackageName != null && _existingPackageName!.isNotEmpty) {
      final ok = await Generator.handleSignatureConflict(packageName: _existingPackageName!, context: context);
      if (!ok) return;
    }
    if (t.$1.startsWith('starter:')) {
      // Starter apps are real HTML files shipped with Applix - they get the
      // UI kit injected at build time just like an AI generated app.
      final starterId = t.$1.substring('starter:'.length);
      String html;
      try {
        html = await rootBundle.loadString('assets/starters/$starterId.html');
      } catch (e) {
        _snack('Starter app could not be loaded.');
        return;
      }
      await _doBuild(label, html, 'ai', description: t.$4);
      return;
    }
    setState(() { _isBuilding = true; _showBuildLog = true; _log.clear(); });
    try {
      final result = await Generator.generateFromTemplate(label: label, templateId: t.$1, packageName: _existingPackageName, iconConfig: _iconConfig.toJsonString(), appTheme: _appTheme.toJsonString(), onProgress: _addLog);
      final now = DateTime.now();
      final appId = _editingId ?? '${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      await AppStorage.save(AppData(
        id: appId, name: label,
        description: 'Demo: ${t.$4}', prompt: '', html: '', appType: 'demo', templateId: t.$1,
        packageName: result.packageName, apkPath: result.apkPath, iconConfig: _iconConfig.toJsonString(),
        createdAt: _editingId != null ? (await _getExistingCreatedAt(_editingId!) ?? now) : now, updatedAt: now,
      ));
      _editingId = appId;
      _existingPackageName = result.packageName;
      _addLog('\u2705 Build complete! App saved.');
      widget.onAppSaved?.call();
    } on PlatformException catch (e) {
      if (e.message != null && e.message!.contains('SIGNATURE_CONFLICT:')) {
        final pkg = e.message!.split('SIGNATURE_CONFLICT:').last;
        _addLog('\u26A0 App signed by another device. Uninstall the old version first.');
        final ok = await Generator.handleSignatureConflict(packageName: pkg, context: context);
        if (ok) _addLog('Old version removed. Tap Build again to install.');
      } else {
        final err = friendlyError(e.message); _addLog('\u274C ${err.message}'); if (err.hint != null) _addLog('   ${err.hint}');
      }
    } catch (e) {
      _addLog('\u274C Unexpected error: $e');
    }
    finally { if (mounted) setState(() => _isBuilding = false); }
  }

  Future<void> _doBuild(String label, String html, String appType, {String description = '', String prompt = ''}) async {
    if (_existingPackageName != null && _existingPackageName!.isNotEmpty) {
      final ok = await Generator.handleSignatureConflict(packageName: _existingPackageName!, context: context);
      if (!ok) return;
    }
    setState(() { _isBuilding = true; _showBuildLog = true; _log.clear(); });
    try {
      // Save old version before rebuilding
      if (_editingId != null) {
        final existing = (await AppStorage.loadAll()).where((a) => a.id == _editingId).toList();
        if (existing.isNotEmpty && existing.first.html.isNotEmpty && existing.first.html != html) {
          await AppStorage.saveVersion(_editingId!, existing.first.html);
        }
      }
      final ic = _ensureIconConfig(label);
      // If a showcase app was loaded with resources, move the temp bundle to the real appId
      final appId = _editingId ?? '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      if (_pendingShowcaseBundleId != null && _editingId == null) {
        // First build of a showcase app — move temp bundle to the new appId
        final tempFiles = await BundleStorage.readAll(_pendingShowcaseBundleId!);
        for (final entry in tempFiles.entries) {
          await BundleStorage.addFile(appId, entry.key, entry.value);
        }
        await BundleStorage.clearBundle(_pendingShowcaseBundleId!);
        _pendingShowcaseBundleId = null;
        _editingId = appId; // set early so bundlePaths picks it up
      }
      final bundlePaths = await BundleStorage.paths(appId);
      // The project (entry file + extra files) lives on the device and is
      // shipped inside the APK, so relative paths such as <link href="style.css">
      // work in the installed app.
      await ProjectStore.writeProject(
        appId: appId,
        packageName: _existingPackageName,
        indexHtml: html,
      );
      final projectPaths = await ProjectStore.paths(appId: appId, packageName: _existingPackageName);
      final result = await Generator.injectHtml(label: label, htmlContent: html, packageName: _existingPackageName, iconConfig: ic.toJsonString(), appTheme: _appTheme.toJsonString(), firebaseConfig: _firebaseConfig.isNotEmpty ? _firebaseConfig : null, onProgress: _addLog, webOnly: appType == 'web', bundleFiles: bundlePaths, projectFiles: projectPaths);
      // Now that the package name is known, move the project to its final place.
      await ProjectStore.migrateToPackage(appId: appId, packageName: result.packageName);
      await ProjectStore.writeConfig(
        appId: appId,
        packageName: result.packageName,
        config: {
          'name': label,
          'packageName': result.packageName,
          'version': kAppVersion,
          'entry': 'index.html',
          'files': projectPaths.keys.toList(),
          'icon': jsonDecode(ic.toJsonString()),
          'theme': _appTheme.toJson(),
          'updated': DateTime.now().toIso8601String(),
        },
      );
      await _loadProjectFiles();
      final now = DateTime.now();
      await AppStorage.save(AppData(
        id: appId, name: label,
        description: description, prompt: prompt, html: AppStorage.tagHtml(html), appType: appType,
        packageName: result.packageName, apkPath: result.apkPath, iconConfig: ic.toJsonString(),
        appTheme: _appTheme.toJsonString(), firebaseConfig: _firebaseConfig,
        createdAt: _editingId != null ? (await _getExistingCreatedAt(_editingId!) ?? now) : now, updatedAt: now,
      ));
      _editingId = appId;
      _existingPackageName = result.packageName;
      _addLog('\u2705 Build complete! App saved.');
      widget.onAppSaved?.call();
    } on PlatformException catch (e) {
      if (e.message != null && e.message!.contains('SIGNATURE_CONFLICT:')) {
        final pkg = e.message!.split('SIGNATURE_CONFLICT:').last;
        _addLog('\u26A0 App signed by another device. Uninstall the old version first.');
        final ok = await Generator.handleSignatureConflict(packageName: pkg, context: context);
        if (ok) _addLog('Old version removed. Tap Build again to install.');
      } else {
        final err = friendlyError(e.message); _addLog('\u274C ${err.message}'); if (err.hint != null) _addLog('   ${err.hint}');
      }
    } catch (e) {
      _addLog('\u274C Unexpected error: $e');
    }
    finally { if (mounted) setState(() => _isBuilding = false); }
  }

  Future<void> _loadBundleFiles() async {
    if (_editingId == null) return;
    final files = await BundleStorage.listFiles(_editingId!);
    if (mounted) setState(() => _bundleFiles = files);
  }

  /// Loads the project files (style.css, script.js, ...) of the current app.
  Future<void> _loadProjectFiles() async {
    final appId = _editingId;
    if (appId == null) return;
    final files = await ProjectStore.listFiles(
      appId: appId,
      packageName: _existingPackageName,
    );
    if (mounted) setState(() => _projectFiles = files);
  }

  /// Adds a text file to the project. It is shipped next to index.html, so the
  /// app can load it with a relative path.
  Future<void> _addProjectFile() async {
    final appId = _editingId;
    if (appId == null) { _snack('Save the app first, then add project files.'); return; }
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['css', 'js', 'json', 'html', 'txt', 'svg', 'csv', 'md'],
    );
    if (r == null || r.files.single.path == null) return;
    final picked = File(r.files.single.path!);
    final name = r.files.single.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final bytes = await picked.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) { _snack('Project files are limited to 2 MB.'); return; }
    try {
      final content = utf8.decode(bytes);
      await ProjectStore.addFile(
        appId: appId,
        packageName: _existingPackageName,
        name: name,
        content: content,
      );
      await _loadProjectFiles();
      _snack('Added $name to the project');
    } catch (_) {
      _snack('Only text files can be added to a project.');
    }
  }

  Future<void> _removeProjectFile(String name) async {
    final appId = _editingId;
    if (appId == null) return;
    await ProjectStore.removeFile(
      appId: appId,
      packageName: _existingPackageName,
      name: name,
    );
    await _loadProjectFiles();
  }

  Future<void> _addBundleFile() async {
    final appId = _editingId;
    if (appId == null) { _snack('Save the app first, then add files.'); return; }
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    if (r == null || r.files.single.path == null) return;
    final picked = File(r.files.single.path!);
    var name = r.files.single.name;
    // Sanitize filename
    name = name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    if (name.length > 100) name = name.substring(0, 100);
    final bytes = await picked.readAsBytes();
    if (bytes.length > 100 * 1024 * 1024) { _snack('File too large (max 100 MB).'); return; }
    await BundleStorage.addFile(appId, name, bytes);
    await _loadBundleFiles();
    _snack('Added $name (${(bytes.length / 1024).toStringAsFixed(0)} KB)');
  }

  Future<void> _removeBundleFile(String name) async {
    if (_editingId == null) return;
    await BundleStorage.removeFile(_editingId!, name);
    await _loadBundleFiles();
  }

  String _bundleTotalSize() {
    int total = 0;
    for (final f in _bundleFiles) total += f['size'] as int;
    if (total < 1024) return '$total B';
    if (total < 1024 * 1024) return '${(total / 1024).toStringAsFixed(1)} KB';
    return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _generatePrompt() async {
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();
    if (name.isEmpty || desc.isEmpty) {
      _snack('Fill in the app name and describe what it should do.');
      return;
    }
    if (_promptGenerating) return;
    setState(() => _promptGenerating = true);
    try {
      final existingHtml = _editingId != null ? _htmlController.text.trim() : null;
      final full = await PromptBuilder.buildPrompt(appName: name, description: desc, existingHtml: existingHtml);
      final linked = await PromptBuilder.buildLinkedPrompt(appName: name, description: desc, existingHtml: existingHtml);
      // Keep the prompt on the device - it is the only copy of the work the
      // user did, and the Manual flow spans several app launches.
      await Settings.savePromptDraft(full: full, linked: linked, description: desc);
      if (!mounted) return;
      setState(() {
        _generatedPrompt = full;
        _generatedLinkedPrompt = linked;
        _promptVisible = true;
        _promptExpanded = true;
        _promptCopied = false;
        _descExpanded = false;
        _htmlExpanded = true;
      });
      _snack('Prompt ready - copy it to your AI, then paste the HTML back here.');
    } catch (e) {
      _snack('Could not create the prompt: $e');
    } finally {
      if (mounted) setState(() => _promptGenerating = false);
    }
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _showBuildLog ? _buildingView() : _mode == null ? _modeSelection() : _mode == 'showcase' ? _showcaseView() : _formView(),
      ),
    );
  }

  /// Opens the built-in code editor for the project files.
  Future<void> _openCodeEditor() async {
    final appId = _editingId;
    if (appId == null) { _snack('Save the app first, then edit its code.'); return; }
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CodeEditorScreen(
          appId: appId,
          packageName: _existingPackageName,
          onSaved: (file, content) {
            // The entry page is the app code - keep the editor in sync and
            // refresh the list of project files.
            if (file == 'index.html' && mounted) {
              _htmlController.text = content;
              setState(() {});
            }
            _loadProjectFiles();
          },
        ),
      ),
    );
  }

  Widget _advancedSettings() {
    if (_existingPackageName == null || _existingPackageName!.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: const Text('Advanced Settings', style: TextStyle(fontSize: 13, color: Colors.white54)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      iconColor: Colors.white38,
      collapsedIconColor: Colors.white38,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Package Name', style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 4),
            SelectableText(_existingPackageName!, style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Color(0xFF4FC3F7))),
            const SizedBox(height: 4),
            const Text('Use this when adding an Android app in Firebase Console.', style: TextStyle(fontSize: 10, color: Colors.white24)),
            const SizedBox(height: 16),
            // Advanced: open the code editor for the project files.
            GestureDetector(
              onTap: _openCodeEditor,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F3460),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.code, size: 16, color: Color(0xFF4FC3F7)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Edit Code',
                        style: TextStyle(fontSize: 13, color: Colors.white)),
                  ),
                  const Text('index.html, style.css, script.js',
                      style: TextStyle(fontSize: 10, color: Colors.white54)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.white24),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Firebase Config (optional)', style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 4),
            const Text('Enables push notifications. Create a Firebase project, add an Android app with the package name above, download google-services.json.',
              style: TextStyle(fontSize: 10, color: Colors.white24)),
            const SizedBox(height: 8),
            Row(children: [
              GestureDetector(
                onTap: () async {
                  final result = await FilePicker.platform.pickFiles(type: FileType.any);
                  if (result != null && result.files.single.path != null) {
                    final file = File(result.files.single.path!);
                    final content = await file.readAsString();
                    if (content.contains('project_id') && content.contains('client')) {
                      setState(() => _firebaseConfig = content);
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invalid google-services.json')),
                      );
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F3460),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _firebaseConfig.isEmpty ? 'Pick google-services.json' : 'Replace config',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4FC3F7)),
                  ),
                ),
              ),
              if (_firebaseConfig.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: Color(0xFF69F0AE), size: 16),
                const SizedBox(width: 4),
                const Text('Configured', style: TextStyle(fontSize: 11, color: Color(0xFF69F0AE))),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _firebaseConfig = ''),
                  child: const Icon(Icons.close, color: Colors.white38, size: 16),
                ),
              ],
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _modeSelection() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _appHeader('Create App'),
      const SizedBox(height: 32),
      const Text('What do you want to create?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 20),
      h.buildModeCard(icon: Icons.auto_awesome, title: 'AI-generated App', subtitle: 'Describe what you want, generate with AI', onTap: () => setState(() => _mode = 'ai')),
      const SizedBox(height: 12),
      h.buildModeCard(icon: Icons.language, title: 'Website as App', subtitle: 'Turn any website into a standalone app', onTap: () => setState(() => _mode = 'web')),
      const SizedBox(height: 12),
      h.buildModeCard(icon: Icons.storefront_outlined, title: 'Showcase', subtitle: 'Community apps — ready to build', onTap: () => setState(() => _mode = 'showcase')),
      const SizedBox(height: 12),
      h.buildModeCard(icon: Icons.science_outlined, title: 'Demo App', subtitle: 'Pre-built apps to test bridge features', onTap: () => setState(() => _mode = 'demo')),
    ]),
  );

  Widget _showcaseView() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
    child: ShowcaseScreen(onBack: () => setState(() => _mode = null), onLoadApp: (name, html, {String? bundleAppId}) {
      _pendingShowcaseBundleId = bundleAppId;
      _nameController.text = name;
      _htmlController.text = html;
      _descController.text = 'Showcase app: $name';
      _selectedHtml = html;
      _genMethod = 'manual';
      _htmlExpanded = true;
      _descExpanded = false;
      setState(() => _mode = 'ai');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name loaded — preview or build it'), backgroundColor: const Color(0xFF1A1A2E), duration: const Duration(seconds: 3)));
      });
    }),
  );

  Widget _formView() {
    final isEdit = _editingId != null;
    final label = _mode == 'web' ? 'Website as App' : _mode == 'ai' ? 'AI App' : 'Demo App';
    return SingleChildScrollView(
      controller: _formScrollController,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Back + title
        Row(children: [
          GestureDetector(
            onTap: () => _confirmExit(isEdit ? () => widget.onViewMyApps?.call() : _reset),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_back, size: 18, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Editing' : 'New $label',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (isEdit && _nameController.text.isNotEmpty)
                Text(_nameController.text, style: const TextStyle(fontSize: 12, color: Colors.white38)),
            ],
          )),
          GestureDetector(
            onTap: () => _confirmExit(isEdit ? () => widget.onViewMyApps?.call() : _reset),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(8)),
              child: const Text('Cancel', style: TextStyle(fontSize: 13, color: Colors.white54)),
            ),
          ),
        ]),
        const SizedBox(height: 24),

        // Icon + Name
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openIconEditor,
              borderRadius: BorderRadius.circular(14),
              child: Stack(children: [
                IconPreview(config: _iconConfig.elements.isEmpty ? _ensureIconConfig(_nameController.text.trim()) : _iconConfig, size: 60),
                Positioned(right: -2, bottom: -2, child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: const Color(0xFF4FC3F7), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF0D0D1A), width: 2)),
                  child: const Icon(Icons.edit, size: 12, color: Color(0xFF0D0D1A)),
                )),
              ]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'App Name', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            textCapitalization: TextCapitalization.words,
          )),
        ]),
        const SizedBox(height: 20),

        // Splash + system bars (not for the web wrapper)
        if (_mode != 'web')
          GestureDetector(
            onTap: _openSplashSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF12121F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: _appTheme.splashBackground != 0
                        ? Color(_appTheme.splashBackground)
                        : Color(_iconConfig.bgGradient != null && _iconConfig.bgGradient!.isNotEmpty
                            ? _iconConfig.bgGradient!.first
                            : _iconConfig.bgColor),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white12),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Splash & system bars',
                      style: TextStyle(fontSize: 13, color: Colors.white70)),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.white24),
              ]),
            ),
          ),

        if (_mode == 'web') _webFields(),
        if (_mode == 'ai') _aiFields(),
        if (_mode == 'demo') _demoFields(),
      ]),
    );
  }

  // ── Web ──
  void _validateUrl() {
    final url = _urlController.text.trim();
    setState(() {
      if (url.isEmpty) { _urlError = null; }
      else if (!url.startsWith('http://') && !url.startsWith('https://')) { _urlError = 'Must start with http:// or https://'; }
      else if (url == 'http://' || url == 'https://') { _urlError = 'Enter a complete URL'; }
      else if (!url.contains('.')) { _urlError = 'Enter a valid URL'; }
      else { _urlError = null; }
    });
  }

  Widget _webFields() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('URL', style: TextStyle(fontSize: 13, color: Colors.white54)),
    const SizedBox(height: 8),
    TextField(controller: _urlController, style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(hintText: 'https://example.com', errorText: _urlError),
      keyboardType: TextInputType.url,
      onChanged: (_) { if (_urlError != null) _validateUrl(); },
      onEditingComplete: _validateUrl),
    _advancedSettings(),
    const SizedBox(height: 24),
    h.buildActionButton(label: 'Build App', onPressed: _isBuilding ? null : _buildWebApp, icon: Icons.rocket_launch),
  ]);

  // ── AI ──
  Widget _aiFields() {
    if (_activeProvider == null && !_loadingProvider) _loadActiveProvider();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Section 1: Describe
      _section('Describe your app', _descExpanded, () => setState(() => _descExpanded = !_descExpanded),
        done: _genMethod.isNotEmpty || _generatedPrompt.isNotEmpty,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Stack(children: [
            TextField(controller: _descController, style: const TextStyle(color: Colors.white), maxLines: 4,
              decoration: const InputDecoration(hintText: 'What should the app do?', contentPadding: EdgeInsets.fromLTRB(12, 12, 48, 12)),
              textCapitalization: TextCapitalization.sentences),
            Positioned(right: 4, bottom: 4, child: GestureDetector(
              onTap: _voiceInput,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.mic, size: 18, color: Color(0xFF4FC3F7)),
              ),
            )),
          ]),
          const SizedBox(height: 16),
          const Text('Choose how to generate the code for your app.',
              style: TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _genButton(
              icon: Icons.content_paste,
              label: 'AI Manual',
              sublabel: 'Copy-paste',
              selected: _genMethod == 'manual',
              onTap: () => setState(() => _genMethod = 'manual'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _genButton(
              icon: Icons.auto_awesome,
              label: 'AI API',
              sublabel: _activeProvider != null && _activeProvider!.isConfigured
                  ? _activeProvider!.selectedModel.split('/').last.split('-').take(3).join('-')
                  : 'Set up an AI provider',
              warning: _activeProvider == null || !_activeProvider!.isConfigured,
              selected: _genMethod == 'api',
              onTap: () => _selectAiApi(),
            )),
          ]),
          if (_genMethod.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (_genMethod == 'manual')
              const Padding(padding: EdgeInsets.only(bottom: 10),
                child: Text('This will generate a detailed prompt containing all technical instructions. Copy the prompt to any AI assistant, and paste the HTML code it returns back here.',
                  style: TextStyle(fontSize: 11, color: Colors.white38)))
            else if (_genMethod == 'api')
              Padding(padding: const EdgeInsets.only(bottom: 10),
                child: Text('Your app description will be sent to ${_activeProvider?.selectedModel.split('/').last ?? "the AI"} along with the technical documentation. The response appears below.',
                  style: const TextStyle(fontSize: 11, color: Colors.white38))),
            if (_genMethod == 'api' && _editingId != null && _htmlController.text.trim().startsWith('<') && _conversation.isEmpty)
              h.buildActionButton(
                label: 'Edit with AI',
                icon: Icons.edit,
                onPressed: _startEditConversation,
              )
            else
              h.buildActionButton(
                label: _promptGenerating
                    ? 'Creating prompt...'
                    : (_genMethod == 'api'
                        ? 'Generate'
                        : (_editingId != null ? 'Create Update Prompt' : 'Create Prompt for AI')),
                icon: _genMethod == 'api' ? Icons.auto_awesome : Icons.content_paste,
                onPressed: (_aiGenerating || _promptGenerating) ? null : () {
                  if (_genMethod == 'manual') {
                    _generatePrompt();
                  } else if (_activeProvider != null && _activeProvider!.isConfigured) {
                    _generateWithAI(_activeProvider!);
                  } else {
                    // No usable provider: open the setup instead of doing nothing.
                    _selectAiApi();
                  }
                },
              ),
          ],
        ]),
      ),

      // Section 2a: AI Conversation (when using API)
      if (_genMethod == 'api' && _conversation.isNotEmpty) ...[
        const SizedBox(height: 10),
        _section('AI Conversation', true, () {},
          done: _selectedHtml != null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            const Text('Use the text field below to ask for changes. Each message includes the full conversation history.',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 8),
            // Messages
            ..._conversation.map((msg) => _chatBubble(msg)),
            if (_aiGenerating)
              _generatingIndicator(),
            if (!_aiGenerating && _conversation.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(
                  controller: _followUpController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(hintText: _editingId != null ? 'What should change?' : 'Ask for changes...', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                  onSubmitted: (_) => _sendFollowUp(),
                )),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendFollowUp,
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.send, size: 18, color: Color(0xFF4FC3F7)),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ],

      // Section 2b: Manual copy-paste (when using manual)
      if (_genMethod == 'manual') ...[
        if (_promptVisible) ...[
          const SizedBox(height: 10),
          _section('Copy prompt to AI', _promptExpanded, () => setState(() => _promptExpanded = !_promptExpanded), done: _promptCopied,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              const Text('Send this prompt to an AI assistant. The prompt contains the bridge documentation and your app description. It is saved on this device, so you can come back to it later.',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(height: 10),
              // Variant toggle — Full (works anywhere) vs Linked (short, needs an AI that can fetch URLs).
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setState(() => _promptVariant = 'full'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _promptVariant == 'full' ? const Color(0xFF1E3A5F) : const Color(0xFF0A0A14),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                      border: Border.all(color: _promptVariant == 'full' ? const Color(0xFF4FC3F7) : const Color(0xFF222232)),
                    ),
                    child: Center(child: Text('Full (${(_generatedPrompt.length / 1024).toStringAsFixed(1)} KB)',
                        style: TextStyle(fontSize: 11, color: _promptVariant == 'full' ? Colors.white : Colors.white54))),
                  ),
                )),
                Expanded(child: GestureDetector(
                  onTap: () => setState(() => _promptVariant = 'linked'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _promptVariant == 'linked' ? const Color(0xFF1E3A5F) : const Color(0xFF0A0A14),
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                      border: Border.all(color: _promptVariant == 'linked' ? const Color(0xFF4FC3F7) : const Color(0xFF222232)),
                    ),
                    child: Center(child: Text('Linked (${(_generatedLinkedPrompt.length / 1024).toStringAsFixed(1)} KB)',
                        style: TextStyle(fontSize: 11, color: _promptVariant == 'linked' ? Colors.white : Colors.white54))),
                  ),
                )),
              ]),
              const SizedBox(height: 6),
              Text(
                _promptVariant == 'full'
                  ? 'Full prompt works with any AI. Large.'
                  : 'Short prompt that points to the hosted spec. Use with Claude.ai, ChatGPT (browsing), Gemini.',
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity, constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF0A0A14), borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(child: Text(
                  _promptVariant == 'full' ? _generatedPrompt : _generatedLinkedPrompt,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white38))),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: h.buildActionButton(label: 'Copy', icon: Icons.copy, onPressed: () {
                  final text = _promptVariant == 'full' ? _generatedPrompt : _generatedLinkedPrompt;
                  Clipboard.setData(ClipboardData(text: text));
                  setState(() { _promptCopied = true; _promptExpanded = false; });
                  _snack('Copied! Paste into your AI assistant.');
                })),
                const SizedBox(width: 10),
                Expanded(child: h.buildActionButton(label: 'Share', icon: Icons.share, secondary: true, onPressed: () {
                  final text = _promptVariant == 'full' ? _generatedPrompt : _generatedLinkedPrompt;
                  final name = _nameController.text.trim().replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
                  Generator.shareText(content: text, filename: '${name.isEmpty ? "prompt" : name}_prompt.txt');
                  setState(() { _promptCopied = true; });
                })),
              ]),
              const SizedBox(height: 8),
              h.buildActionButton(label: 'Save to Downloads', icon: Icons.download, secondary: true, onPressed: () async {
                try {
                  final text = _promptVariant == 'full' ? _generatedPrompt : _generatedLinkedPrompt;
                  final name = _nameController.text.trim().replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
                  final filename = '${name.isEmpty ? "prompt" : name}_prompt.txt';
                  final dir = Directory('/storage/emulated/0/Download');
                  if (!dir.existsSync()) dir.createSync(recursive: true);
                  final file = File('${dir.path}/$filename');
                  file.writeAsStringSync(text);
                  setState(() { _promptCopied = true; });
                  _snack('Saved to Downloads/$filename');
                } catch (e) {
                  _snack('Could not save: $e');
                }
              }),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        _section('Paste the AI response', _htmlExpanded, () => setState(() => _htmlExpanded = !_htmlExpanded),
          done: _htmlController.text.trim().startsWith('<'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            const Text('Paste the HTML code from the AI response. The code should be a complete HTML file starting with <!DOCTYPE html>.',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 8),
            TextField(controller: _htmlController, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white),
              maxLines: 8, onChanged: (_) { if (_bridgeIssues.isNotEmpty) setState(() => _bridgeIssues = []); },
              decoration: const InputDecoration(hintText: 'Paste HTML here...', hintStyle: TextStyle(fontFamily: 'monospace'))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (!mounted) return;
                  if (d?.text != null) {
                    _htmlController.text = _stripMarkdownFences(d!.text!);
                    setState(() {});
                    _refreshBridgeIssues(_htmlController.text.trim());
                  }
                },
                icon: const Icon(Icons.paste, size: 16), label: const Text('Paste'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF4FC3F7), side: const BorderSide(color: Color(0xFF4FC3F7)),
                  padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['html', 'htm', 'txt']);
                  if (!mounted) return;
                  if (r != null && r.files.single.path != null) {
                    _htmlController.text = _stripMarkdownFences(await File(r.files.single.path!).readAsString());
                    if (mounted) setState(() {});
                    _refreshBridgeIssues(_htmlController.text.trim());
                  }
                },
                icon: const Icon(Icons.file_open, size: 16), label: const Text('File'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF4FC3F7), side: const BorderSide(color: Color(0xFF4FC3F7)),
                  padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
            ]),
          ]),
        ),
      ],

      // Project files — extra files that sit next to index.html in the APK
      if (_editingId != null) ...[
        const SizedBox(height: 6),
        _section(
          'Project files${_projectFiles.isNotEmpty ? ' (${_projectFiles.length})' : ''}',
          _projectExpanded,
          () { setState(() => _projectExpanded = !_projectExpanded); if (_projectExpanded && _projectFiles.isEmpty) _loadProjectFiles(); },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            const Text('Files that are shipped next to index.html, so the app can load them with a relative path: <link rel="stylesheet" href="style.css"> or <script src="script.js">.',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 10),
            if (_projectFiles.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('No project files', style: TextStyle(fontSize: 12, color: Colors.white24))))
            else
              ...List.generate(_projectFiles.length, (i) {
                final f = _projectFiles[i];
                final name = f['name'] as String;
                final size = f['size'] as int;
                final sizeStr = size < 1024 ? '$size B' : '${(size / 1024).toStringAsFixed(0)} KB';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF0A0A14), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.code, size: 16, color: Color(0xFF69F0AE)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, style: const TextStyle(fontSize: 12, color: Colors.white70), overflow: TextOverflow.ellipsis)),
                      Text(sizeStr, style: const TextStyle(fontSize: 11, color: Colors.white30)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _removeProjectFile(name),
                        child: const Icon(Icons.close, size: 16, color: Color(0xFFFF6B6B)),
                      ),
                    ]),
                  ),
                );
              }),
            const SizedBox(height: 8),
            h.buildActionButton(label: '+ Add project file', icon: Icons.add, secondary: true, onPressed: _addProjectFile),
          ]),
        ),
      ],

      // App Files — optional bundled data files (databases, JSON, images, etc.)
      if (_editingId != null) ...[
        const SizedBox(height: 6),
        _section(
          'App Files${_bundleFiles.isNotEmpty ? ' (${_bundleFiles.length} file${_bundleFiles.length == 1 ? '' : 's'}, ${_bundleTotalSize()})' : ''}',
          _bundleExpanded,
          () { setState(() => _bundleExpanded = !_bundleExpanded); if (_bundleExpanded && _bundleFiles.isEmpty) _loadBundleFiles(); },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            const Text('Add files to bundle into the APK (databases, JSON, images). Accessible via iappyx.storage.readAsset() or extractAsset() at runtime.',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 10),
            if (_bundleFiles.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('No files added', style: TextStyle(fontSize: 12, color: Colors.white24))))
            else
              ...List.generate(_bundleFiles.length, (i) {
                final f = _bundleFiles[i];
                final name = f['name'] as String;
                final size = f['size'] as int;
                final sizeStr = size < 1024 ? '$size B' : size < 1024 * 1024 ? '${(size / 1024).toStringAsFixed(0)} KB' : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF0A0A14), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.insert_drive_file, size: 16, color: Color(0xFF4FC3F7)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, style: const TextStyle(fontSize: 12, color: Colors.white70), overflow: TextOverflow.ellipsis)),
                      Text(sizeStr, style: const TextStyle(fontSize: 11, color: Colors.white30)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _removeBundleFile(name),
                        child: const Icon(Icons.close, size: 16, color: Color(0xFFFF6B6B)),
                      ),
                    ]),
                  ),
                );
              }),
            const SizedBox(height: 8),
            h.buildActionButton(label: '+ Add file', icon: Icons.add, secondary: true, onPressed: _addBundleFile),
            if (_bundleFiles.fold<int>(0, (sum, f) => sum + (f['size'] as int)) > 10 * 1024 * 1024)
              const Padding(padding: EdgeInsets.only(top: 6),
                child: Text('Large bundles increase APK size (files are stored uncompressed in the APK).',
                  style: TextStyle(fontSize: 10, color: Color(0xFFFF8A65)))),
          ]),
        ),
      ],

      _advancedSettings(),

      // Section: Preview & Build (both flows)
      if (_htmlController.text.trim().startsWith('<') || _selectedHtml != null || _selectedDemoId != null) ...[
        const SizedBox(height: 10),
        _section('Preview & Build', true, () {},
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            const Text('Preview runs the app in a test environment. Save & Build creates an installable APK on your device.',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 8),
            _bridgeWarningCard(),
            h.buildActionButton(label: 'Preview', icon: Icons.visibility, onPressed: (_htmlController.text.trim().isEmpty && _selectedDemoId == null) ? null : () async {
              var html = _htmlController.text.trim();
              if (html.isEmpty && _selectedDemoId != null) {
                // A demo has no HTML in the editor - take the one the build uses.
                html = await Generator.getPresetHtml(
                  templateId: _selectedDemoId!,
                  label: _nameController.text.trim(),
                );
                if (html.isEmpty) {
                  _snack('This demo could not be loaded for the preview.');
                  return;
                }
              }
              final issues = await _lintBridge(html);
              // Project files are inlined so the preview matches the built app.
              final projectFiles = _editingId != null
                  ? await ProjectStore.readProject(appId: _editingId!, packageName: _existingPackageName)
                  : const <String, String>{};
              if (!mounted) return;
              setState(() => _bridgeIssues = issues);
              Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(
                htmlContent: html,
                projectFiles: projectFiles,
                initialWarnings: issues.map((issue) => issue.consoleLine).toList(),
                onHtmlFixed: (fixed) {
                  if (!mounted) return;
                  _htmlController.text = fixed;
                  setState(() {});
                },
              )));
            }),
            const SizedBox(height: 10),
            h.buildActionButton(label: 'Save & Build APK', icon: Icons.build, onPressed: _isBuilding ? null : _buildAiApp, secondary: true),
          ]),
        ),
      ],
    ]);
  }

  /// The AI / Manual switch. The active option is clearly highlighted: the
  /// primary color, a bright border and a check mark. The inactive one is
  /// dimmed, so the current mode is never in doubt.
  Widget _genButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required bool selected,
    required VoidCallback onTap,
    bool warning = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F3460) : const Color(0xFF14141F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF4FC3F7)
                : (warning ? const Color(0xFFFFB86B) : Colors.white12),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [const BoxShadow(color: Color(0x334FC3F7), blurRadius: 10)]
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: selected ? const Color(0xFF4FC3F7) : Colors.white38),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? Colors.white : Colors.white54)),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 15, color: Color(0xFF4FC3F7))
            else if (warning)
              const Icon(Icons.error_outline, size: 15, color: Color(0xFFFFB86B)),
          ]),
          const SizedBox(height: 3),
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 10,
              color: selected
                  ? Colors.white70
                  : (warning ? const Color(0xFFFFB86B) : Colors.white24),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _generatingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 1)),
        builder: (context, _) {
          final elapsed = _genStartTime != null
              ? DateTime.now().difference(_genStartTime!).inSeconds
              : 0;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7))),
              const SizedBox(width: 10),
              Text('Generating... ${elapsed}s',
                  style: const TextStyle(fontSize: 12, color: Colors.white38)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  _genId++;
                  _aiGenerating = false;
                  _genStartTime = null;
                }),
                child: const Text('Cancel', style: TextStyle(fontSize: 12, color: Color(0xFFFF6B6B))),
              ),
            ]),
            if (elapsed > 60)
              const Padding(
                padding: EdgeInsets.only(left: 26, top: 6),
                child: Text('Taking longer than usual. You can cancel and try again.',
                  style: TextStyle(fontSize: 11, color: Colors.white24)),
              ),
          ]);
        },
      ),
    );
  }

  Widget _chatBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    final isHtml = !isUser && msg.content.trim().startsWith('<');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFF0F3460) : const Color(0xFF0A0A14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(isUser ? 'You' : 'AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: isUser ? const Color(0xFF4FC3F7) : const Color(0xFF69F0AE))),
          const Spacer(),
          if (isHtml)
            GestureDetector(
              onTap: () => _useThisHtml(msg.content),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _selectedHtml == msg.content ? const Color(0xFF1B5E20) : const Color(0xFF0F3460),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_selectedHtml == msg.content) const Icon(Icons.check, size: 12, color: Color(0xFF69F0AE)),
                  if (_selectedHtml == msg.content) const SizedBox(width: 4),
                  Text(_selectedHtml == msg.content ? 'Selected' : 'Use This',
                    style: TextStyle(fontSize: 11, color: _selectedHtml == msg.content ? const Color(0xFF69F0AE) : const Color(0xFF4FC3F7))),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        if (isHtml)
          Text('HTML response (${(msg.content.length / 1024).toStringAsFixed(1)} KB)',
            style: const TextStyle(fontSize: 11, color: Colors.white24))
        else
          Text(msg.content, style: const TextStyle(fontSize: 13, color: Colors.white70)),
      ]),
    );
  }


  // ── Demo ──
  Widget _demoCard((String, String, String, String) t) {
    final sel = _selectedDemoId == t.$1;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedDemoId = t.$1;
        if (_nameController.text.isEmpty || [...h.starterTemplates, ...h.demoTemplates].any((x) => x.$3 == _nameController.text)) _nameController.text = t.$3;
        _iconConfig = IconConfig(bgColor: IconConfig.colorForString(t.$2), elements: [IconElement(content: t.$2)]);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF0F3460) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? const Color(0xFF4FC3F7) : Colors.transparent, width: 1.5),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(t.$2, style: const TextStyle(fontSize: 20)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.$3, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: sel ? Colors.white : Colors.white70)),
            Text(t.$4, style: const TextStyle(fontSize: 9, color: Colors.white38)),
          ]),
        ]),
      ),
    );
  }

  Widget _demoFields() {
    final widgets = <Widget>[
      const Text('Select a demo', style: TextStyle(fontSize: 13, color: Colors.white54)),
      const SizedBox(height: 8),
      TextField(
        controller: _demoFilterController,
        onChanged: (v) => setState(() {
          _demoFilter = v.trim().toLowerCase();
          // Clear selection if the selected demo is no longer visible under the filter.
          // Avoids the "Build X" action referring to a hidden card.
          if (_selectedDemoId != null && _demoFilter.isNotEmpty) {
            final stillVisible = [...h.starterTemplates, ...h.demoTemplates].any((t) =>
              t.$1 == _selectedDemoId && (
                t.$1.toLowerCase().contains(_demoFilter) ||
                t.$3.toLowerCase().contains(_demoFilter) ||
                t.$4.toLowerCase().contains(_demoFilter)
              ));
            if (!stillVisible) _selectedDemoId = null;
          }
        }),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Filter demos…',
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
          suffixIcon: _demoFilter.isEmpty ? null : IconButton(
            icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
            onPressed: () {
              _demoFilterController.clear();
              setState(() => _demoFilter = '');
            },
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      const SizedBox(height: 12),
    ];

    final q = _demoFilter;
    if (q.isEmpty) {
      // Full grid with section headers (original layout)
      final items = [...h.starterTemplates, ...h.demoTemplates];
      int i = 0;
      while (i < items.length) {
        final t = items[i];
        if (t.$1.isEmpty) {
          widgets.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 8),
            child: Text(t.$3, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white38)),
          ));
          i++;
        } else if (i + 1 < items.length && items[i + 1].$1.isNotEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: SizedBox(height: 80, child: _demoCard(t))),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 80, child: _demoCard(items[i + 1]))),
            ]),
          ));
          i += 2;
        } else {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: SizedBox(height: 80, child: _demoCard(t))),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
            ]),
          ));
          i++;
        }
      }
    } else {
      // Filtered: flat pair grid, no section headers, match on id/name/description
      final matches = [...h.starterTemplates, ...h.demoTemplates].where((t) =>
        t.$1.isNotEmpty && (
          t.$1.toLowerCase().contains(q) ||
          t.$3.toLowerCase().contains(q) ||
          t.$4.toLowerCase().contains(q)
        )
      ).toList();
      if (matches.isEmpty) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No demos match', style: TextStyle(color: Colors.white38, fontSize: 13))),
        ));
      } else {
        for (int j = 0; j < matches.length; j += 2) {
          final left = matches[j];
          final right = j + 1 < matches.length ? matches[j + 1] : null;
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: SizedBox(height: 80, child: _demoCard(left))),
              const SizedBox(width: 8),
              right == null
                ? const Expanded(child: SizedBox())
                : Expanded(child: SizedBox(height: 80, child: _demoCard(right))),
            ]),
          ));
        }
      }
    }
    if (_selectedDemoId != null) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(h.buildActionButton(
        label: 'Build ${[...h.starterTemplates, ...h.demoTemplates].where((t) => t.$1 == _selectedDemoId).firstOrNull?.$3 ?? 'App'}',
        onPressed: _isBuilding ? null : _buildDemo, icon: Icons.rocket_launch));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  // ── Building ──
  Widget _buildingView() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (!_isBuilding)
          GestureDetector(
            onTap: () => setState(() { _showBuildLog = false; _log.clear(); }),
            child: Container(
              width: 38, height: 38, margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_back, size: 18, color: Colors.white54),
            ),
          ),
        Expanded(child: _appHeader(_isBuilding ? 'Building...' : 'Build Complete')),
      ]),
      const SizedBox(height: 24),
      if (_isBuilding && _log.isEmpty) const LinearProgressIndicator(color: Color(0xFF4FC3F7), backgroundColor: Color(0xFF1A1A2E)),
      BuildLog(log: _log),
      if (!_isBuilding && _log.isNotEmpty) ...[
        const SizedBox(height: 24),
        h.buildActionButton(label: 'View in My Apps', onPressed: widget.onViewMyApps, icon: Icons.folder_outlined),
        const SizedBox(height: 12),
        h.buildActionButton(label: 'Keep Editing', onPressed: () => setState(() { _showBuildLog = false; _log.clear(); }), icon: Icons.edit, secondary: true),
        const SizedBox(height: 12),
        h.buildActionButton(label: 'Create New App', onPressed: _reset, secondary: true),
      ],
    ]),
  );

  // ── Shared widgets ──
  Widget _appHeader(String sub) => Row(children: [
    Container(width: 44, height: 44,
      decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/ic_launcher.png', width: 44, height: 44))),
    const SizedBox(width: 12),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Applix', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white38)),
    ]),
  ]);

  Widget _section(String title, bool expanded, VoidCallback onToggle, {required Widget child, bool done = false}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              done ? const Icon(Icons.check_circle, size: 18, color: Color(0xFF69F0AE))
                   : Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.white38),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
        if (expanded) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child),
      ]),
    );
  }
}

// ── Provider Setup Page ──

class ProviderSetupPage extends StatefulWidget {
  final AiProvider provider;
  const ProviderSetupPage({required this.provider});
  @override
  State<ProviderSetupPage> createState() => ProviderSetupPageState();
}

class ProviderSetupPageState extends State<ProviderSetupPage> {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelIdController;
  final _searchController = TextEditingController();
  late AiProvider _provider;
  List<AiModel> _models = [];
  String _searchQuery = '';
  bool _loading = false;
  String? _error;
  String? _notice; // "API key saved" / "could not store the key"
  bool _keyStored = true;

  @override
  void initState() {
    super.initState();
    _provider = AiProvider(
      id: widget.provider.id, name: widget.provider.name, baseUrl: widget.provider.baseUrl,
      apiKey: widget.provider.apiKey, selectedModel: widget.provider.selectedModel,
      models: List.from(widget.provider.models),
    );
    _keyController = TextEditingController(text: _provider.apiKey);
    _baseUrlController = TextEditingController(text: _provider.baseUrl);
    _modelIdController = TextEditingController(text: _provider.selectedModel);
    _models = List.from(_provider.models);
    // Auto-fetch OpenRouter (public) and custom servers with a URL.
    if (_provider.id == 'openrouter' && _models.isEmpty) _fetchModels();
    if (_provider.id == 'openai_compatible' && _provider.baseUrl.isNotEmpty) _fetchModels();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelIdController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    final isCustom = _provider.id == 'openai_compatible';
    // OpenRouter models are public; custom servers only need a URL.
    if (isCustom) {
      if (_baseUrlController.text.trim().isEmpty) {
        setState(() => _error = 'Enter the Base URL first');
        return;
      }
    } else if (_provider.id != 'openrouter' && _keyController.text.trim().isEmpty) {
      return;
    }
    // Save first: the key has to be stored even when the user only taps
    // refresh, and the request must use the key that is currently typed.
    await _autoSave();
    final apiKey = _keyController.text.trim();
    setState(() { _loading = true; _error = null; });
    try {
      if (_provider.id == 'anthropic') {
        _models = await AiService.fetchAnthropicModels(apiKey);
      } else if (_provider.id == 'openrouter') {
        _models = await AiService.fetchOpenRouterModels(apiKey);
      } else if (isCustom) {
        _provider.baseUrl = _baseUrlController.text.trim();
        _models = await AiService.fetchOpenAICompatibleModels(_provider.baseUrl, apiKey);
      }
      if (_models.isEmpty) {
        _models = _standardModels(isCustom);
        if (mounted) {
          setState(() {
            _loading = false;
            _notice = 'The server returned no model list - showing the usual local models. '
                'You can also type any model ID above.';
          });
        }
        return;
      }
      if (mounted) setState(() { _loading = false; _notice = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the model list: $e';
      });
      // Keep whatever we know and offer the standard models as a fallback.
      if (_models.isEmpty) _models = _standardModels(isCustom);
    }
  }

  /// Fallback list for servers that do not expose /models (or fail to answer).
  List<AiModel> _standardModels(bool isCustom) {
    final ids = isCustom
        ? const [
            'llama3.2', 'llama3.1', 'qwen2.5', 'qwen3', 'mistral', 'gemma3',
            'phi4', 'deepseek-r1', 'command-r', 'gpt-4o-mini', 'gpt-4o',
          ]
        : const [
            'claude-sonnet-4-20250514', 'claude-3-5-haiku-20241022',
            'gpt-4o', 'gpt-4o-mini',
          ];
    return ids.map((id) => AiModel(id: id, name: id)).toList();
  }

  /// Persists the provider. The key goes into the encrypted store; when that
  /// is not available the user is told instead of silently losing the key.
  Future<bool> _autoSave() async {
    _provider.baseUrl = _baseUrlController.text.trim();
    _provider.apiKey = _keyController.text.trim();
    _provider.selectedModel = _modelIdController.text.trim();
    final stored = await Settings.updateProvider(_provider);
    final activeStored = await Settings.setActiveProvider(_provider);
    final ok = stored && activeStored;
    if (mounted) {
      setState(() {
        _keyStored = ok;
        _notice = ok
            ? (_provider.apiKey.isEmpty ? 'Settings saved.' : 'API key saved.')
            : 'The API key could NOT be stored securely on this device. '
                'It stays only for this session.';
      });
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    // canPop: false - the page saves the provider itself and pops with it, so
    // the caller always receives the configured provider (also when the user
    // leaves with the system back gesture).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _autoSave();
        if (!mounted) return;
        Navigator.pop(context, _provider);
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        title: Text(_provider.name, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _autoSave();
            if (!mounted) return;
            Navigator.pop(context, _provider);
          },
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _autoSave();
              if (!mounted) return;
              Navigator.pop(context, _provider);
            },
            child: const Text('Save',
                style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_provider.id == 'openai_compatible') ...[
            const Text('Base URL', style: TextStyle(fontSize: 13, color: Colors.white54)),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlController,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'http://192.168.1.20:11434/v1',
                filled: true, fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onEditingComplete: () { _autoSave(); _fetchModels(); },
            ),
            const SizedBox(height: 6),
            const Text('Server root or /v1 endpoint. Works with Ollama, LM Studio and vLLM.',
                style: TextStyle(fontSize: 10, color: Colors.white30)),
            const SizedBox(height: 20),
          ],
          Text(_provider.id == 'openai_compatible' ? 'API Key (optional)' : 'API Key',
              style: const TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: _keyController,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              obscureText: true,
              decoration: InputDecoration(
                hintText: _provider.id == 'anthropic'
                    ? 'sk-ant-...'
                    : _provider.id == 'openai_compatible'
                        ? 'Leave empty if not required'
                        : 'sk-or-...',
                filled: true, fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onEditingComplete: () { _autoSave(); _fetchModels(); },
            )),
            ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loading ? null : _fetchModels,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFF0F3460), borderRadius: BorderRadius.circular(10)),
                  child: _loading
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4FC3F7)))
                      : const Icon(Icons.refresh, size: 18, color: Color(0xFF4FC3F7)),
                ),
              ),
            ],
          ]),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFFF6B6B))),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(_keyStored ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 13, color: _keyStored ? const Color(0xFF69F0AE) : const Color(0xFFFFB86B)),
              const SizedBox(width: 6),
              Expanded(child: Text(_notice!,
                  style: TextStyle(fontSize: 11, color: _keyStored ? const Color(0xFF69F0AE) : const Color(0xFFFFB86B)))),
            ]),
          ],

          const SizedBox(height: 20),
          const Text('Model', style: TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 8),

          if (_provider.id == 'openai_compatible') ...[
            TextField(
              controller: _modelIdController,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Model ID, e.g. llama3.2',
                filled: true, fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (v) => _provider.selectedModel = v.trim(),
              onEditingComplete: () { _autoSave(); },
            ),
            const SizedBox(height: 8),
          ],

          if (_models.length > 10)
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search models...',
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white24),
                filled: true, fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          if (_models.length > 10) const SizedBox(height: 8),

          if (_models.isEmpty)
            GestureDetector(
              onTap: _fetchModels,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(10)),
                child: Text(
                    _provider.id == 'openai_compatible'
                        ? 'Tap to load models, or enter a Model ID above'
                        : 'Enter API key and tap refresh to load models',
                    style: const TextStyle(fontSize: 12, color: Colors.white38), textAlign: TextAlign.center),
              ),
            )
          else
            ...(_models.where((m) => _searchQuery.isEmpty || m.name.toLowerCase().contains(_searchQuery) || m.id.toLowerCase().contains(_searchQuery)).map((m) {
              final selected = _provider.selectedModel == m.id;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _provider.selectedModel = m.id;
                    _modelIdController.text = m.id;
                  });
                  _autoSave();
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF0F3460) : const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? const Color(0xFF4FC3F7) : Colors.transparent),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.white70)),
                      if (m.description != null)
                        Text(m.description!, style: const TextStyle(fontSize: 10, color: Colors.white38)),
                      if (m.contextLength != null || m.pricePer1mTokens != null)
                        Text(
                          [
                            if (m.contextLength != null) '${(m.contextLength! / 1000).round()}K ctx',
                            if (m.pricePer1mTokens != null) '\$${m.pricePer1mTokens!.toStringAsFixed(2)}/1M tokens',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 9, color: Colors.white24),
                        ),
                    ])),
                    if (selected)
                      const Icon(Icons.check_circle, size: 18, color: Color(0xFF4FC3F7)),
                  ]),
                ),
              );
            })),

          const SizedBox(height: 40),
        ]),
      ),
    ),
    );
  }
}

