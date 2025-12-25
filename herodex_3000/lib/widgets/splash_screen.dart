import 'package:flutter/material.dart';

/// Branded splash screen shown during app initialization.
class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    required this.status,
    this.progress = 0,
    this.total = 0,
    this.heroName = '',
  });

  final String status;
  final int progress;
  final int total;
  final String heroName;

  @override
  Widget build(BuildContext context) {
    final hasProgress = total > 0;
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield, size: 100, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              'HeroDex 3000',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Orbitron',
              ),
            ),
            const SizedBox(height: 48),
            if (hasProgress) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: LinearProgressIndicator(
                  value: progress / total,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                heroName.isNotEmpty
                    ? '$heroName ($progress/$total)'
                    : '$progress / $total',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  fontFamily: 'Orbitron',
                ),
              ),
            ] else ...[
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
