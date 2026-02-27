import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_driven_ui/server_driven_ui.dart';
import 'package:herodex_3000/core/herodex_widget_registry.dart';
import 'hero_card_test_utils.dart';

/// YAML templates used by the hero card tree.
const _requiredTemplates = [
  'HeroCardBody',
  'DismissibleCard',
  'BadgeRow',
  'OverlayActionButton',
  'HeroPlaceholder',
  'StatChip',
  'PowerBar',
];

/// Convert CamelCase to snake_case for YAML file names.
String _camelToSnake(String input) {
  return input.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (m) => m.start == 0 ? m[0]!.toLowerCase() : '_${m[0]!.toLowerCase()}',
  );
}

void main() {
  setUpAll(() {
    // Initialize static bindings (no platform boundaries needed for tests)
    WidgetRegistry.initStaticBindings();

    // Register YAML templates on the static registry
    for (final name in _requiredTemplates) {
      final file = File('assets/widgets/${_camelToSnake(name)}.yaml');
      if (file.existsSync()) {
        WidgetRegistry.loadStaticTemplate(name, file.readAsStringSync());
      }
    }
    // Register custom Dart factories (HeroCardImage, BattleMap)
    registerStaticFactories(createHeroDexWidgetRegistry());
  });

  /// Build a hero card tree through the static registry, matching the shape
  /// that SHQL™ _MAKE_HERO_CARD_TREE emits at runtime.
  Widget buildTestCard({
    String name = 'Batman',
    String? imageUrl,
    int alignment = 3,
    List<Map<String, dynamic>> stats = const [],
    int? totalPower = 450,
    bool locked = false,
    String? onTap,
    String? onDelete,
    String? onToggleLock,
  }) {
    // Build info children (mirrors SHQL™ _MAKE_HERO_CARD_TREE)
    final infoChildren = <Map<String, dynamic>>[
      {'type': 'Text', 'props': {'data': name, 'style': {'fontWeight': 'bold'}}},
    ];

    // Stat chip rows (groups of 3)
    if (stats.isNotEmpty) {
      infoChildren.add({'type': 'SizedBox', 'props': {'height': 8}});
      final rowChildren = <Map<String, dynamic>>[];
      for (var i = 0; i < stats.length; i++) {
        if (rowChildren.isNotEmpty) {
          rowChildren.add({'type': 'SizedBox', 'props': {'width': 4}});
        }
        rowChildren.add({
          'type': 'StatChip',
          'props': {
            'label': stats[i]['label'] ?? '?',
            'valueText': stats[i]['value']?.toString() ?? '-',
            'color': stats[i]['color'] ?? '0xFF9E9E9E',
            'bgColor': '0x1A9E9E9E',
          },
        });
      }
      infoChildren.add({'type': 'Row', 'children': rowChildren});
    }

    // Power bar
    if (totalPower != null && totalPower > 0) {
      infoChildren.add({'type': 'SizedBox', 'props': {'height': 8}});
      infoChildren.add({
        'type': 'PowerBar',
        'props': {
          'label': 'Total Power: $totalPower',
          'progress': (totalPower / 600).clamp(0.0, 1.0),
          'color': '0xFF42A5F5',
          'bgColor': '0xFFE0E0E0',
        },
      });
    }

    // Build image section: Expanded > Stack > [CachedImage, badge, overlays]
    // Mirrors SHQL™ _MAKE_HERO_CARD_TREE structure.
    final phColor = '0xFFEEEEEE';
    final phIconColor = '0xFFBDBDBD';
    final placeholder = {'type': 'Container', 'props': {'color': phColor, 'child': {'type': 'HeroPlaceholder', 'props': {'color': phIconColor}}}};
    final spinner = {'type': 'Container', 'props': {'color': phColor, 'child': {'type': 'Center', 'props': {'child': {'type': 'CircularProgressIndicator', 'props': {}}}}}};

    final stackChildren = <Map<String, dynamic>>[
      {'type': 'CachedImage', 'props': {'imageUrl': imageUrl, 'placeholder': placeholder, 'spinner': spinner}},
      {'type': 'Positioned', 'props': {
        'top': 8, 'left': 8,
        'child': {'type': 'Container', 'props': {
          'padding': {'left': 8, 'right': 8, 'top': 4, 'bottom': 4},
          'decoration': {'gradient': {'colors': ['0xFF42A5F5', '0xFF00897B']}, 'borderRadius': 12},
          'child': {'type': 'BadgeRow', 'props': {'icon': 'shield', 'label': 'Good'}},
        }},
      }},
      if (onDelete != null) {
        'type': 'OverlayActionButton',
        'props': {
          'top': 8, 'right': 8,
          'label': 'Remove $name from database',
          'bgColor': '0x8A000000',
          'onTap': onDelete,
          'icon': 'delete',
          'iconColor': '0xFFEF9A9A',
        },
      },
      if (onToggleLock != null) {
        'type': 'OverlayActionButton',
        'props': {
          'top': onDelete != null ? 48 : 8, 'right': 8,
          'label': locked
              ? 'Unlock $name (currently locked from reconciliation)'
              : 'Lock $name (prevent reconciliation changes)',
          'bgColor': locked ? '0xE6FFA000' : '0x8A000000',
          'onTap': onToggleLock,
          'icon': locked ? 'lock' : 'lock_open',
          'iconColor': '0xFFFFFFFF',
        },
      },
    ];

    final imageSection = {
      'type': 'Expanded',
      'props': {
        'child': {'type': 'Stack', 'props': {'fit': 'expand', 'children': stackChildren}},
      },
    };

    // Card body
    Map<String, dynamic> card = {
      'type': 'HeroCardBody',
      'props': {
        'semanticsLabel': 'Batman, Good alignment',
        'isButton': onTap != null,
        'borderColor': '0x8042A5F5',
        'onTap': onTap,
        'children': [
          imageSection,
          {
            'type': 'Padding',
            'props': {
              'padding': 12,
              'child': {
                'type': 'Column',
                'props': {
                  'crossAxisAlignment': 'start',
                  'children': infoChildren,
                },
              },
            },
          },
        ],
      },
    };

    // Dismissible wrapper
    if (onDelete != null) {
      card = {
        'type': 'DismissibleCard',
        'props': {'onDismissed': onDelete, 'child': card},
      };
    }

    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return SizedBox(
            width: 300,
            height: 400,
            child: WidgetRegistry.buildStatic(context, card, 'test.heroCard'),
          );
        }),
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
      await tester.pumpWidget(buildTestCard(onDelete: 'shql: NOP()'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete), findsOneWidget);
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
      await tester.pumpWidget(buildTestCard(locked: false, onToggleLock: 'shql: NOP()'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('shows lock icon when locked and onToggleLock set', (tester) async {
      await tester.pumpWidget(buildTestCard(locked: true, onToggleLock: 'shql: NOP()'));
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

    test('alignmentColorFor returns correct color', () {
      final good = HeroCard.alignmentColorFor(3);
      expect(good, const Color(0xFF42A5F5));
      final unknown = HeroCard.alignmentColorFor(99);
      expect(unknown, const Color(0xFF9E9E9E));
    });

    test('semanticsLabel builds correct string', () {
      final label = HeroCard.semanticsLabel('Batman', 3, [
        {'label': 'STR', 'value': 80},
      ]);
      expect(label, 'Batman, Good alignment, STR 80');
    });

    test('subtitle joins publisher and race', () {
      expect(HeroCard.subtitle('DC', 'Human'), 'DC \u2022 Human');
      expect(HeroCard.subtitle('DC', null), 'DC');
      expect(HeroCard.subtitle(null, null), '');
    });
  });
}
