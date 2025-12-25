import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Displays a map with hero/villain battle markers.
/// Driven entirely by SHQL™ data — receives markers as a list of maps.
class BattleMapWidget extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double zoom;
  final List<Map<String, dynamic>> markers;

  const BattleMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.zoom = 10,
    this.markers = const [],
  });

  @override
  Widget build(BuildContext context) {
    final center = LatLng(latitude, longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 250,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.herodex3000.app',
            ),
            MarkerLayer(
              markers: markers.map(_buildMarker).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Marker _buildMarker(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble() ?? latitude;
    final lon = (data['lon'] as num?)?.toDouble() ?? longitude;
    final type = data['type']?.toString() ?? 'hero';
    final name = data['name']?.toString() ?? '?';
    final isVillain = type == 'villain';

    return Marker(
      point: LatLng(lat, lon),
      width: 36,
      height: 36,
      child: Tooltip(
        message: name,
        child: Container(
          decoration: BoxDecoration(
            color: isVillain ? Colors.red : Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Icon(
            isVillain ? Icons.dangerous : Icons.shield,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
