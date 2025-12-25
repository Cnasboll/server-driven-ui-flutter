import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Returns (latitude, longitude) or null if unavailable.
  static Future<(double, double)?> getCoordinates() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      return (position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  static Future<String> getLocationDescription() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'Location permission denied';
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      return 'Lat: ${position.latitude.toStringAsFixed(2)}, '
          'Lon: ${position.longitude.toStringAsFixed(2)}';
    } catch (e) {
      debugPrint('Location error: $e');
      return 'Location unavailable';
    }
  }
}
