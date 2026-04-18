import 'package:flutter/material.dart';

class HackerTheme {
  // Core colors - matching OmniAgent
  static const Color bg = Color(0xFF050505);
  static const Color bgPanel = Color(0xFF000000);
  static const Color bgCard = Color(0xFF000000);
  static const Color bgContent = Color(0xFF000A00);
  static const Color border = Color(0xFF00FF41);
  static const Color borderDim = Color(0xFF0A3D10);

  static const Color green = Color(0xFF00FF41);
  static const Color greenDim = Color(0x3300FF41); // 20% opacity
  static const Color greenGlow = Color(0x9900FF41); // 60% opacity
  static const Color cyan = Color(0xFF00D4FF);
  static const Color amber = Color(0xFFFFB700);
  static const Color red = Color(0xFFFF003C);
  static const Color white = Color(0xFFE6EDF3);
  static const Color grey = Color(0xFF7D8590);
  static const Color dimText = Color(0xFF3A5F3A);

  static const String fontFamily = 'Courier New';

  static TextStyle mono({
    double size = 13,
    Color color = green,
    FontWeight weight = FontWeight.bold,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.5,
      shadows: [
        Shadow(color: color.withValues(alpha: 0.6), blurRadius: 5),
      ],
    );
  }

  static TextStyle monoNoGlow({
    double size = 13,
    Color color = green,
    FontWeight weight = FontWeight.bold,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.5,
    );
  }

  static BoxDecoration terminalBox({bool active = false}) {
    return BoxDecoration(
      color: bgCard,
      border: Border.all(color: active ? green : borderDim, width: 1),
      boxShadow: active
          ? [BoxShadow(color: greenGlow, blurRadius: 10, spreadRadius: -2)]
          : [BoxShadow(color: greenDim, blurRadius: 10, spreadRadius: -5)],
    );
  }

  static BoxDecoration dashedBorder({bool right = false, bool bottom = false, bool top = false, bool left = false}) {
    return BoxDecoration(
      color: bgPanel,
      border: Border(
        right: right ? const BorderSide(color: green, width: 1) : BorderSide.none,
        bottom: bottom ? const BorderSide(color: green, width: 1) : BorderSide.none,
        top: top ? const BorderSide(color: green, width: 1) : BorderSide.none,
        left: left ? const BorderSide(color: green, width: 1) : BorderSide.none,
      ),
    );
  }

  static ThemeData get themeData => ThemeData.dark().copyWith(
    scaffoldBackgroundColor: bg,
    cardColor: bgCard,
    dividerColor: border,
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: fontFamily),
    colorScheme: const ColorScheme.dark(
      primary: green,
      secondary: cyan,
      surface: bgPanel,
      error: red,
    ),
  );
}
