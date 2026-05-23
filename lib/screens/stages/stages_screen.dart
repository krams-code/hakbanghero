import 'package:flutter/material.dart';

class StagesScreen extends StatelessWidget {
  const StagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.map, color: Color(0xFFFFD700), size: 64),
              const SizedBox(height: 16),
              const Text(
                'STAGE SELECT',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Coming Soon',
                style: TextStyle(
                  color: const Color(0xFF4A6A4A),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}