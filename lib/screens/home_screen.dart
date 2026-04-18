import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';
import '../widgets/scanline_overlay.dart';
import '../widgets/terminal_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final WsService _ws = WsService();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _promptFocus = FocusNode();

  List<dynamic> _sessions = [];
  String? _activeSessionId;
  String _serverStatus = 'CONNECTING...';
  bool _serverOnline = false;
  final List<Map<String, dynamic>> _events = [];
  bool _isLoading = false;
  bool _isProcessing = false;
  bool _sidebarOpen = false;
  StreamSubscription? _wsSub;
  late AnimationController _cursorController;
  Timer? _sessionRefreshTimer;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    _init();
    _sessionRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadSessions());
  }

  Future<void> _init() async {
    try {
      await ApiService.health();
      setState(() { _serverStatus = 'ONLINE'; _serverOnline = true; });
    } catch (e) {
      setState(() { _serverStatus = 'OFFLINE'; _serverOnline = false; });
    }
    await _loadSessions();
    _ws.connect();
    _wsSub = _ws.events.listen(_onWsEvent);
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'] ?? '';
    if (type == 'status') {
      setState(() => _isProcessing = event['content'] == 'processing');
      if (event['content'] == 'ready') _loadSessions();
      return;
    }
    if (type == 'replay') {
      final replayEvents = (event['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() => _events.addAll(replayEvents.where((e) => e['type'] != 'status')));
    } else if (type == 'error' && (event['content'] ?? '').toString().contains('still processing')) {
      setState(() => _events.add({'type': 'system', 'content': 'Claude is still thinking... please wait.'}));
    } else {
      setState(() {
        _events.add(event);
        if (type == 'assistant_text') _isProcessing = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _loadSessions() async {
    try {
      final s = await ApiService.listSessions();
      if (mounted) setState(() => _sessions = s);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  bool _isMobile(BuildContext context) => MediaQuery.of(context).size.width < 768;

  Future<void> _createSession() async {
    final nameCtl = TextEditingController();
    final dirCtl = TextEditingController(text: '/home/lanccc');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: HackerTheme.bgPanel,
        shape: RoundedRectangleBorder(side: const BorderSide(color: HackerTheme.green)),
        child: Container(
          padding: const EdgeInsets.all(20), constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('[ NEW SESSION ]', style: HackerTheme.mono(size: 16)),
            const SizedBox(height: 16), _buildInput('SESSION_NAME', nameCtl),
            const SizedBox(height: 12), _buildInput('PROJECT_DIR', dirCtl),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _buildBtn('CANCEL', onTap: () => Navigator.pop(ctx), primary: false),
              const SizedBox(width: 8),
              _buildBtn('CREATE', onTap: () => Navigator.pop(ctx, {'name': nameCtl.text, 'dir': dirCtl.text})),
            ]),
          ]),
        ),
      ),
    );
    if (result != null && result['name']!.isNotEmpty) {
      await ApiService.createSession(result['name']!, result['dir']!);
      await _loadSessions();
    }
  }

  Widget _buildInput(String label, TextEditingController c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: HackerTheme.mono(size: 10)), const SizedBox(height: 4),
      TextField(controller: c, style: HackerTheme.monoNoGlow(size: 14, color: HackerTheme.green), cursorColor: HackerTheme.green,
        decoration: InputDecoration(filled: true, fillColor: HackerTheme.bg, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: HackerTheme.borderDim), borderRadius: BorderRadius.zero),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: HackerTheme.green), borderRadius: BorderRadius.zero))),
    ]);
  }

  Widget _buildBtn(String t, {required VoidCallback onTap, bool primary = true}) {
    return InkWell(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: primary ? HackerTheme.green : HackerTheme.bgPanel, border: Border.all(color: HackerTheme.green)),
      child: Text(t, style: HackerTheme.monoNoGlow(size: 12, color: primary ? Colors.black : HackerTheme.green))));
  }

  Future<void> _selectSession(String id) async {
    if (_activeSessionId != null) _ws.unsubscribe();
    setState(() { _activeSessionId = id; _events.clear(); _sidebarOpen = false; _isProcessing = false; });
    _ws.subscribe(id);
  }

  Future<void> _startSession(String id) async {
    setState(() => _isLoading = true);
    try { await ApiService.startSession(id); await _loadSessions(); _selectSession(id); } catch (e) { _events.add({'type': 'system', 'content': 'ERROR: $e'}); }
    setState(() => _isLoading = false);
  }

  Future<void> _stopSession(String id) async {
    try { await ApiService.stopSession(id); await _loadSessions(); setState(() => _isProcessing = false); } catch (_) {}
  }

  void _sendPrompt() {
    final text = _promptController.text.trim();
    if (text.isEmpty || _activeSessionId == null || _isProcessing) return;
    _ws.sendPrompt(_activeSessionId!, text);
    _promptController.clear();
    _promptFocus.requestFocus();
    setState(() => _isProcessing = true);
  }

  @override
  void dispose() {
    _wsSub?.cancel(); _ws.dispose(); _promptController.dispose(); _scrollController.dispose();
    _promptFocus.dispose(); _cursorController.dispose(); _sessionRefreshTimer?.cancel(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Scaffold(body: ScanlineOverlay(child: Column(children: [
      _buildTopBar(mobile),
      Expanded(child: Stack(children: [
        Row(children: [if (!mobile) _buildSidebar(), Expanded(child: _buildTerminalView())]),
        if (mobile && _sidebarOpen) ...[
          GestureDetector(onTap: () => setState(() => _sidebarOpen = false), child: Container(color: Colors.black54)),
          _buildSidebar(mobile: true),
        ],
      ])),
      if (_isProcessing) _buildProcessingBar(),
      _buildInputBar(),
    ])));
  }

  Widget _buildTopBar(bool mobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: HackerTheme.bgPanel, border: const Border(bottom: BorderSide(color: HackerTheme.borderDim, width: 1))),
      child: Row(children: [
        if (mobile) InkWell(onTap: () => setState(() => _sidebarOpen = !_sidebarOpen),
          child: Padding(padding: const EdgeInsets.only(right: 10), child: Text('[\u2630]', style: HackerTheme.mono(size: 16)))),
        Text('LAN CCC', style: HackerTheme.mono(size: 13)), const SizedBox(width: 6),
        Text('///', style: HackerTheme.mono(size: 10, color: HackerTheme.borderDim)), const SizedBox(width: 6),
        Container(width: 6, height: 6, decoration: BoxDecoration(color: _serverOnline ? HackerTheme.green : HackerTheme.red, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: _serverOnline ? HackerTheme.greenGlow : const Color(0x99FF003C), blurRadius: 6)])),
        const SizedBox(width: 6),
        Text(_serverStatus, style: HackerTheme.mono(size: 10, color: _serverOnline ? HackerTheme.green : HackerTheme.red)),
        const Spacer(),
        if (_activeSessionId != null) ...[
          Builder(builder: (_) {
            final s = _sessions.firstWhere((s) => s['id'] == _activeSessionId, orElse: () => null);
            return s == null ? const SizedBox() : Text('[ ${s['name']} ]', style: HackerTheme.mono(size: 10, color: HackerTheme.dimText));
          }),
          const SizedBox(width: 8),
        ],
        AnimatedBuilder(animation: _cursorController, builder: (_, __) => Container(width: 8, height: 14,
          color: _cursorController.value < 0.5 ? HackerTheme.green : Colors.transparent)),
      ]),
    );
  }

  Widget _buildSidebar({bool mobile = false}) {
    return Container(
      width: mobile ? 260 : 220,
      decoration: BoxDecoration(color: HackerTheme.bgPanel, border: const Border(right: BorderSide(color: HackerTheme.green, width: 1)),
        boxShadow: mobile ? [BoxShadow(color: HackerTheme.greenDim, blurRadius: 20)] : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: HackerTheme.borderDim))),
          child: Text('SESSIONS', style: HackerTheme.mono(size: 11))),
        Expanded(child: ListView.builder(itemCount: _sessions.length, itemBuilder: (_, i) => _buildSessionTile(_sessions[i]))),
        Padding(padding: const EdgeInsets.all(8), child: InkWell(onTap: _createSession,
          child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(border: Border.all(color: HackerTheme.green)),
            child: Center(child: Text('[ + NEW SESSION ]', style: HackerTheme.mono(size: 12)))))),
      ]),
    );
  }

  Widget _buildSessionTile(dynamic session) {
    final id = session['id'] as String, name = session['name'] as String, status = session['status'] as String;
    final isActive = id == _activeSessionId, isRunning = status == 'active';
    return InkWell(onTap: () => _selectSession(id), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: isActive ? HackerTheme.greenDim : Colors.transparent,
        border: Border(left: BorderSide(color: isActive ? HackerTheme.green : Colors.transparent, width: 2),
          bottom: const BorderSide(color: HackerTheme.borderDim, width: 0.5))),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(
          color: isRunning ? HackerTheme.green : Colors.transparent,
          border: Border.all(color: isRunning ? HackerTheme.green : HackerTheme.grey), shape: BoxShape.circle,
          boxShadow: isRunning ? [BoxShadow(color: HackerTheme.greenGlow, blurRadius: 6)] : null)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.toUpperCase(), style: HackerTheme.mono(size: 12, color: isActive ? HackerTheme.green : HackerTheme.dimText)),
          Row(children: [
            Text(session['project_dir'] ?? '/home/lanccc', style: HackerTheme.monoNoGlow(size: 9, color: HackerTheme.dimText)),
            if (isActive && _isProcessing) ...[const SizedBox(width: 6),
              SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1, color: HackerTheme.amber))],
          ]),
        ])),
        if (isActive && !isRunning) InkWell(onTap: () => _startSession(id), child: Container(padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(border: Border.all(color: HackerTheme.green)), child: Text('\u25B6', style: HackerTheme.mono(size: 10)))),
        if (isActive && isRunning) InkWell(onTap: () => _stopSession(id), child: Container(padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(border: Border.all(color: HackerTheme.red)), child: Text('\u25A0', style: HackerTheme.mono(size: 10, color: HackerTheme.red)))),
      ]),
    ));
  }

  Widget _buildProcessingBar() {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), color: HackerTheme.bgCard,
      child: Row(children: [
        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: HackerTheme.green)),
        const SizedBox(width: 10), Text('CLAUDE IS THINKING...', style: HackerTheme.mono(size: 11, color: HackerTheme.amber)),
        const Spacer(),
        AnimatedBuilder(animation: _cursorController, builder: (_, __) {
          final dots = '.' * ((_cursorController.value * 3).floor() + 1);
          return Text(dots, style: HackerTheme.mono(size: 11));
        }),
      ]));
  }

  Widget _buildTerminalView() {
    if (_activeSessionId == null) {
      return Container(color: HackerTheme.bgContent, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('  \u2588\u2588\u2588\u2588\u2588\u2588\u2557  \u2588\u2588\u2588\u2588\u2588\u2588\u2557  \u2588\u2588\u2588\u2588\u2588\u2588\u2557\n'
          ' \u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d \u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d \u2588\u2588\u2554\u2550\u2550\u2550\u2550\u255d\n'
          ' \u2588\u2588\u2551      \u2588\u2588\u2551      \u2588\u2588\u2551     \n'
          ' \u2588\u2588\u2551      \u2588\u2588\u2551      \u2588\u2588\u2551     \n'
          ' \u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2557 \u255a\u2588\u2588\u2588\u2588\u2588\u2588\u2557\n'
          '  \u255a\u2550\u2550\u2550\u2550\u2550\u255d  \u255a\u2550\u2550\u2550\u2550\u2550\u255d  \u255a\u2550\u2550\u2550\u2550\u2550\u255d',
          style: HackerTheme.mono(size: 14), textAlign: TextAlign.center),
        const SizedBox(height: 12), Text('CLAUDE COMMAND CENTER', style: HackerTheme.mono(size: 12, color: HackerTheme.dimText)),
        const SizedBox(height: 24), Text('> SELECT OR CREATE A SESSION TO BEGIN', style: HackerTheme.mono(color: HackerTheme.dimText, size: 11)),
      ])));
    }
    return Container(color: HackerTheme.bgContent, child: _isLoading
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('INITIALIZING...', style: HackerTheme.mono()), const SizedBox(height: 8),
          const SizedBox(width: 200, child: LinearProgressIndicator(backgroundColor: HackerTheme.borderDim, valueColor: AlwaysStoppedAnimation(HackerTheme.green)))]))
      : ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(16), itemCount: _events.length,
          itemBuilder: (_, i) => _buildEventWidget(_events[i])));
  }

  Widget _buildEventWidget(Map<String, dynamic> event) {
    switch (event['type'] ?? '') {
      case 'user_message': return _buildUserMessage(event['content'] ?? '');
      case 'assistant_text': return _buildAssistantMessage(event['content'] ?? '');
      case 'tool_call': return _buildToolCall(event);
      case 'tool_result': return _buildToolResult();
      case 'system': return _buildSystemMessage(event['content'] ?? '');
      case 'session_ended': return _buildSystemMessage('Session terminated [code: ${event['code']}]');
      case 'subscribed': return _buildSystemMessage('LINKED TO SESSION ${(event['sessionId'] ?? '').toString().substring(0, 8)}');
      case 'stderr': final t = event['content'] ?? ''; return t.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: Text(t, style: HackerTheme.monoNoGlow(color: HackerTheme.dimText, size: 10)));
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildUserMessage(String c) => TerminalCard(active: true, margin: const EdgeInsets.symmetric(vertical: 6), padding: const EdgeInsets.all(12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('> ', style: HackerTheme.mono(size: 14)), Expanded(child: SelectableText(c, style: HackerTheme.mono(size: 13)))]));

  Widget _buildAssistantMessage(String c) => Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: SelectableText(c, style: HackerTheme.monoNoGlow(size: 13, color: HackerTheme.green)));

  Widget _buildToolCall(Map<String, dynamic> event) {
    final name = event['name'] ?? '?'; final input = event['input'];
    String detail = '';
    if (input is Map) {
      if (input.containsKey('file_path')) detail = input['file_path'];
      else if (input.containsKey('command')) detail = input['command'];
      else if (input.containsKey('pattern')) detail = input['pattern'];
      else { final s = input.toString(); detail = s.length > 80 ? '${s.substring(0, 80)}...' : s; }
    }
    Color ic; String icon;
    switch (name) {
      case 'Read': icon = '\u2636'; ic = HackerTheme.cyan;
      case 'Edit': case 'Write': icon = '\u270E'; ic = HackerTheme.amber;
      case 'Bash': icon = '\$'; ic = HackerTheme.green;
      case 'Grep': case 'Glob': icon = '\u2315'; ic = HackerTheme.cyan;
      default: icon = '\u2699'; ic = HackerTheme.grey;
    }
    return Container(margin: const EdgeInsets.symmetric(vertical: 3), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: HackerTheme.bgCard, border: Border.all(color: HackerTheme.borderDim)),
      child: Row(children: [Text(icon, style: TextStyle(color: ic, fontSize: 14, fontFamily: 'Courier New')), const SizedBox(width: 8),
        Text(name.toUpperCase(), style: HackerTheme.mono(color: ic, size: 11)), const SizedBox(width: 8),
        Expanded(child: Text(detail, style: HackerTheme.monoNoGlow(color: HackerTheme.dimText, size: 11), overflow: TextOverflow.ellipsis))]));
  }

  Widget _buildToolResult() => Padding(padding: const EdgeInsets.only(left: 36, bottom: 4), child: Text('[OK]', style: HackerTheme.mono(color: HackerTheme.green, size: 10)));
  Widget _buildSystemMessage(String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('[SYS] $t', style: HackerTheme.mono(color: HackerTheme.amber, size: 10)));

  Widget _buildInputBar() {
    final hasSession = _activeSessionId != null;
    final session = hasSession ? _sessions.firstWhere((s) => s['id'] == _activeSessionId, orElse: () => null) : null;
    final isRunning = session?['status'] == 'active';
    final canSend = hasSession && isRunning && !_isProcessing;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: HackerTheme.bgPanel, border: const Border(top: BorderSide(color: HackerTheme.green, width: 1)),
        boxShadow: [BoxShadow(color: HackerTheme.greenDim, blurRadius: 8)]),
      child: Row(children: [
        Text('> ', style: HackerTheme.mono(size: 16)),
        Expanded(child: TextField(controller: _promptController, focusNode: _promptFocus, enabled: canSend,
          style: HackerTheme.monoNoGlow(size: 14, color: HackerTheme.green), cursorColor: HackerTheme.green,
          decoration: InputDecoration(hintText: _isProcessing ? 'WAITING FOR RESPONSE...' : !hasSession ? 'SELECT A SESSION...' : !isRunning ? 'START SESSION FIRST...' : 'ENTER COMMAND...',
            hintStyle: HackerTheme.monoNoGlow(color: _isProcessing ? HackerTheme.amber : HackerTheme.dimText, size: 14),
            border: InputBorder.none, contentPadding: EdgeInsets.zero),
          onSubmitted: (_) => _sendPrompt())),
        const SizedBox(width: 8),
        InkWell(onTap: canSend ? _sendPrompt : null, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: canSend ? HackerTheme.green : HackerTheme.bgCard,
            border: Border.all(color: canSend ? HackerTheme.green : HackerTheme.borderDim),
            boxShadow: canSend ? [BoxShadow(color: HackerTheme.greenGlow, blurRadius: 8)] : null),
          child: Text(_isProcessing ? 'WAIT' : 'SEND', style: HackerTheme.monoNoGlow(size: 12, color: canSend ? Colors.black : HackerTheme.dimText)))),
      ]));
  }
}
