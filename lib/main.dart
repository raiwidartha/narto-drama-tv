import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/tv_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force Landscape Orientation for TV 10-Foot Experience
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Dark navigation styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B1120),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const NartoDramaTvApp());
}

class NartoDramaTvApp extends StatelessWidget {
  const NartoDramaTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Narto Drama TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFFFF2D55),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2D55),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF1E293B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1120),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const TvHomeScreen(),
    );
  }
}

