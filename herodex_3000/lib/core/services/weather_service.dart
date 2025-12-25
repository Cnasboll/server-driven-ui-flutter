import 'dart:convert';
import 'package:http/http.dart' as http;

/// Fetches current weather from Open-Meteo (free, no API key).
/// Caches the last result so it works offline.
class WeatherService {
  Map<String, dynamic>? _cache;
  DateTime? _cacheTime;

  /// Returns {temp, description, icon, windSpeed} or cached data.
  Future<Map<String, dynamic>> fetchWeather(double lat, double lon) async {
    // Return cache if fresh (< 1 hour)
    if (_cache != null && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!).inMinutes < 60) {
      return _cache!;
    }

    try {
      final url = 'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lon&current_weather=true';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final current = json['current_weather'] as Map<String, dynamic>;
        final code = (current['weathercode'] as num).toInt();
        final result = {
          'temp': (current['temperature'] as num).toDouble(),
          'windSpeed': (current['windspeed'] as num).toDouble(),
          'description': _weatherDescription(code),
          'icon': _weatherIcon(code),
        };
        _cache = result;
        _cacheTime = DateTime.now();
        return result;
      }
    } catch (_) {
      // Offline — return cache if available
    }
    return _cache ?? {'temp': 0.0, 'windSpeed': 0.0, 'description': 'Unknown', 'icon': 'cloud'};
  }

  /// WMO Weather interpretation codes → human description
  static String _weatherDescription(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Rain showers';
    if (code <= 86) return 'Snow showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Cloudy';
  }

  /// WMO code → Material icon name
  static String _weatherIcon(int code) {
    if (code == 0) return 'wb_sunny';
    if (code <= 3) return 'cloud';
    if (code <= 48) return 'foggy';
    if (code <= 67) return 'water_drop';
    if (code <= 77) return 'ac_unit';
    if (code <= 86) return 'ac_unit';
    if (code >= 95) return 'flash_on';
    return 'cloud';
  }
}
