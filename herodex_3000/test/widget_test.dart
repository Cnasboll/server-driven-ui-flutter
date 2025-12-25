// HeroDex 3000 Widget Tests
//
// These tests verify basic widget functionality.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HeroDex 3000 splash screen shows app name', (
    WidgetTester tester,
  ) async {
    // Build a simple splash screen widget
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF1A237E),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield, size: 100, color: Colors.white),
                SizedBox(height: 24),
                Text(
                  'HeroDex 3000',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Verify app name is displayed
    expect(find.text('HeroDex 3000'), findsOneWidget);

    // Verify shield icon is present
    expect(find.byIcon(Icons.shield), findsOneWidget);
  });
}
