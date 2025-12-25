import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A reusable card widget for displaying hero/villain information
/// This widget is designed to work both as a native Flutter widget
/// and to be registered with the SDUI system
class HeroCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int alignment;
  final int? strength;
  final int? intelligence;
  final int? speed;
  final int? durability;
  final int? power;
  final int? combat;
  final int? totalPower;
  final String? publisher;
  final String? race;
  final String? fullName;
  final bool locked;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleLock;

  const HeroCard({
    super.key,
    required this.name,
    this.imageUrl,
    this.alignment = 0,
    this.strength,
    this.intelligence,
    this.speed,
    this.durability,
    this.power,
    this.combat,
    this.totalPower,
    this.publisher,
    this.race,
    this.fullName,
    this.locked = false,
    this.onTap,
    this.onDelete,
    this.onToggleLock,
  });

  /// Create from a Map (for SDUI integration)
  factory HeroCard.fromMap(
    Map<String, dynamic> data, {
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    return HeroCard(
      name: data['name'] as String? ?? 'Unknown',
      imageUrl: data['url'] as String? ?? data['imageUrl'] as String? ?? data['image']?['url'] as String?,
      alignment: data['alignment'] as int? ??
          data['biography']?['alignment'] as int? ?? 0,
      strength:
          data['powerStats']?['strength'] as int? ?? data['strength'] as int?,
      intelligence:
          data['powerStats']?['intelligence'] as int? ??
          data['intelligence'] as int?,
      speed: data['powerStats']?['speed'] as int? ?? data['speed'] as int?,
      durability:
          data['powerStats']?['durability'] as int? ?? data['durability'] as int?,
      power:
          data['powerStats']?['power'] as int? ?? data['power'] as int?,
      combat:
          data['powerStats']?['combat'] as int? ?? data['combat'] as int?,
      totalPower: data['totalPower'] as int?,
      publisher: data['publisher'] as String?,
      race: data['race'] as String?,
      fullName: data['fullName'] as String?,
      locked: data['locked'] as bool? ?? false,
      onTap: onTap,
      onDelete: onDelete,
    );
  }

  // Indexed by Alignment enum ordinal (hero_common/lib/models/biography_model.dart)
  static const _alignmentStyles = <({String label, IconData icon, List<Color> gradient})>[
    /* 0 */ (label: 'Unknown',       icon: Icons.help_outline,          gradient: [Color(0xFF9E9E9E), Color(0xFF616161)]),
    /* 1 */ (label: 'Neutral',       icon: Icons.balance,               gradient: [Color(0xFF78909C), Color(0xFF455A64)]),
    /* 2 */ (label: 'Mostly Good',   icon: Icons.verified_user,         gradient: [Color(0xFF29B6F6), Color(0xFF1E88E5)]),
    /* 3 */ (label: 'Good',          icon: Icons.shield,                gradient: [Color(0xFF42A5F5), Color(0xFF00897B)]),
    /* 4 */ (label: 'Reasonable',    icon: Icons.thumb_up,              gradient: [Color(0xFF7986CB), Color(0xFF3949AB)]),
    /* 5 */ (label: 'Not Quite',     icon: Icons.warning_amber,         gradient: [Color(0xFFFFA726), Color(0xFFE64A19)]),
    /* 6 */ (label: 'Bad',           icon: Icons.whatshot,               gradient: [Color(0xFFE53935), Color(0xFF4A0000)]),
    /* 7 */ (label: 'Ugly',          icon: Icons.mood_bad,              gradient: [Color(0xFFC62828), Color(0xFF3A0000)]),
    /* 8 */ (label: 'Evil',          icon: Icons.local_fire_department, gradient: [Color(0xFF8B0000), Color(0xFF1A0000)]),
    /* 9 */ (label: 'Using Mobile Speaker on Public Transport', icon: Icons.volume_up, gradient: [Color(0xFF0D0000), Color(0xFF000000)]),
  ];

  ({String label, IconData icon, List<Color> gradient}) get _alignmentStyle =>
      (alignment >= 0 && alignment < _alignmentStyles.length)
          ? _alignmentStyles[alignment]
          : _alignmentStyles[0];

  Color get _alignmentColor => _alignmentStyle.gradient.first;
  IconData get _alignmentIcon => _alignmentStyle.icon;
  List<Color> get _alignmentGradient => _alignmentStyle.gradient;

  String get _subtitle {
    final parts = <String>[];
    if (publisher != null && publisher!.isNotEmpty) parts.add(publisher!);
    if (race != null && race!.isNotEmpty) parts.add(race!);
    return parts.join(' \u2022 ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget card = Semantics(
      label: '$name, ${_alignmentStyle.label} alignment'
          '${strength != null ? ", strength $strength" : ""}'
          '${intelligence != null ? ", intelligence $intelligence" : ""}'
          '${speed != null ? ", speed $speed" : ""}',
      button: onTap != null,
      child: Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _alignmentColor.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image section – fill remaining space after the info section
            Expanded(
              child: _HeroCardImage(
                imageUrl: imageUrl,
                isDark: isDark,
                alignmentGradient: _alignmentGradient,
                alignmentIcon: _alignmentIcon,
                alignmentLabel: _alignmentStyle.label,
                heroName: name,
                locked: locked,
                onDelete: onDelete,
                onToggleLock: onToggleLock,
              ),
            ),

            // Info section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Publisher / Race subtitle
                  if (_subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Stats row 1: STR / INT / SPD
                  Row(
                    children: [
                      _StatChip(icon: Icons.fitness_center, value: strength, color: Colors.red),
                      const SizedBox(width: 4),
                      _StatChip(icon: Icons.psychology, value: intelligence, color: Colors.blue),
                      const SizedBox(width: 4),
                      _StatChip(icon: Icons.flash_on, value: speed, color: Colors.amber),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Stats row 2: DUR / POW / CMB
                  Row(
                    children: [
                      _StatChip(icon: Icons.shield, value: durability, color: Colors.green),
                      const SizedBox(width: 4),
                      _StatChip(icon: Icons.bolt, value: power, color: Colors.purple),
                      const SizedBox(width: 4),
                      _StatChip(icon: Icons.sports_mma, value: combat, color: Colors.brown),
                    ],
                  ),

                  if (totalPower != null) ...[
                    const SizedBox(height: 8),
                    _PowerBar(
                      totalPower: totalPower!,
                      isDark: isDark,
                      color: _alignmentColor,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );

    // Wrap in Dismissible for swipe-to-delete
    if (onDelete != null) {
      card = Dismissible(
        key: ValueKey('dismiss_$name'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white, size: 32),
        ),
        onDismissed: (_) => onDelete!(),
        child: card,
      );
    }

    return card;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 2),
            Text(
              value?.toString() ?? '-',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCardImage extends StatelessWidget {
  const _HeroCardImage({
    required this.imageUrl,
    required this.isDark,
    required this.alignmentGradient,
    required this.alignmentIcon,
    required this.alignmentLabel,
    required this.heroName,
    required this.locked,
    this.onDelete,
    this.onToggleLock,
  });

  final String? imageUrl;
  final bool isDark;
  final List<Color> alignmentGradient;
  final IconData alignmentIcon;
  final String alignmentLabel;
  final String heroName;
  final bool locked;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleLock;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hero image
        if (imageUrl != null && imageUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: isDark ? Colors.grey[800] : Colors.grey[200],
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => _buildPlaceholder(isDark),
          )
        else
          _buildPlaceholder(isDark),

        // Alignment badge
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: alignmentGradient,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(alignmentIcon, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text(
                  alignmentLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Delete button (only for saved heroes)
        if (onDelete != null)
          Positioned(
            top: 8,
            right: 8,
            child: Semantics(
              label: 'Remove $heroName from database',
              button: true,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.delete,
                      color: Colors.red[300],
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Lock toggle
        if (onToggleLock != null)
          Positioned(
            top: onDelete != null ? 48 : 8,
            right: 8,
            child: Semantics(
              label: locked
                  ? 'Unlock $heroName (currently locked from reconciliation)'
                  : 'Lock $heroName (prevent reconciliation changes)',
              button: true,
              child: Material(
                color: locked
                    ? Colors.amber[700]!.withValues(alpha: 0.9)
                    : Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onToggleLock,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      locked ? Icons.lock : Icons.lock_open,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      child: Icon(
        Icons.person,
        size: 64,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    );
  }
}

class _PowerBar extends StatelessWidget {
  const _PowerBar({
    required this.totalPower,
    required this.isDark,
    required this.color,
  });

  final int totalPower;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total Power: $totalPower',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: (totalPower / 600).clamp(0.0, 1.0),
          backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ],
    );
  }
}
