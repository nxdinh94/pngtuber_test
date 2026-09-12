import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pngtuber/pngtuber_controller.dart';
import 'widgets/pngtuber_demo_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  runApp(const MePngTuberApp());
}

class MePngTuberApp extends StatelessWidget {
  const MePngTuberApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Me PNGTuber',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF090A10),
        useMaterial3: true,
      ),
      home: const PNGTuberDemoPage(controllerFactory: PNGTuberController.new),
    );
  }
}
