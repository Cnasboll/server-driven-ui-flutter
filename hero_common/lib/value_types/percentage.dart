
import 'package:equatable/equatable.dart';
import 'package:hero_common/amendable/parsing_context.dart';

class Percentage extends Equatable implements Comparable<Percentage> {
  
  Percentage(this.value, {ParsingContext? parsingContext}) {
    var (success, error) = validateValue(value, parsingContext: parsingContext);
    if (error != null) {
      throw FormatException(error);
    }
  }
  
  Percentage._create(this.value);

  static (bool, String?) validateValue(int value, {ParsingContext? parsingContext}) {
    if (value < 0 || value > 100) {
      var context = parsingContext != null
          ? 'When ${parsingContext.toString()}: '
          : '';
      return (false, "${context}Percentage value must be within the range 0 to 100, inclusive, got: $value");
    }
    return (true, null);
  }

  static (bool, String?) validateInput(String? input) {
    var (_, error) = tryParse(input);
    return (error == null, error);
  }

  static (Percentage?, String?) tryCreate(
    int value, {
    ParsingContext? parsingContext,
  }) {
    var (success, error) = validateValue(value, parsingContext: parsingContext);
    if (!success) {
      return (null, error);
    }
    return (Percentage._create(value), null);
  }

  static (Percentage?, String?) tryParse(String? value, {ParsingContext? parsingContext}) {
    if (value == null) {
      return (null, null);
    }
    final intValue = int.tryParse(value);
    if (intValue == null) {
      var context = parsingContext != null
            ? 'When ${parsingContext.toString()}: '
            : '';
      return (null, "${context}Could not parse percentage value: $value");
    }

    return tryCreate(intValue, parsingContext: parsingContext);
  }

  @override
  List<Object?> get props => [value];

  @override
  int compareTo(Percentage other) {
    return value.compareTo(other.value);
  }

  final int value;
}
