import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herodex_3000/widgets/hero_card.dart';

void main() {
  Widget buildTestCard({
    String name = 'Batman',
    String? imageUrl,
    int alignment = 3,  // Alignment.good
    List<Map<String, dynamic>> stats = const [],
    int? totalPower = 450,
    bool locked = false,
    VoidCallback? onTap,
    VoidCallback? onDelete,
    VoidCallback? onToggleLock,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 400,
          child: HeroCard(
            name: name,
            imageUrl: imageUrl,
            alignment: alignment,
            stats: stats,
            totalPower: totalPower,
            locked: locked,
            onTap: onTap,
            onDelete: onDelete,
            onToggleLock: onToggleLock,
          ),
        ),
      ),
    );
  }

  group('HeroCard', () {
    testWidgets('displays hero name', (tester) async {
      await tester.pumpWidget(buildTestCard(name: 'Superman'));
      await tester.pumpAndSettle();
      expect(find.text('Superman'), findsOneWidget);
    });

    testWidgets('displays alignment badge', (tester) async {
      await tester.pumpWidget(buildTestCard(alignment: 3));
      await tester.pumpAndSettle();
      expect(find.text('Good'), findsOneWidget);
    });

    testWidgets('displays stat chips from stats list', (tester) async {
      await tester.pumpWidget(buildTestCard(
        stats: [
          {'label': 'STR', 'value': 80, 'color': '0xFFF44336'},
          {'label': 'INT', 'value': 100, 'color': '0xFF2196F3'},
          {'label': 'SPD', 'value': 60, 'color': '0xFFFF9800'},
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('80'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('STR'), findsOneWidget);
      expect(find.text('INT'), findsOneWidget);
      expect(find.text('SPD'), findsOneWidget);
    });

    testWidgets('hides delete button when onDelete is null', (tester) async {
      await tester.pumpWidget(buildTestCard());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets('shows delete icon when onDelete is set', (tester) async {
      await tester.pumpWidget(buildTestCard(onDelete: () {}));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('calls onDelete when delete tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(buildTestCard(
        onDelete: () => called = true,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete));
      expect(called, isTrue);
    });

    testWidgets('shows placeholder when imageUrl is null', (tester) async {
      await tester.pumpWidget(buildTestCard(imageUrl: null));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('has accessibility semantics', (tester) async {
      await tester.pumpWidget(buildTestCard(
        name: 'Batman',
        alignment: 3,
        stats: [
          {'label': 'STR', 'value': 80, 'color': '0xFFF44336'},
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Batman')), findsAtLeast(1));
    });

    testWidgets('shows lock_open icon when unlocked and onToggleLock set', (tester) async {
      await tester.pumpWidget(buildTestCard(locked: false, onToggleLock: () {}));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('shows lock icon when locked and onToggleLock set', (tester) async {
      await tester.pumpWidget(buildTestCard(locked: true, onToggleLock: () {}));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.byIcon(Icons.lock_open), findsNothing);
    });

    testWidgets('hides lock icon when onToggleLock is null', (tester) async {
      await tester.pumpWidget(buildTestCard(locked: true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_open), findsNothing);
    });

    testWidgets('calls onToggleLock when lock tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(buildTestCard(
        locked: false,
        onToggleLock: () => called = true,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.lock_open));
      expect(called, isTrue);
    });

    testWidgets('fromMap creates card correctly', (tester) async {
      final card = HeroCard.fromMap({
        'name': 'Wonder Woman',
        'alignment': 3,
        'stats': [
          {'label': 'STR', 'value': 90, 'color': '0xFFF44336'},
          {'label': 'INT', 'value': 95, 'color': '0xFF2196F3'},
        ],
        'totalPower': 500,
      });
      expect(card.name, 'Wonder Woman');
      expect(card.stats.length, 2);
      expect(card.stats[0]['value'], 90);
    });
  });
}
