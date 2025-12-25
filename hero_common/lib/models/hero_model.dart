import 'package:uuid/uuid.dart';
import 'package:hero_common/amendable/field_base.dart';
import 'package:hero_common/amendable/parsing_context.dart';
import 'package:hero_common/models/appearance_model.dart';
import 'package:hero_common/models/biography_model.dart';
import 'package:hero_common/models/connections_model.dart';
import 'package:hero_common/models/image_model.dart';
import 'package:hero_common/models/power_stats_model.dart';
import 'package:hero_common/models/work_model.dart';
import 'package:hero_common/amendable/field.dart';
import 'package:hero_common/amendable/amendable.dart';

class HeroParsingContext implements ParsingContext {
  HeroParsingContext(
    this.id,
    this.externalId,
    this.name,
    this.isNew, {
    this.crumbs = const [],
  });
  final String id;
  final String externalId;
  final String name;
  final bool isNew;
  final List<String> crumbs;
  @override
  String toString() {
    if (isNew) {
      return 'parsing ${crumbs.join(" -> ")} for new hero with externalId: "$externalId" and name: "$name"';
    }
    return 'parsing ${crumbs.join(" -> ")} for hero with id: $id, externalId: "$externalId" and name: "$name"';
  }

  @override
  ParsingContext next(String crumb) {
    return HeroParsingContext(
      id,
      externalId,
      name,
      isNew,
      crumbs: [...crumbs, crumb],
    );
  }
}

class HeroModel extends Amendable<HeroModel> {
  HeroModel({
    required this.id,
    required this.externalId,
    required this.version,
    required this.timestamp,
    required this.locked,
    required this.name,
    required this.powerStats,
    required this.biography,
    required this.appearance,
    required this.work,
    required this.connections,
    required this.image,
  });

  HeroModel.newId(
    DateTime timestamp,
    String externalId,
    String name,
    PowerStatsModel powerStats,
    BiographyModel biography,
    AppearanceModel appearance,
    WorkModel work,
    ConnectionsModel connections,
    ImageModel image,
  ) : this(
        id: Uuid().v4(),
        version: 1,
        timestamp: timestamp,
        locked: false,
        externalId: externalId,
        name: name,
        powerStats: powerStats,
        biography: biography,
        appearance: appearance,
        work: work,
        connections: connections,
        image: image,
      );

  @override
  Future<HeroModel> amendWith(
    Map<String, dynamic>? amendment, {
    ParsingContext? parsingContext,
  }) async {
    return apply(amendment, DateTime.timestamp(), true);
  }

  Future<HeroModel> apply(
    Map<String, dynamic>? amendment,
    DateTime timestamp,
    bool manualAmendment,
  ) async {
    var name = _nameField.getStringForAmendment(this, amendment);
    var parsingContext = HeroParsingContext(id, externalId, name, false);
    return HeroModel(
      id: id,
      version: version + 1,
      timestamp: timestamp,
      locked:
          locked ||
          manualAmendment, // Any manual amendment locks the hero from synchronization with the server
      externalId: externalId,
      name: name,
      powerStats: await powerStats.fromChildJsonAmendment(
        _powerstatsField,
        amendment,
        parsingContext: parsingContext.next(_powerstatsField.name),
      ),
      biography: await biography.fromChildJsonAmendment(
        _biographyField,
        amendment,
        parsingContext: parsingContext.next(_biographyField.name),
      ),
      appearance: await appearance.fromChildJsonAmendment(
        _appearanceField,
        amendment,
        parsingContext: parsingContext.next(_appearanceField.name),
      ),
      work: await work.fromChildJsonAmendment(
        _workField,
        amendment,
        parsingContext: parsingContext.next(_workField.name),
      ),
      connections: await connections.fromChildJsonAmendment(
        _connectionsField,
        amendment,
        parsingContext: parsingContext.next(_connectionsField.name),
      ),
      image: await image.fromChildJsonAmendment(
        _imageField,
        amendment,
        parsingContext: parsingContext.next(_imageField.name),
      ),
    );
  }

  /// Call this to allow the hero to be synced with server again
  HeroModel unlock() {
    return copyWith(locked: false);
  }

  static Future<HeroModel> fromJson(Map<String, dynamic> json, DateTime timestamp) async {
    var id = Uuid().v4();
    var externalId = _externalIdField.getNullableString(json)!;
    var name = _nameField.getNullableString(json)!;
    var parsingContext = HeroParsingContext(id, externalId, name, true);
    return HeroModel(
      id: id,
      version: 1,
      timestamp: timestamp,
      locked: false,
      externalId: externalId,
      name: name,
      powerStats: PowerStatsModel.fromJson(
        _powerstatsField.getJson(json),
        parsingContext: parsingContext.next(_powerstatsField.name),
      ),
      biography: BiographyModel.fromJson(
        _biographyField.getJson(json),
        parsingContext: parsingContext.next(_biographyField.name),
      ),
      appearance: await AppearanceModel.fromJson(
        _appearanceField.getJson(json),
        parsingContext: parsingContext.next(_appearanceField.name),
      ),
      work: WorkModel.fromJson(
        _workField.getJson(json),
        parsingContext: parsingContext.next(_workField.name),
      ),
      connections: ConnectionsModel.fromJson(
        _connectionsField.getJson(json),
        parsingContext: parsingContext.next(_connectionsField.name),
      ),
      image: ImageModel.fromJson(
        _imageField.getJson(json),
        parsingContext: parsingContext.next(_imageField.name),
      ),
    );
  }

