import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../theme.dart';

/// Custom builder for fenced code blocks (`pre` tag).
class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  CodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;

    // Extract language from child <code> element's class attribute
    String? lang;
    if (element.children != null) {
      for (final child in element.children!) {
        if (child is md.Element && child.attributes.containsKey('class')) {
          final cls = child.attributes['class'] ?? '';
          if (cls.startsWith('language-')) lang = cls.substring(9);
        }
      }
    }

    return _CodeBlockWithCopy(code: code, language: lang);
  }
}

class _CodeBlockWithCopy extends StatefulWidget {
  final String code;
  final String? language;
  const _CodeBlockWithCopy({required this.code, this.language});

  @override
  State<_CodeBlockWithCopy> createState() => _CodeBlockWithCopyState();
}

class _CodeBlockWithCopyState extends State<_CodeBlockWithCopy> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: HackerTheme.bgCard,
        border: Border.all(color: HackerTheme.borderDim),
      ),
      child: Column(children: [
        // Header with language label + copy button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: const BoxDecoration(
            color: Color(0xFF0A1A0A),
            border: Border(bottom: BorderSide(color: HackerTheme.borderDim)),
          ),
          child: Row(children: [
            if (widget.language != null)
              Text(widget.language!.toUpperCase(),
                style: HackerTheme.monoNoGlow(size: 9, color: HackerTheme.dimText)),
            const Spacer(),
            InkWell(
              onTap: _copy,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_copied ? Icons.check : Icons.copy, size: 11,
                  color: _copied ? HackerTheme.green : HackerTheme.dimText),
                const SizedBox(width: 3),
                Text(_copied ? 'COPIED' : 'COPY',
                  style: HackerTheme.monoNoGlow(size: 9,
                    color: _copied ? HackerTheme.green : HackerTheme.dimText)),
              ]),
            ),
          ]),
        ),
        // Code content
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          child: SelectableText(
            widget.code,
            style: HackerTheme.monoNoGlow(size: 11, color: HackerTheme.amber),
          ),
        ),
      ]),
    );
  }
}
