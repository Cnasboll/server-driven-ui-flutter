// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swedish (`sv`).
class AppLocalizationsSv extends AppLocalizations {
  AppLocalizationsSv([String locale = 'sv']) : super(locale);

  @override
  String get appTitle => 'HeroDex 3000';

  @override
  String get loadingMessage => 'Laddar...';

  @override
  String get errorBuildingUi => 'Fel vid byggnation av gränssnitt';

  @override
  String get noInternetConnection => 'Ingen internetanslutning';

  @override
  String get backOnline => 'Tillbaka online';

  @override
  String get locationUnavailable => 'Plats ej tillgänglig';

  @override
  String get locationDenied => 'Platstillstånd nekad';
}
