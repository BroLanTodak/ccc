import 'package:flutter/material.dart';
import '../theme.dart';

class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final visible = _controller.value < 0.5;
        return Container(
          width: 10,
          height: 18,
          color: visible ? HackerTheme.green : Colors.transparent,
          margin: const EdgeInsets.only(left: 4),
        );
      },
    );
  }
}
