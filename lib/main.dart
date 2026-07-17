import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const NevaApp());
}

class NevaApp extends StatelessWidget {
  const NevaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neva',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BCD4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D1B2A),
      ),
      home: const HomeScreen(),
    );
  }
}
