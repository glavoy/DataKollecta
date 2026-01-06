import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/survey_config_service.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Initialize surveys (extract zips)
    await SurveyConfigService().initializeSurveys();

    // 2. Run DB init and minimum delay in parallel
    await Future.wait([
      DbService.init(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 214, 231, 244),
      body: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/branding/datakollecta.png',
            width: 200,
            height: 200,
          ),
        ),
      ),
    );
  }
}
