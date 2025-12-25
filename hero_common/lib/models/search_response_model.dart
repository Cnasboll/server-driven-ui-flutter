import 'package:hero_common/managers/hero_data_managing.dart';
import 'package:hero_common/models/hero_model.dart';

class SearchResponseModel {
  SearchResponseModel({
    required this.response,
    required this.resultsFor,
    required this.results,
  });

  static Future<SearchResponseModel> fromJson(
    HeroDataManaging heroDataManaging,
    Map<String, dynamic> json,
    DateTime timestamp,
    List<String> failures,
  ) async {
    var response = json['response'] as String;

    List<HeroModel> results = [];

    if (response == "success") {
      for (var h in (json['results'] as List<dynamic>)) {
        var heroJson = h as Map<String, dynamic>;
        try {
          results.add(await heroDataManaging.heroFromJson(heroJson, timestamp));
        } catch (e) {
          failures.add(e.toString());
        }
      }
    }

    return SearchResponseModel(
      response: json['response'] as String,
      resultsFor: json['results-for'] as String,
      results: results,
    );
  }

  String response;
  String resultsFor;
  List<HeroModel> results;
}
