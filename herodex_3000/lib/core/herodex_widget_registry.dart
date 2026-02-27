import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

/// Creates a [WidgetRegistry] with HeroDex-specific custom widgets
/// layered on top of the basic SDUI widgets.
///
/// Only widgets that genuinely need Dart (3rd-party libs, platform APIs)
/// live here. All JSON-like widget tree generation is in SHQL™.
HeroDexWidgetRegistry createHeroDexWidgetRegistry() {
  final basicRegistry = WidgetRegistry.basic();

  final customFactories = <String, WidgetFactory>{
    // -----------------------------------------------------------------------
    // CachedImage — CachedNetworkImage (3rd-party).
    // The ONLY Dart boundary here: CachedNetworkImage has builder callbacks
    // (placeholder, errorWidget) that require Dart closures.
    // Everything else (Stack, badge, overlays) is SHQL™-generated.
    // -----------------------------------------------------------------------
    'CachedImage':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final imageUrl = props['imageUrl'] as String?;
          final placeholderNode = props['placeholder'];
          final spinnerNode = props['spinner'];

          if (imageUrl == null || imageUrl.isEmpty) {
            return buildChild(placeholderNode, '$path.placeholder');
          }

          return CachedNetworkImage(
            key: key,
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (ctx, url) =>
                buildChild(spinnerNode, '$path.spinner'),
            errorWidget: (ctx, url, error) =>
                buildChild(placeholderNode, '$path.placeholder'),
          );
        },

    // -----------------------------------------------------------------------
    // flutter_map types — registered individually so SHQL™ can generate
    // the full widget tree as JSON. Only Dart because they are 3rd-party.
    // -----------------------------------------------------------------------
    'FlutterMap':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final lat = (props['latitude'] as num?)?.toDouble() ?? 0;
          final lon = (props['longitude'] as num?)?.toDouble() ?? 0;
          final zoom = (props['zoom'] as num?)?.toDouble() ?? 10;
          final childList = (children is List) ? children : <dynamic>[];

          return FlutterMap(
            key: key,
            options: MapOptions(
              initialCenter: LatLng(lat, lon),
              initialZoom: zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: childList
                .asMap()
                .entries
                .map((e) => buildChild(e.value, '$path.children[${e.key}]'))
                .toList(),
          );
        },

    'TileLayer':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          return TileLayer(
            key: key,
            urlTemplate: props['urlTemplate'] as String? ??
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: props['userAgent'] as String? ??
                'com.herodex3000.app',
          );
        },

    'MarkerLayer':
        (context, props, buildChild, child, children, path, shql, key, engine) {
          final rawMarkers = props['markers'];
          final markers = <Marker>[];
          if (rawMarkers is List) {
            for (var i = 0; i < rawMarkers.length; i++) {
              var m = rawMarkers[i];
              if (m is! Map<String, dynamic>) m = shql.objectToMap(m);
              final data = m;
              markers.add(Marker(
                point: LatLng(
                  (data['lat'] as num?)?.toDouble() ?? 0,
                  (data['lon'] as num?)?.toDouble() ?? 0,
                ),
                width: (data['width'] as num?)?.toDouble() ?? 36,
                height: (data['height'] as num?)?.toDouble() ?? 36,
                child: buildChild(data['child'], '$path.marker[$i]'),
              ));
            }
          }
          return MarkerLayer(key: key, markers: markers);
        },
  };

  return HeroDexWidgetRegistry(basicRegistry, customFactories);
}

/// Registers HeroDex custom factories on the static registry so that
/// imperative Dart widgets using [WidgetRegistry.buildStatic] can resolve
/// custom types like `HeroCardImage`.
void registerStaticFactories(AppWidgetRegistry registry) {
  for (final entry in registry.customFactories.entries) {
    WidgetRegistry.registerStaticFactory(entry.key, entry.value);
  }
}

/// Extended registry that adds HeroDex custom widgets on top of the basic
/// framework registry. Uses the generic [AppWidgetRegistry] 3-tier lookup:
/// custom factories → basic (framework) registry → YAML templates.
class HeroDexWidgetRegistry extends AppWidgetRegistry {
  HeroDexWidgetRegistry(super.basicRegistry, super.customFactories);
}
