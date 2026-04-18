import 'package:flutter/material.dart';
import '../theme.dart';

class TerminalCard extends StatelessWidget {
  final Widget child;
  final bool active;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  const TerminalCard({
    super.key,
    required this.child,
    this.active = false,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: padding ?? const EdgeInsets.all(14),
            decoration: HackerTheme.terminalBox(active: active),
            child: child,
          ),
          // Corner markers like OmniAgent
          Positioned(top: -8, left: -4,
            child: Text('+', style: TextStyle(color: HackerTheme.green, fontSize: 14, fontFamily: 'Courier New', fontWeight: FontWeight.bold,
              shadows: [Shadow(color: HackerTheme.greenGlow, blurRadius: 5)]))),
          Positioned(bottom: -10, right: -4,
            child: Text('+', style: TextStyle(color: HackerTheme.green, fontSize: 14, fontFamily: 'Courier New', fontWeight: FontWeight.bold,
              shadows: [Shadow(color: HackerTheme.greenGlow, blurRadius: 5)]))),
        ],
      ),
    );
  }
}