  static Future<HeroModel> fromJsonAndIdAsync(Map<String, dynamic> json, String id) async {
    var externalId = _externalIdField.getNullableString(json)!;
    var name = _nameField.getNullableString(json)!;
    var parsingContext = HeroParsingContext(id, externalId, name, true);
    return HeroModel(
      id: id,
      version: 1,
      timestamp: DateTime.timestamp(),
      locked: true, // Create in locked mode
      externalId: externalId,
      name: name,
      powerStats: PowerStatsModel.fromJson(
        _powerstatsField.getJson(json),
        parsingContext: parsingContext,
      ),
      biography: BiographyModel.fromJson(
        _biographyField.getJson(json),
        parsingContext: parsingContext,
      ),
      appearance: await AppearanceModel.fromJson(
        _appearanceField.getJson(json),
        parsingContext: parsingContext,
      ),
      work: WorkModel.fromJson(
        _workField.getJson(json),
        parsingContext: parsingContext,
      ),
      connections: ConnectionsModel.fromJson(
        _connectionsField.getJson(json),
        parsingContext: parsingContext,
      ),
      image: ImageModel.fromJson(
        _imageField.getJson(json),
        parsingContext: parsingContext,
      ),
    );
  }



  factory HeroModel.fromRow(Row row) {
    return HeroModel(
      version: _versionField.getIntFromRow(row, -1),
      timestamp: _timestampField.getDateTimeFromRow(row, DateTime.timestamp()),
      locked: _lockedField.getBoolFromRow(row, false),
      id: _idField.getNullableStringFromRow(row)!,
      externalId: _externalIdField.getNullableStringFromRow(row)!,
      name: _nameField.getNullableStringFromRow(row) as String,
      powerStats: PowerStatsModel.fromRow(row),
      biography: BiographyModel.fromRow(row),
      appearance: AppearanceModel.fromRow(row),
      work: WorkModel.fromRow(row),
      connections: ConnectionsModel.fromRow(row),
      image: ImageModel.fromRow(row),
    );
  }

  HeroModel.from(HeroModel other)
    : this(
        id: other.id,
        version: other.version,
        timestamp: other.timestamp,
        locked: other.locked,
        externalId: other.externalId,
        name: other.name,
        powerStats: PowerStatsModel.from(other.powerStats),
        biography: BiographyModel.from(other.biography),
        appearance: AppearanceModel.from(other.appearance),
        work: WorkModel.from(other.work),
        connections: ConnectionsModel.from(other.connections),
        image: ImageModel.from(other.image),
      );

  HeroModel copyWith({
    String? id,
    int? version,
    DateTime? timestamp,
    bool? locked,
    String? externalId,
    String? name,
    PowerStatsModel? powerStats,
    BiographyModel? biography,
    AppearanceModel? appearance,
    WorkModel? work,
    ConnectionsModel? connections,
    ImageModel? image,
  }) {
    return HeroModel(
      id: id ?? this.id,
      externalId: externalId ?? this.externalId,
      version: version ?? (this.version + 1),
      timestamp: timestamp ?? DateTime.timestamp(),
      locked:
          locked ??
          this.locked, // Any manual amendment locks the hero from synchronization with the server
      name: name ?? this.name,
      powerStats: powerStats ?? this.powerStats,
      biography: biography ?? this.biography,
      appearance: appearance ?? this.appearance,
      work: work ?? this.work,
      connections: connections ?? this.connections,
      image: image ?? this.image,
    );
  }

  @override
  int compareTo(HeroModel other) {
    int comparison = powerStats.compareTo(other.powerStats);
    if (comparison != 0) {
      return comparison;
    }

    // if powerStats are the same, sort other, fields ascending in order of significance which is
    // appearance, biography, id, externalId, version, name, work, connections, image
    // (id is before externalId as it is more unique, version is after externalId
    comparison = appearance.compareTo(other.appearance);
    if (comparison != 0) {
      return comparison;
    }
    comparison = biography.compareTo(other.biography);
    if (comparison != 0) {
      return comparison;
    }
    for (var field in [
      _idField,
      _externalIdField,
      _versionField,
      _lockedField,
      _nameField,
    ]) {
      comparison = field.compareField(this, other);
      if (comparison != 0) {
        return comparison;
      }
    }

    comparison = work.compareTo(other.work);
    if (comparison != 0) {
      return comparison;
    }
    comparison = connections.compareTo(other.connections);
    if (comparison != 0) {
      return comparison;
    }
    comparison = image.compareTo(other.image);
    if (comparison != 0) {
      return comparison;
    }

    return 0;
  }

