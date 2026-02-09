import 'package:flutter/material.dart';

import 'src/demo_page.dart';

void main() {
  runApp(const EscPosExampleApp());
}

class EscPosExampleApp extends StatelessWidget {
  const EscPosExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESC/POS Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
      ),
      home: const DemoPage(),
    );
  }
}
