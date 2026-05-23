import 'package:flutter/material.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060C06),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.leaderboard,
                  color: Color(0xFF00CFFF), size: 64),
              const SizedBox(height: 16),
              const Text(
                'LEADERBOARD',
                style: TextStyle(
                  color: Color(0xFF00CFFF),
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