  static Future<HeroModel?> fromPrompt() async {
    var json = await Amendable.promptForJson(staticFields);
    if (json == null) {
      return null;
    }

    return HeroModel.fromJsonAndIdAsync(json, Uuid().v4());
  }

  static String generateSQLiteInsertColumnPlaceholders() {
    return staticFields
        .map((f) => f.generateSQLiteInsertColumnPlaceholders())
        .join(',');
  }

  static String generateSqliteColumnNameList(String indent) {
    return '$indent${staticFields.map((f) => f.generateSqliteColumnNameList(indent)).join(',\n$indent')}\n';
  }

  static String generateSqliteColumnDeclarations(String indent) {
    return '$indent${staticFields.map((f) => f.generateSqliteColumnDeclarations(indent)).join(',\n$indent')}\n';
  }

  static String generateSqliteColumnDefinitions() {
    return '\n${staticFields.map((f) => {f.generateSqliteColumnDefinition()}).join(',\n')}\n';
  }

  static String generateSqliteUpdateClause(String indent) {
    return '${staticFields.where((c) => c.mutable).map((f) => f.generateSqliteUpdateClause(indent)).join(',\n$indent')}\n';
  }

  @override
  List<FieldBase<HeroModel>> get fields => staticFields;

  final String id;
  // "ID" field in JSON is "externalId" here to avoid confusion with our own "id" field.
  // It appears to be an integer in the JSON, but is actually a string.
  final String externalId;
  final int version;
  final DateTime timestamp;
  final bool
  locked; // Whether the hero is locked and not synchronized with the server
  final String name;
  final PowerStatsModel powerStats;
  final BiographyModel biography;
  final AppearanceModel appearance;
  final WorkModel work;
  final ConnectionsModel connections;
  final ImageModel image;

  static final FieldBase<HeroModel> _idField = Field.infer(
    // This is OUR unique ID, not the server ID. It is a UUID, not nullable or mutable per definition.
    (h) => h.id,
    "id",
    "UUID",
    primary: true,
  );

  static final FieldBase<HeroModel> _externalIdField = Field.infer(
    (h) => h.externalId,
    "External ID",
    "Server assigned string ID",
    // This is mapped to the ID field of the superhero API so it is not nullable or mutable.
    jsonName: "id",
    nullable: false,
    mutable: false,
  );

  static final FieldBase<HeroModel> _versionField = Field.infer(
    (h) => h.version,
    "Version",
    "Version number",
    assignedBySystem: true,
    comparable: false,
  );

  static final FieldBase<HeroModel> _timestampField = Field.infer(
    (h) => h.timestamp,
    "Timestamp",
    "UTC of last change to this hero",
    format: (h) => h.timestamp.toIso8601String(),
    sqliteGetter: (h) => h.timestamp.toIso8601String(),
    assignedBySystem: true,
    comparable: false,
  );

  static final FieldBase<HeroModel> _lockedField = Field.infer(
    (h) => h.locked,
    "Locked",
    "Whether the hero is locked and not synchronized with the server",
    sqliteGetter: (h) => h.locked ? 1 : 0,
    assignedBySystem: true,
    comparable: false,
  );

  static final FieldBase<HeroModel> _nameField = Field.infer(
    (h) => h.name,
    "Name",
    "Most commonly used name",
    nullable: false,
    showInSummary: true,
  );

  static final FieldBase<HeroModel> _powerstatsField = Field.infer(
    (h) => h.powerStats,
    "Powerstats",
    "Power statistics which is mostly misused",
    children: PowerStatsModel.staticFields,
    displayName: 'Power Stats',
  );

  static final FieldBase<HeroModel> _biographyField = Field.infer(
    (h) => h.biography,
    "Biography",
    "Hero's quite biased biography",
    format: (h) => "Biography: ${h.biography}",
    children: BiographyModel.staticFields,
  );

  static final FieldBase<HeroModel> _workField = Field.infer(
    (h) => h.work,
    "Work",
    "Hero's work",
    format: (h) => "Work: ${h.work}",
    children: WorkModel.staticFields,
  );

  static final FieldBase<HeroModel> _appearanceField = Field.infer(
    (h) => h.appearance,
    "Appearance",
    "Hero's appearance",
    format: (h) => "Appearance: ${h.appearance}",
    children: AppearanceModel.staticFields,
  );

  static final FieldBase<HeroModel> _connectionsField = Field.infer(
    (h) => h.connections,
    "Connections",
    "Hero's connections",
    format: (h) => "Connections: ${h.connections}",
    children: ConnectionsModel.staticFields,
  );

  static final FieldBase<HeroModel> _imageField = Field.infer(
    (h) => h.image,
    "Image",
    "Hero's image",
    format: (h) => "Image: ${h.image}",
    children: ImageModel.staticFields,
    showInDetail: false,
  );

  static final List<FieldBase<HeroModel>> staticFields = [
    _idField,
    _versionField,
    _timestampField,
    _lockedField,
    _externalIdField,
    _nameField,
    _powerstatsField,
    _biographyField,
    _appearanceField,
    _workField,
    _connectionsField,
    _imageField,
  ];
}
