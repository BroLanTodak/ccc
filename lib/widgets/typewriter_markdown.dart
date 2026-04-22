import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

/// Markdown text that types out character-by-character like a terminal.
/// After animation completes, renders full MarkdownBody for proper formatting.
class TypewriterMarkdown extends StatefulWidget {
  final String data;
  final bool animate; // false = render instantly (for replayed/old messages)
  final int charsPerTick;
  final Duration tickInterval;
  final VoidCallback? onComplete;

  const TypewriterMarkdown({
    super.key,
    required this.data,
    this.animate = true,
    this.charsPerTick = 3,
    this.tickInterval = const Duration(milliseconds: 12),
    this.onComplete,
  });

  @override
  State<TypewriterMarkdown> createState() => _TypewriterMarkdownState();
}

class _TypewriterMarkdownState extends State<TypewriterMarkdown> {
  int _visibleChars = 0;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (!widget.animate || widget.data.isEmpty) {
      _done = true;
      _visibleChars = widget.data.length;
    } else {
      _startTyping();
    }
  }

  void _startTyping() {
    _timer = Timer.periodic(widget.tickInterval, (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _visibleChars += widget.charsPerTick;
        if (_visibleChars >= widget.data.length) {
          _visibleChars = widget.data.length;
          _done = true;
          t.cancel();
          widget.onComplete?.call();
        }
      });
    });
  }

  @override
  void didUpdateWidget(TypewriterMarkdown old) {
    super.didUpdateWidget(old);
    // If data changed (e.g. streaming append), keep typing
    if (widget.data != old.data && _done) {
      _done = false;
      _startTyping();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  MarkdownStyleSheet _buildMdStyle() => MarkdownStyleSheet(
    p: HackerTheme.monoNoGlow(size: 12, color: HackerTheme.green),
    h1: HackerTheme.mono(size: 16, color: HackerTheme.cyan),
    h2: HackerTheme.mono(size: 14, color: HackerTheme.cyan),
    h3: HackerTheme.mono(size: 13, color: HackerTheme.cyan),
    h4: HackerTheme.mono(size: 12, color: HackerTheme.cyan),
    code: HackerTheme.monoNoGlow(size: 11, color: HackerTheme.amber).copyWith(backgroundColor: HackerTheme.bgCard),
    codeblockDecoration: BoxDecoration(color: HackerTheme.bgCard, border: Border.all(color: HackerTheme.borderDim)),
    codeblockPadding: const EdgeInsets.all(10),
    listBullet: HackerTheme.monoNoGlow(size: 12, color: HackerTheme.green),
    strong: HackerTheme.monoNoGlow(size: 12, color: HackerTheme.white),
    em: HackerTheme.monoNoGlow(size: 12, color: HackerTheme.cyan),
    a: HackerTheme.monoNoGlow(size: 12, color: HackerTheme.cyan).copyWith(decoration: TextDecoration.underline, decorationColor: HackerTheme.cyan),
    blockquoteDecoration: BoxDecoration(color: HackerTheme.bgCard, border: const Border(left: BorderSide(color: HackerTheme.green, width: 3))),
    blockquotePadding: const EdgeInsets.all(8),
    tableBorder: TableBorder.all(color: HackerTheme.borderDim),
    tableHead: HackerTheme.mono(size: 10, color: HackerTheme.cyan),
    tableBody: HackerTheme.monoNoGlow(size: 10, color: HackerTheme.green),
    tableCellsDecoration: const BoxDecoration(color: HackerTheme.bgCard),
    horizontalRuleDecoration: const BoxDecoration(border: Border(top: BorderSide(color: HackerTheme.borderDim))),
  );

  @override
  Widget build(BuildContext context) {
    final text = widget.data.substring(0, _visibleChars);

    return MarkdownBody(
      data: _done ? text : '$text▌',
      selectable: _done,
      onTapLink: (_, href, __) {
        if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
      styleSheet: _buildMdStyle(),
    );
  }
}
