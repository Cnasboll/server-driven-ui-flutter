import 'package:hero_common/amendable/field_base.dart';
import 'package:shql/execution/runtime/runtime.dart' show Object;
import 'package:shql/parser/constants_set.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:hero_common/models/appearance_model.dart';
import 'package:hero_common/models/biography_model.dart';
import 'package:hero_common/value_types/value_type.dart';

/// Shared logic for exposing HeroModel data to the SHQL™ runtime.
///
/// Use [registerHeroSchema] once at startup to register Alignment / Gender /
/// SystemOfUnits constants and all HeroModel field identifiers into a
/// [ConstantsSet].
///
/// Use [heroToShqlObject] / [heroToDisplayObject] to turn a [HeroModel] into
/// an SHQL™ [Object] whose members can be accessed with `.member` syntax in
/// SHQL™ expressions (e.g. `hero.biography.alignment`).
class HeroShqlAdapter {
  HeroShqlAdapter._();

  // ---------------------------------------------------------------------------
  // Schema registration
  // ---------------------------------------------------------------------------

  /// Registers Alignment / Gender / SystemOfUnits constants and all HeroModel
  /// field identifiers into [constantsSet].
  static void registerHeroSchema(ConstantsSet constantsSet) {
    _registerEnum(constantsSet, Alignment.values, Alignment.displayNames, 'alignment');
    _registerEnum(constantsSet, Gender.values, Gender.displayNames, 'gender');
    _registerEnum(constantsSet, SystemOfUnits.values, null, 'system_of_units');
    _declareFields(HeroModel.staticFields, constantsSet);
  }

  // Maps shqlName → SHQL™ label list variable name for enum fields.
  static final _enumLabelVars = <String, String>{};

  /// Returns the SHQL™ label list variable name for an enum field, or null.
  /// e.g. `enumLabelsFor('alignment')` → `'_ALIGNMENT_LABELS'`
  static String? enumLabelsFor(String shqlName) => _enumLabelVars[shqlName];

  static void _registerEnum(
    ConstantsSet cs,
    List<Enum> values,
    List<String>? displayNames,
    String shqlName,
  ) {
    final upper = shqlName.toUpperCase();
    cs.registerEnum(values, '_${upper}_NAMES');
    if (displayNames != null) {
      final labelsVar = '_${upper}_LABELS';
      cs.registerConstant(displayNames, cs.includeIdentifier(labelsVar));
      _enumLabelVars[shqlName] = labelsVar;
    }
  }

  static void _declareFields(List<FieldBase> fields, ConstantsSet constantsSet) {
    for (var field in fields) {
      var f = field as dynamic;
      constantsSet.includeIdentifier((f.shqlName as String).toUpperCase());
      _declareFields(f.children as List<FieldBase>, constantsSet);
    }
  }

  // ---------------------------------------------------------------------------
  // Object creation
  // ---------------------------------------------------------------------------

  /// Populates [target] with SHQL™ variables for each field in [fields],
  /// reading values from [model].  Nested child fields become nested Objects.
  static void registerFields(
    List<FieldBase> fields,
    dynamic model,
    ConstantsTable<String> identifiers,
    Object target,
  ) {
    for (var field in fields) {
      var f = field as dynamic;
      var id = identifiers.include((f.shqlName as String).toUpperCase());
      var children = f.children as List<FieldBase>;
      if (children.isEmpty) {
        target.setVariable(id, (f.shqlGetter as Function)(model));
      } else {
        var childObj = Object();
        registerFields(children, (f.getter as Function)(model), identifiers, childObj);
        target.setVariable(id, childObj);
      }
    }
  }

  /// Creates an SHQL™ [Object] from a [HeroModel] with all fields registered
  /// as members.
  static Object heroToShqlObject(HeroModel hero, ConstantsTable<String> identifiers) {
    var obj = Object();
    registerFields(HeroModel.staticFields, hero, identifiers, obj);
    return obj;
  }

  /// Like [heroToShqlObject] but also sets a `SAVED_AT` member so that SHQL™
  /// code can distinguish saved heroes from unsaved search results.
  static Object heroToDisplayObject(
    HeroModel hero,
    ConstantsTable<String> identifiers, {
    required bool isSaved,
  }) {
    var obj = heroToShqlObject(hero, identifiers);
    obj.setVariable(
      identifiers.include('SAVED_AT'),
      isSaved ? hero.timestamp.toIso8601String() : null,
    );
    obj.setVariable(
      identifiers.include('LOCKED'),
      hero.locked,
    );
    return obj;
  }

  /// Converts a list of [HeroModel]s to a list of SHQL™ display Objects.
  static List<Object> heroesToDisplayList(
    List<HeroModel> heroes,
    ConstantsTable<String> identifiers, {
    required bool isSaved,
  }) {
    return heroes
        .map((h) => heroToDisplayObject(h, identifiers, isSaved: isSaved))
        .toList();
  }

  /// Builds a `Map<String, dynamic>` from a [HeroModel] for use as
  /// `boundValues` in [Engine.execute].  Leaf fields map to raw values;
  /// sub-models (appearance, biography, …) map to SHQL™ [Object]s.
  static Map<String, dynamic> heroToBoundValues(
    HeroModel hero,
    ConstantsTable<String> identifiers,
  ) {
    var result = <String, dynamic>{};
    for (var field in HeroModel.staticFields) {
      var f = field as dynamic;
      var name = f.shqlName as String;
      var children = f.children as List<FieldBase>;
      if (children.isEmpty) {
        result[name] = (f.shqlGetter as Function)(hero);
      } else {
        var childObj = Object();
        registerFields(children, (f.getter as Function)(hero), identifiers, childObj);
        result[name] = childObj;
      }
    }
    return result;
  }

}
