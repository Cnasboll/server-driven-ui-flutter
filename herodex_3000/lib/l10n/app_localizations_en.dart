// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'HeroDex 3000';

  @override
  String get loadingMessage => 'Loading...';

  @override
  String get errorBuildingUi => 'Error building UI';

  @override
  String get noInternetConnection => 'No internet connection';

  @override
  String get backOnline => 'Back online';

  @override
  String get locationUnavailable => 'Location unavailable';

  @override
  String get locationDenied => 'Location permission denied';
}
