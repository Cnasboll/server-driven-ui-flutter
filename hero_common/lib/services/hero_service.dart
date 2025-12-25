import 'dart:async';
import 'dart:convert';

import 'package:hero_common/env/env.dart';
import 'package:hero_common/services/hero_servicing.dart';
import 'package:http/http.dart' as http;

class HeroService implements HeroServicing {
  HeroService(this._env);

  String applyApiKey(String path) {
    return "/api.php/${_env.apiKey}/$path";
  }

  Future<(String, int)> fetchRawAsync(String path) async {
    final httpPackageUrl = Uri.https(_env.apiHost, applyApiKey(path));
    final httpPackageResponse = await http.get(httpPackageUrl)
        .timeout(const Duration(seconds: 15));
    return (httpPackageResponse.body, httpPackageResponse.statusCode);
  }

  Future<Map<String, dynamic>?> fetchAsync(String path) async {
    try {
      final httpPackageUrl = Uri.https(_env.apiHost, applyApiKey(path));
      print('[HeroService] GET $httpPackageUrl');
      final (body, statusCode) = await fetchRawAsync(path);
      print('[HeroService] status=$statusCode body=${body.length > 200 ? '${body.substring(0, 200)}...' : body}');
      if (statusCode == 200) {
        return json.decode(body) as Map<String, dynamic>;
      }
      return null;
    } on TimeoutException {
      print('[HeroService] Request timed out for $path');
      return {'error': 'Request timed out'};
    } catch (e) {
      print('[HeroService] Error fetching $path: $e');
      return {'error': '$e'};
    }
  }

  @override
  Future<Map<String, dynamic>?> search(String name) async {
    return fetchAsync("search/$name");
  }

  @override
  Future<Map<String, dynamic>?> getById(String id) async {
    return fetchAsync(id);
  }

  final Env _env;
}
