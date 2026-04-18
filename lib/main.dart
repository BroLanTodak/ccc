import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const LanCCCApp());
}

class LanCCCApp extends StatelessWidget {
  const LanCCCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAN CCC',
      debugShowCheckedModeBanner: false,
      theme: HackerTheme.themeData,
      home: const HomeScreen(),
    );
  }
}
