import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Platform boundary: HTTP client for the SHQL™ runtime.
///
/// These are the Dart functions behind FETCH(url), POST(url, body),
/// and PATCH(url, body). They are the only place the `http` package
/// is touched for SHQL™ purposes.

Future<dynamic> httpFetch(String url) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  } catch (e) {
    debugPrint('Fetch error: $e');
    return null;
  }
}

/// HTTP POST — returns `{'status': statusCode, 'body': parsedJson}`.
Future<dynamic> httpPost(String url, dynamic body) async {
  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return {
      'status': response.statusCode,
      'body': response.body.isNotEmpty ? jsonDecode(response.body) : null,
    };
  } catch (e) {
    debugPrint('POST error: $e');
    return {'status': 0, 'body': null};
  }
}

/// HTTP PATCH — returns `{'status': statusCode, 'body': parsedJson}`.
Future<dynamic> httpPatch(String url, dynamic body) async {
  try {
    final response = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return {
      'status': response.statusCode,
      'body': response.body.isNotEmpty ? jsonDecode(response.body) : null,
    };
  } catch (e) {
    debugPrint('PATCH error: $e');
    return {'status': 0, 'body': null};
  }
}

/// HTTP GET with Bearer token — returns parsed JSON or null.
Future<dynamic> httpFetchAuth(String url, String token) async {
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    debugPrint('FetchAuth ${response.statusCode}: ${response.body}');
    return null;
  } catch (e) {
    debugPrint('FetchAuth error: $e');
    return null;
  }
}

/// HTTP PATCH with Bearer token — returns `{'status': statusCode, 'body': parsedJson}`.
Future<dynamic> httpPatchAuth(String url, dynamic body, String token) async {
  try {
    final response = await http.patch(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    return {
      'status': response.statusCode,
      'body': response.body.isNotEmpty ? jsonDecode(response.body) : null,
    };
  } catch (e) {
    debugPrint('PatchAuth error: $e');
    return {'status': 0, 'body': null};
  }
}
