import 'package:dart_dotenv/dart_dotenv.dart';
import 'package:hero_common/callbacks.dart';

class Env {
  static Future<Env> createAsync() async {
    final dotEnv = DotEnv(filePath: filePath);
    var env = dotEnv.getDotEnv();
    bool saveNeeded = false;
    var apiKey = env[apiKeyName] ?? '';
    if (apiKey.isEmpty) {
      if (Callbacks.onPromptFor != null) {
        apiKey = await Callbacks.onPromptFor!('Enter your API key: ');
      }
      if (apiKey.isEmpty) {
        throw Exception(
          "API key is required. Set '$apiKeyName' in .env or configure terminal prompts.",
        );
      }
      saveNeeded = true;
    }

    var apiHost = env[apiHostName] ?? '';
    if (apiHost.isEmpty) {
      if (Callbacks.onPromptFor != null) {
        apiHost = await Callbacks.onPromptFor!(
          'Enter API host or press enter to accept default ("$defaultApiHost"): ',
          defaultApiHost,
        );
      } else {
        apiHost = defaultApiHost;
      }
      saveNeeded = true;
    }

    if (saveNeeded) {
      dotEnv.set(apiKeyName, apiKey);
      dotEnv.set(apiHostName, apiHost);
      if (!dotEnv.exists()) {
        dotEnv.createNew();
      }
      dotEnv.saveDotEnv();
    }

    return Env.create(apiKey: apiKey, apiHost: apiHost);
  }

  Env.create({required this.apiKey, required this.apiHost});

  static const String filePath = '.env';
  static const apiKeyName = 'API_KEY';
  static const apiHostName = 'API_HOST';
  static const defaultApiHost = 'www.superheroapi.com';

  final String apiKey;
  final String apiHost;
}
