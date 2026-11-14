// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/scanner_screen.dart';
import 'screens/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode to simplify real-time camera/HUD coordinate transforms
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Set system UI to immersive dark HUD style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    const ProviderScope(
      child: PantryPilotApp(),
    ),
  );
}

class PantryPilotApp extends StatelessWidget {
  const PantryPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pantry Pilot',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676), // High-visibility Neon Green
          secondary: Color(0xFFFF5252), // High-visibility Alert Red
          tertiary: Color(0xFFFFD54F), // High-visibility Amber
          surface: Color(0xFF1B1E23),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B1E23),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const ScannerScreen(),
        '/profile': (context) => const ProfileScreen(),
      },
    );
  }
}
