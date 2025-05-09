// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, Track> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Untitled Track'),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('video'),
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isVisibleMeta = const VerificationMeta(
    'isVisible',
  );
  @override
  late final GeneratedColumn<bool> isVisible = GeneratedColumn<bool>(
    'is_visible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_visible" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isLockedMeta = const VerificationMeta(
    'isLocked',
  );
  @override
  late final GeneratedColumn<bool> isLocked = GeneratedColumn<bool>(
    'is_locked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_locked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    order,
    isVisible,
    isLocked,
    metadataJson,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Track> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    } else if (isInserting) {
      context.missing(_orderMeta);
    }
    if (data.containsKey('is_visible')) {
      context.handle(
        _isVisibleMeta,
        isVisible.isAcceptableOrUnknown(data['is_visible']!, _isVisibleMeta),
      );
    }
    if (data.containsKey('is_locked')) {
      context.handle(
        _isLockedMeta,
        isLocked.isAcceptableOrUnknown(data['is_locked']!, _isLockedMeta),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Track map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Track(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      order:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}order'],
          )!,
      isVisible:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_visible'],
          )!,
      isLocked:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_locked'],
          )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class Track extends DataClass implements Insertable<Track> {
  final int id;
  final String name;
  final String type;
  final int order;
  final bool isVisible;
  final bool isLocked;
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Track({
    required this.id,
    required this.name,
    required this.type,
    required this.order,
    required this.isVisible,
    required this.isLocked,
    this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['order'] = Variable<int>(order);
    map['is_visible'] = Variable<bool>(isVisible);
    map['is_locked'] = Variable<bool>(isLocked);
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      order: Value(order),
      isVisible: Value(isVisible),
      isLocked: Value(isLocked),
      metadataJson:
          metadataJson == null && nullToAbsent
              ? const Value.absent()
              : Value(metadataJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Track.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Track(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      order: serializer.fromJson<int>(json['order']),
      isVisible: serializer.fromJson<bool>(json['isVisible']),
      isLocked: serializer.fromJson<bool>(json['isLocked']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'order': serializer.toJson<int>(order),
      'isVisible': serializer.toJson<bool>(isVisible),
      'isLocked': serializer.toJson<bool>(isLocked),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Track copyWith({
    int? id,
    String? name,
    String? type,
    int? order,
    bool? isVisible,
    bool? isLocked,
    Value<String?> metadataJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Track(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    order: order ?? this.order,
    isVisible: isVisible ?? this.isVisible,
    isLocked: isLocked ?? this.isLocked,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Track copyWithCompanion(TracksCompanion data) {
    return Track(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      order: data.order.present ? data.order.value : this.order,
      isVisible: data.isVisible.present ? data.isVisible.value : this.isVisible,
      isLocked: data.isLocked.present ? data.isLocked.value : this.isLocked,
      metadataJson:
          data.metadataJson.present
              ? data.metadataJson.value
              : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Track(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('order: $order, ')
          ..write('isVisible: $isVisible, ')
          ..write('isLocked: $isLocked, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    order,
    isVisible,
    isLocked,
    metadataJson,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.order == this.order &&
          other.isVisible == this.isVisible &&
          other.isLocked == this.isLocked &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TracksCompanion extends UpdateCompanion<Track> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> type;
  final Value<int> order;
  final Value<bool> isVisible;
  final Value<bool> isLocked;
  final Value<String?> metadataJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.order = const Value.absent(),
    this.isVisible = const Value.absent(),
    this.isLocked = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TracksCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    required int order,
    this.isVisible = const Value.absent(),
    this.isLocked = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : order = Value(order);
  static Insertable<Track> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<int>? order,
    Expression<bool>? isVisible,
    Expression<bool>? isLocked,
    Expression<String>? metadataJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (order != null) 'order': order,
      if (isVisible != null) 'is_visible': isVisible,
      if (isLocked != null) 'is_locked': isLocked,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TracksCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? type,
    Value<int>? order,
    Value<bool>? isVisible,
    Value<bool>? isLocked,
    Value<String?>? metadataJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      order: order ?? this.order,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    if (isVisible.present) {
      map['is_visible'] = Variable<bool>(isVisible.value);
    }
    if (isLocked.present) {
      map['is_locked'] = Variable<bool>(isLocked.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('order: $order, ')
          ..write('isVisible: $isVisible, ')
          ..write('isLocked: $isLocked, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ClipsTable extends Clips with TableInfo<$ClipsTable, Clip> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Untitled Clip'),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('video'),
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDurationMsMeta = const VerificationMeta(
    'sourceDurationMs',
  );
  @override
  late final GeneratedColumn<int> sourceDurationMs = GeneratedColumn<int>(
    'source_duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startTimeInSourceMsMeta =
      const VerificationMeta('startTimeInSourceMs');
  @override
  late final GeneratedColumn<int> startTimeInSourceMs = GeneratedColumn<int>(
    'start_time_in_source_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeInSourceMsMeta = const VerificationMeta(
    'endTimeInSourceMs',
  );
  @override
  late final GeneratedColumn<int> endTimeInSourceMs = GeneratedColumn<int>(
    'end_time_in_source_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeOnTrackMsMeta =
      const VerificationMeta('startTimeOnTrackMs');
  @override
  late final GeneratedColumn<int> startTimeOnTrackMs = GeneratedColumn<int>(
    'start_time_on_track_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _endTimeOnTrackMsMeta = const VerificationMeta(
    'endTimeOnTrackMs',
  );
  @override
  late final GeneratedColumn<int> endTimeOnTrackMs = GeneratedColumn<int>(
    'end_time_on_track_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
    'metadata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _previewPositionXMeta = const VerificationMeta(
    'previewPositionX',
  );
  @override
  late final GeneratedColumn<double> previewPositionX = GeneratedColumn<double>(
    'preview_position_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _previewPositionYMeta = const VerificationMeta(
    'previewPositionY',
  );
  @override
  late final GeneratedColumn<double> previewPositionY = GeneratedColumn<double>(
    'preview_position_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _previewWidthMeta = const VerificationMeta(
    'previewWidth',
  );
  @override
  late final GeneratedColumn<double> previewWidth = GeneratedColumn<double>(
    'preview_width',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(100.0),
  );
  static const VerificationMeta _previewHeightMeta = const VerificationMeta(
    'previewHeight',
  );
  @override
  late final GeneratedColumn<double> previewHeight = GeneratedColumn<double>(
    'preview_height',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(100.0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    trackId,
    name,
    type,
    sourcePath,
    sourceDurationMs,
    startTimeInSourceMs,
    endTimeInSourceMs,
    startTimeOnTrackMs,
    endTimeOnTrackMs,
    metadata,
    previewPositionX,
    previewPositionY,
    previewWidth,
    previewHeight,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clips';
  @override
  VerificationContext validateIntegrity(
    Insertable<Clip> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('source_duration_ms')) {
      context.handle(
        _sourceDurationMsMeta,
        sourceDurationMs.isAcceptableOrUnknown(
          data['source_duration_ms']!,
          _sourceDurationMsMeta,
        ),
      );
    }
    if (data.containsKey('start_time_in_source_ms')) {
      context.handle(
        _startTimeInSourceMsMeta,
        startTimeInSourceMs.isAcceptableOrUnknown(
          data['start_time_in_source_ms']!,
          _startTimeInSourceMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startTimeInSourceMsMeta);
    }
    if (data.containsKey('end_time_in_source_ms')) {
      context.handle(
        _endTimeInSourceMsMeta,
        endTimeInSourceMs.isAcceptableOrUnknown(
          data['end_time_in_source_ms']!,
          _endTimeInSourceMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endTimeInSourceMsMeta);
    }
    if (data.containsKey('start_time_on_track_ms')) {
      context.handle(
        _startTimeOnTrackMsMeta,
        startTimeOnTrackMs.isAcceptableOrUnknown(
          data['start_time_on_track_ms']!,
          _startTimeOnTrackMsMeta,
        ),
      );
    }
    if (data.containsKey('end_time_on_track_ms')) {
      context.handle(
        _endTimeOnTrackMsMeta,
        endTimeOnTrackMs.isAcceptableOrUnknown(
          data['end_time_on_track_ms']!,
          _endTimeOnTrackMsMeta,
        ),
      );
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    }
    if (data.containsKey('preview_position_x')) {
      context.handle(
        _previewPositionXMeta,
        previewPositionX.isAcceptableOrUnknown(
          data['preview_position_x']!,
          _previewPositionXMeta,
        ),
      );
    }
    if (data.containsKey('preview_position_y')) {
      context.handle(
        _previewPositionYMeta,
        previewPositionY.isAcceptableOrUnknown(
          data['preview_position_y']!,
          _previewPositionYMeta,
        ),
      );
    }
    if (data.containsKey('preview_width')) {
      context.handle(
        _previewWidthMeta,
        previewWidth.isAcceptableOrUnknown(
          data['preview_width']!,
          _previewWidthMeta,
        ),
      );
    }
    if (data.containsKey('preview_height')) {
      context.handle(
        _previewHeightMeta,
        previewHeight.isAcceptableOrUnknown(
          data['preview_height']!,
          _previewHeightMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Clip map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Clip(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      trackId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}track_id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      sourcePath:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source_path'],
          )!,
      sourceDurationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_duration_ms'],
      ),
      startTimeInSourceMs:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}start_time_in_source_ms'],
          )!,
      endTimeInSourceMs:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}end_time_in_source_ms'],
          )!,
      startTimeOnTrackMs:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}start_time_on_track_ms'],
          )!,
      endTimeOnTrackMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_time_on_track_ms'],
      ),
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata'],
      ),
      previewPositionX:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}preview_position_x'],
          )!,
      previewPositionY:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}preview_position_y'],
          )!,
      previewWidth:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}preview_width'],
          )!,
      previewHeight:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}preview_height'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $ClipsTable createAlias(String alias) {
    return $ClipsTable(attachedDatabase, alias);
  }
}

class Clip extends DataClass implements Insertable<Clip> {
  final int id;
  final int trackId;
  final String name;
  final String type;
  final String sourcePath;
  final int? sourceDurationMs;
  final int startTimeInSourceMs;
  final int endTimeInSourceMs;
  final int startTimeOnTrackMs;
  final int? endTimeOnTrackMs;
  final String? metadata;
  final double previewPositionX;
  final double previewPositionY;
  final double previewWidth;
  final double previewHeight;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Clip({
    required this.id,
    required this.trackId,
    required this.name,
    required this.type,
    required this.sourcePath,
    this.sourceDurationMs,
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
    required this.startTimeOnTrackMs,
    this.endTimeOnTrackMs,
    this.metadata,
    required this.previewPositionX,
    required this.previewPositionY,
    required this.previewWidth,
    required this.previewHeight,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_id'] = Variable<int>(trackId);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['source_path'] = Variable<String>(sourcePath);
    if (!nullToAbsent || sourceDurationMs != null) {
      map['source_duration_ms'] = Variable<int>(sourceDurationMs);
    }
    map['start_time_in_source_ms'] = Variable<int>(startTimeInSourceMs);
    map['end_time_in_source_ms'] = Variable<int>(endTimeInSourceMs);
    map['start_time_on_track_ms'] = Variable<int>(startTimeOnTrackMs);
    if (!nullToAbsent || endTimeOnTrackMs != null) {
      map['end_time_on_track_ms'] = Variable<int>(endTimeOnTrackMs);
    }
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    map['preview_position_x'] = Variable<double>(previewPositionX);
    map['preview_position_y'] = Variable<double>(previewPositionY);
    map['preview_width'] = Variable<double>(previewWidth);
    map['preview_height'] = Variable<double>(previewHeight);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ClipsCompanion toCompanion(bool nullToAbsent) {
    return ClipsCompanion(
      id: Value(id),
      trackId: Value(trackId),
      name: Value(name),
      type: Value(type),
      sourcePath: Value(sourcePath),
      sourceDurationMs:
          sourceDurationMs == null && nullToAbsent
              ? const Value.absent()
              : Value(sourceDurationMs),
      startTimeInSourceMs: Value(startTimeInSourceMs),
      endTimeInSourceMs: Value(endTimeInSourceMs),
      startTimeOnTrackMs: Value(startTimeOnTrackMs),
      endTimeOnTrackMs:
          endTimeOnTrackMs == null && nullToAbsent
              ? const Value.absent()
              : Value(endTimeOnTrackMs),
      metadata:
          metadata == null && nullToAbsent
              ? const Value.absent()
              : Value(metadata),
      previewPositionX: Value(previewPositionX),
      previewPositionY: Value(previewPositionY),
      previewWidth: Value(previewWidth),
      previewHeight: Value(previewHeight),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Clip.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Clip(
      id: serializer.fromJson<int>(json['id']),
      trackId: serializer.fromJson<int>(json['trackId']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      sourceDurationMs: serializer.fromJson<int?>(json['sourceDurationMs']),
      startTimeInSourceMs: serializer.fromJson<int>(
        json['startTimeInSourceMs'],
      ),
      endTimeInSourceMs: serializer.fromJson<int>(json['endTimeInSourceMs']),
      startTimeOnTrackMs: serializer.fromJson<int>(json['startTimeOnTrackMs']),
      endTimeOnTrackMs: serializer.fromJson<int?>(json['endTimeOnTrackMs']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      previewPositionX: serializer.fromJson<double>(json['previewPositionX']),
      previewPositionY: serializer.fromJson<double>(json['previewPositionY']),
      previewWidth: serializer.fromJson<double>(json['previewWidth']),
      previewHeight: serializer.fromJson<double>(json['previewHeight']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackId': serializer.toJson<int>(trackId),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'sourceDurationMs': serializer.toJson<int?>(sourceDurationMs),
      'startTimeInSourceMs': serializer.toJson<int>(startTimeInSourceMs),
      'endTimeInSourceMs': serializer.toJson<int>(endTimeInSourceMs),
      'startTimeOnTrackMs': serializer.toJson<int>(startTimeOnTrackMs),
      'endTimeOnTrackMs': serializer.toJson<int?>(endTimeOnTrackMs),
      'metadata': serializer.toJson<String?>(metadata),
      'previewPositionX': serializer.toJson<double>(previewPositionX),
      'previewPositionY': serializer.toJson<double>(previewPositionY),
      'previewWidth': serializer.toJson<double>(previewWidth),
      'previewHeight': serializer.toJson<double>(previewHeight),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Clip copyWith({
    int? id,
    int? trackId,
    String? name,
    String? type,
    String? sourcePath,
    Value<int?> sourceDurationMs = const Value.absent(),
    int? startTimeInSourceMs,
    int? endTimeInSourceMs,
    int? startTimeOnTrackMs,
    Value<int?> endTimeOnTrackMs = const Value.absent(),
    Value<String?> metadata = const Value.absent(),
    double? previewPositionX,
    double? previewPositionY,
    double? previewWidth,
    double? previewHeight,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Clip(
    id: id ?? this.id,
    trackId: trackId ?? this.trackId,
    name: name ?? this.name,
    type: type ?? this.type,
    sourcePath: sourcePath ?? this.sourcePath,
    sourceDurationMs:
        sourceDurationMs.present
            ? sourceDurationMs.value
            : this.sourceDurationMs,
    startTimeInSourceMs: startTimeInSourceMs ?? this.startTimeInSourceMs,
    endTimeInSourceMs: endTimeInSourceMs ?? this.endTimeInSourceMs,
    startTimeOnTrackMs: startTimeOnTrackMs ?? this.startTimeOnTrackMs,
    endTimeOnTrackMs:
        endTimeOnTrackMs.present
            ? endTimeOnTrackMs.value
            : this.endTimeOnTrackMs,
    metadata: metadata.present ? metadata.value : this.metadata,
    previewPositionX: previewPositionX ?? this.previewPositionX,
    previewPositionY: previewPositionY ?? this.previewPositionY,
    previewWidth: previewWidth ?? this.previewWidth,
    previewHeight: previewHeight ?? this.previewHeight,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Clip copyWithCompanion(ClipsCompanion data) {
    return Clip(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      sourcePath:
          data.sourcePath.present ? data.sourcePath.value : this.sourcePath,
      sourceDurationMs:
          data.sourceDurationMs.present
              ? data.sourceDurationMs.value
              : this.sourceDurationMs,
      startTimeInSourceMs:
          data.startTimeInSourceMs.present
              ? data.startTimeInSourceMs.value
              : this.startTimeInSourceMs,
      endTimeInSourceMs:
          data.endTimeInSourceMs.present
              ? data.endTimeInSourceMs.value
              : this.endTimeInSourceMs,
      startTimeOnTrackMs:
          data.startTimeOnTrackMs.present
              ? data.startTimeOnTrackMs.value
              : this.startTimeOnTrackMs,
      endTimeOnTrackMs:
          data.endTimeOnTrackMs.present
              ? data.endTimeOnTrackMs.value
              : this.endTimeOnTrackMs,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      previewPositionX:
          data.previewPositionX.present
              ? data.previewPositionX.value
              : this.previewPositionX,
      previewPositionY:
          data.previewPositionY.present
              ? data.previewPositionY.value
              : this.previewPositionY,
      previewWidth:
          data.previewWidth.present
              ? data.previewWidth.value
              : this.previewWidth,
      previewHeight:
          data.previewHeight.present
              ? data.previewHeight.value
              : this.previewHeight,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Clip(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceDurationMs: $sourceDurationMs, ')
          ..write('startTimeInSourceMs: $startTimeInSourceMs, ')
          ..write('endTimeInSourceMs: $endTimeInSourceMs, ')
          ..write('startTimeOnTrackMs: $startTimeOnTrackMs, ')
          ..write('endTimeOnTrackMs: $endTimeOnTrackMs, ')
          ..write('metadata: $metadata, ')
          ..write('previewPositionX: $previewPositionX, ')
          ..write('previewPositionY: $previewPositionY, ')
          ..write('previewWidth: $previewWidth, ')
          ..write('previewHeight: $previewHeight, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    trackId,
    name,
    type,
    sourcePath,
    sourceDurationMs,
    startTimeInSourceMs,
    endTimeInSourceMs,
    startTimeOnTrackMs,
    endTimeOnTrackMs,
    metadata,
    previewPositionX,
    previewPositionY,
    previewWidth,
    previewHeight,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Clip &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.name == this.name &&
          other.type == this.type &&
          other.sourcePath == this.sourcePath &&
          other.sourceDurationMs == this.sourceDurationMs &&
          other.startTimeInSourceMs == this.startTimeInSourceMs &&
          other.endTimeInSourceMs == this.endTimeInSourceMs &&
          other.startTimeOnTrackMs == this.startTimeOnTrackMs &&
          other.endTimeOnTrackMs == this.endTimeOnTrackMs &&
          other.metadata == this.metadata &&
          other.previewPositionX == this.previewPositionX &&
          other.previewPositionY == this.previewPositionY &&
          other.previewWidth == this.previewWidth &&
          other.previewHeight == this.previewHeight &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ClipsCompanion extends UpdateCompanion<Clip> {
  final Value<int> id;
  final Value<int> trackId;
  final Value<String> name;
  final Value<String> type;
  final Value<String> sourcePath;
  final Value<int?> sourceDurationMs;
  final Value<int> startTimeInSourceMs;
  final Value<int> endTimeInSourceMs;
  final Value<int> startTimeOnTrackMs;
  final Value<int?> endTimeOnTrackMs;
  final Value<String?> metadata;
  final Value<double> previewPositionX;
  final Value<double> previewPositionY;
  final Value<double> previewWidth;
  final Value<double> previewHeight;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ClipsCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.sourceDurationMs = const Value.absent(),
    this.startTimeInSourceMs = const Value.absent(),
    this.endTimeInSourceMs = const Value.absent(),
    this.startTimeOnTrackMs = const Value.absent(),
    this.endTimeOnTrackMs = const Value.absent(),
    this.metadata = const Value.absent(),
    this.previewPositionX = const Value.absent(),
    this.previewPositionY = const Value.absent(),
    this.previewWidth = const Value.absent(),
    this.previewHeight = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ClipsCompanion.insert({
    this.id = const Value.absent(),
    required int trackId,
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    required String sourcePath,
    this.sourceDurationMs = const Value.absent(),
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
    this.startTimeOnTrackMs = const Value.absent(),
    this.endTimeOnTrackMs = const Value.absent(),
    this.metadata = const Value.absent(),
    this.previewPositionX = const Value.absent(),
    this.previewPositionY = const Value.absent(),
    this.previewWidth = const Value.absent(),
    this.previewHeight = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : trackId = Value(trackId),
       sourcePath = Value(sourcePath),
       startTimeInSourceMs = Value(startTimeInSourceMs),
       endTimeInSourceMs = Value(endTimeInSourceMs);
  static Insertable<Clip> custom({
    Expression<int>? id,
    Expression<int>? trackId,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? sourcePath,
    Expression<int>? sourceDurationMs,
    Expression<int>? startTimeInSourceMs,
    Expression<int>? endTimeInSourceMs,
    Expression<int>? startTimeOnTrackMs,
    Expression<int>? endTimeOnTrackMs,
    Expression<String>? metadata,
    Expression<double>? previewPositionX,
    Expression<double>? previewPositionY,
    Expression<double>? previewWidth,
    Expression<double>? previewHeight,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (sourcePath != null) 'source_path': sourcePath,
      if (sourceDurationMs != null) 'source_duration_ms': sourceDurationMs,
      if (startTimeInSourceMs != null)
        'start_time_in_source_ms': startTimeInSourceMs,
      if (endTimeInSourceMs != null) 'end_time_in_source_ms': endTimeInSourceMs,
      if (startTimeOnTrackMs != null)
        'start_time_on_track_ms': startTimeOnTrackMs,
      if (endTimeOnTrackMs != null) 'end_time_on_track_ms': endTimeOnTrackMs,
      if (metadata != null) 'metadata': metadata,
      if (previewPositionX != null) 'preview_position_x': previewPositionX,
      if (previewPositionY != null) 'preview_position_y': previewPositionY,
      if (previewWidth != null) 'preview_width': previewWidth,
      if (previewHeight != null) 'preview_height': previewHeight,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ClipsCompanion copyWith({
    Value<int>? id,
    Value<int>? trackId,
    Value<String>? name,
    Value<String>? type,
    Value<String>? sourcePath,
    Value<int?>? sourceDurationMs,
    Value<int>? startTimeInSourceMs,
    Value<int>? endTimeInSourceMs,
    Value<int>? startTimeOnTrackMs,
    Value<int?>? endTimeOnTrackMs,
    Value<String?>? metadata,
    Value<double>? previewPositionX,
    Value<double>? previewPositionY,
    Value<double>? previewWidth,
    Value<double>? previewHeight,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ClipsCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      type: type ?? this.type,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
      startTimeInSourceMs: startTimeInSourceMs ?? this.startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs ?? this.endTimeInSourceMs,
      startTimeOnTrackMs: startTimeOnTrackMs ?? this.startTimeOnTrackMs,
      endTimeOnTrackMs: endTimeOnTrackMs ?? this.endTimeOnTrackMs,
      metadata: metadata ?? this.metadata,
      previewPositionX: previewPositionX ?? this.previewPositionX,
      previewPositionY: previewPositionY ?? this.previewPositionY,
      previewWidth: previewWidth ?? this.previewWidth,
      previewHeight: previewHeight ?? this.previewHeight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (sourceDurationMs.present) {
      map['source_duration_ms'] = Variable<int>(sourceDurationMs.value);
    }
    if (startTimeInSourceMs.present) {
      map['start_time_in_source_ms'] = Variable<int>(startTimeInSourceMs.value);
    }
    if (endTimeInSourceMs.present) {
      map['end_time_in_source_ms'] = Variable<int>(endTimeInSourceMs.value);
    }
    if (startTimeOnTrackMs.present) {
      map['start_time_on_track_ms'] = Variable<int>(startTimeOnTrackMs.value);
    }
    if (endTimeOnTrackMs.present) {
      map['end_time_on_track_ms'] = Variable<int>(endTimeOnTrackMs.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (previewPositionX.present) {
      map['preview_position_x'] = Variable<double>(previewPositionX.value);
    }
    if (previewPositionY.present) {
      map['preview_position_y'] = Variable<double>(previewPositionY.value);
    }
    if (previewWidth.present) {
      map['preview_width'] = Variable<double>(previewWidth.value);
    }
    if (previewHeight.present) {
      map['preview_height'] = Variable<double>(previewHeight.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClipsCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceDurationMs: $sourceDurationMs, ')
          ..write('startTimeInSourceMs: $startTimeInSourceMs, ')
          ..write('endTimeInSourceMs: $endTimeInSourceMs, ')
          ..write('startTimeOnTrackMs: $startTimeOnTrackMs, ')
          ..write('endTimeOnTrackMs: $endTimeOnTrackMs, ')
          ..write('metadata: $metadata, ')
          ..write('previewPositionX: $previewPositionX, ')
          ..write('previewPositionY: $previewPositionY, ')
          ..write('previewWidth: $previewWidth, ')
          ..write('previewHeight: $previewHeight, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProjectAssetsTable extends ProjectAssets
    with TableInfo<$ProjectAssetsTable, ProjectAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<double> fileSize = GeneratedColumn<double>(
    'file_size',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    sourcePath,
    type,
    mimeType,
    durationMs,
    width,
    height,
    fileSize,
    metadataJson,
    thumbnailPath,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectAsset(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      sourcePath:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source_path'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}file_size'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $ProjectAssetsTable createAlias(String alias) {
    return $ProjectAssetsTable(attachedDatabase, alias);
  }
}

class ProjectAsset extends DataClass implements Insertable<ProjectAsset> {
  final int id;
  final String name;
  final String sourcePath;
  final String type;
  final String? mimeType;
  final int? durationMs;
  final int? width;
  final int? height;
  final double? fileSize;
  final String? metadataJson;
  final String? thumbnailPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ProjectAsset({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.type,
    this.mimeType,
    this.durationMs,
    this.width,
    this.height,
    this.fileSize,
    this.metadataJson,
    this.thumbnailPath,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['source_path'] = Variable<String>(sourcePath);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<double>(fileSize);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectAssetsCompanion toCompanion(bool nullToAbsent) {
    return ProjectAssetsCompanion(
      id: Value(id),
      name: Value(name),
      sourcePath: Value(sourcePath),
      type: Value(type),
      mimeType:
          mimeType == null && nullToAbsent
              ? const Value.absent()
              : Value(mimeType),
      durationMs:
          durationMs == null && nullToAbsent
              ? const Value.absent()
              : Value(durationMs),
      width:
          width == null && nullToAbsent ? const Value.absent() : Value(width),
      height:
          height == null && nullToAbsent ? const Value.absent() : Value(height),
      fileSize:
          fileSize == null && nullToAbsent
              ? const Value.absent()
              : Value(fileSize),
      metadataJson:
          metadataJson == null && nullToAbsent
              ? const Value.absent()
              : Value(metadataJson),
      thumbnailPath:
          thumbnailPath == null && nullToAbsent
              ? const Value.absent()
              : Value(thumbnailPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProjectAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectAsset(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      type: serializer.fromJson<String>(json['type']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      fileSize: serializer.fromJson<double?>(json['fileSize']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'type': serializer.toJson<String>(type),
      'mimeType': serializer.toJson<String?>(mimeType),
      'durationMs': serializer.toJson<int?>(durationMs),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'fileSize': serializer.toJson<double?>(fileSize),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProjectAsset copyWith({
    int? id,
    String? name,
    String? sourcePath,
    String? type,
    Value<String?> mimeType = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<double?> fileSize = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProjectAsset(
    id: id ?? this.id,
    name: name ?? this.name,
    sourcePath: sourcePath ?? this.sourcePath,
    type: type ?? this.type,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    fileSize: fileSize.present ? fileSize.value : this.fileSize,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    thumbnailPath:
        thumbnailPath.present ? thumbnailPath.value : this.thumbnailPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProjectAsset copyWithCompanion(ProjectAssetsCompanion data) {
    return ProjectAsset(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sourcePath:
          data.sourcePath.present ? data.sourcePath.value : this.sourcePath,
      type: data.type.present ? data.type.value : this.type,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      metadataJson:
          data.metadataJson.present
              ? data.metadataJson.value
              : this.metadataJson,
      thumbnailPath:
          data.thumbnailPath.present
              ? data.thumbnailPath.value
              : this.thumbnailPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectAsset(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('type: $type, ')
          ..write('mimeType: $mimeType, ')
          ..write('durationMs: $durationMs, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSize: $fileSize, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    sourcePath,
    type,
    mimeType,
    durationMs,
    width,
    height,
    fileSize,
    metadataJson,
    thumbnailPath,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectAsset &&
          other.id == this.id &&
          other.name == this.name &&
          other.sourcePath == this.sourcePath &&
          other.type == this.type &&
          other.mimeType == this.mimeType &&
          other.durationMs == this.durationMs &&
          other.width == this.width &&
          other.height == this.height &&
          other.fileSize == this.fileSize &&
          other.metadataJson == this.metadataJson &&
          other.thumbnailPath == this.thumbnailPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectAssetsCompanion extends UpdateCompanion<ProjectAsset> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> sourcePath;
  final Value<String> type;
  final Value<String?> mimeType;
  final Value<int?> durationMs;
  final Value<int?> width;
  final Value<int?> height;
  final Value<double?> fileSize;
  final Value<String?> metadataJson;
  final Value<String?> thumbnailPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ProjectAssetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.type = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProjectAssetsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String sourcePath,
    required String type,
    this.mimeType = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name),
       sourcePath = Value(sourcePath),
       type = Value(type);
  static Insertable<ProjectAsset> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? sourcePath,
    Expression<String>? type,
    Expression<String>? mimeType,
    Expression<int>? durationMs,
    Expression<int>? width,
    Expression<int>? height,
    Expression<double>? fileSize,
    Expression<String>? metadataJson,
    Expression<String>? thumbnailPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sourcePath != null) 'source_path': sourcePath,
      if (type != null) 'type': type,
      if (mimeType != null) 'mime_type': mimeType,
      if (durationMs != null) 'duration_ms': durationMs,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (fileSize != null) 'file_size': fileSize,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProjectAssetsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? sourcePath,
    Value<String>? type,
    Value<String?>? mimeType,
    Value<int?>? durationMs,
    Value<int?>? width,
    Value<int?>? height,
    Value<double?>? fileSize,
    Value<String?>? metadataJson,
    Value<String?>? thumbnailPath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ProjectAssetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sourcePath: sourcePath ?? this.sourcePath,
      type: type ?? this.type,
      mimeType: mimeType ?? this.mimeType,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      metadataJson: metadataJson ?? this.metadataJson,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<double>(fileSize.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectAssetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('type: $type, ')
          ..write('mimeType: $mimeType, ')
          ..write('durationMs: $durationMs, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSize: $fileSize, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ChangeLogsTable extends ChangeLogs
    with TableInfo<$ChangeLogsTable, ChangeLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChangeLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oldDataMeta = const VerificationMeta(
    'oldData',
  );
  @override
  late final GeneratedColumn<String> oldData = GeneratedColumn<String>(
    'old_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _newDataMeta = const VerificationMeta(
    'newData',
  );
  @override
  late final GeneratedColumn<String> newData = GeneratedColumn<String>(
    'new_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entity,
    entityId,
    action,
    oldData,
    newData,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'change_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChangeLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('old_data')) {
      context.handle(
        _oldDataMeta,
        oldData.isAcceptableOrUnknown(data['old_data']!, _oldDataMeta),
      );
    }
    if (data.containsKey('new_data')) {
      context.handle(
        _newDataMeta,
        newData.isAcceptableOrUnknown(data['new_data']!, _newDataMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChangeLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChangeLog(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      entity:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}entity'],
          )!,
      entityId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}entity_id'],
          )!,
      action:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}action'],
          )!,
      oldData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}old_data'],
      ),
      newData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_data'],
      ),
      timestamp:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}timestamp'],
          )!,
    );
  }

  @override
  $ChangeLogsTable createAlias(String alias) {
    return $ChangeLogsTable(attachedDatabase, alias);
  }
}

class ChangeLog extends DataClass implements Insertable<ChangeLog> {
  final int id;
  final String entity;
  final String entityId;
  final String action;
  final String? oldData;
  final String? newData;
  final int timestamp;
  const ChangeLog({
    required this.id,
    required this.entity,
    required this.entityId,
    required this.action,
    this.oldData,
    this.newData,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || oldData != null) {
      map['old_data'] = Variable<String>(oldData);
    }
    if (!nullToAbsent || newData != null) {
      map['new_data'] = Variable<String>(newData);
    }
    map['timestamp'] = Variable<int>(timestamp);
    return map;
  }

  ChangeLogsCompanion toCompanion(bool nullToAbsent) {
    return ChangeLogsCompanion(
      id: Value(id),
      entity: Value(entity),
      entityId: Value(entityId),
      action: Value(action),
      oldData:
          oldData == null && nullToAbsent
              ? const Value.absent()
              : Value(oldData),
      newData:
          newData == null && nullToAbsent
              ? const Value.absent()
              : Value(newData),
      timestamp: Value(timestamp),
    );
  }

  factory ChangeLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChangeLog(
      id: serializer.fromJson<int>(json['id']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      oldData: serializer.fromJson<String?>(json['oldData']),
      newData: serializer.fromJson<String?>(json['newData']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'oldData': serializer.toJson<String?>(oldData),
      'newData': serializer.toJson<String?>(newData),
      'timestamp': serializer.toJson<int>(timestamp),
    };
  }

  ChangeLog copyWith({
    int? id,
    String? entity,
    String? entityId,
    String? action,
    Value<String?> oldData = const Value.absent(),
    Value<String?> newData = const Value.absent(),
    int? timestamp,
  }) => ChangeLog(
    id: id ?? this.id,
    entity: entity ?? this.entity,
    entityId: entityId ?? this.entityId,
    action: action ?? this.action,
    oldData: oldData.present ? oldData.value : this.oldData,
    newData: newData.present ? newData.value : this.newData,
    timestamp: timestamp ?? this.timestamp,
  );
  ChangeLog copyWithCompanion(ChangeLogsCompanion data) {
    return ChangeLog(
      id: data.id.present ? data.id.value : this.id,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      oldData: data.oldData.present ? data.oldData.value : this.oldData,
      newData: data.newData.present ? data.newData.value : this.newData,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChangeLog(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('oldData: $oldData, ')
          ..write('newData: $newData, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, entity, entityId, action, oldData, newData, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChangeLog &&
          other.id == this.id &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.oldData == this.oldData &&
          other.newData == this.newData &&
          other.timestamp == this.timestamp);
}

class ChangeLogsCompanion extends UpdateCompanion<ChangeLog> {
  final Value<int> id;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> action;
  final Value<String?> oldData;
  final Value<String?> newData;
  final Value<int> timestamp;
  const ChangeLogsCompanion({
    this.id = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.oldData = const Value.absent(),
    this.newData = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  ChangeLogsCompanion.insert({
    this.id = const Value.absent(),
    required String entity,
    required String entityId,
    required String action,
    this.oldData = const Value.absent(),
    this.newData = const Value.absent(),
    required int timestamp,
  }) : entity = Value(entity),
       entityId = Value(entityId),
       action = Value(action),
       timestamp = Value(timestamp);
  static Insertable<ChangeLog> custom({
    Expression<int>? id,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<String>? oldData,
    Expression<String>? newData,
    Expression<int>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (oldData != null) 'old_data': oldData,
      if (newData != null) 'new_data': newData,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  ChangeLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? entity,
    Value<String>? entityId,
    Value<String>? action,
    Value<String?>? oldData,
    Value<String?>? newData,
    Value<int>? timestamp,
  }) {
    return ChangeLogsCompanion(
      id: id ?? this.id,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      oldData: oldData ?? this.oldData,
      newData: newData ?? this.newData,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (oldData.present) {
      map['old_data'] = Variable<String>(oldData.value);
    }
    if (newData.present) {
      map['new_data'] = Variable<String>(newData.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChangeLogsCompanion(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('oldData: $oldData, ')
          ..write('newData: $newData, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProjectDatabase extends GeneratedDatabase {
  _$ProjectDatabase(QueryExecutor e) : super(e);
  $ProjectDatabaseManager get managers => $ProjectDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $ClipsTable clips = $ClipsTable(this);
  late final $ProjectAssetsTable projectAssets = $ProjectAssetsTable(this);
  late final $ChangeLogsTable changeLogs = $ChangeLogsTable(this);
  late final ProjectDatabaseTrackDao projectDatabaseTrackDao =
      ProjectDatabaseTrackDao(this as ProjectDatabase);
  late final ProjectDatabaseClipDao projectDatabaseClipDao =
      ProjectDatabaseClipDao(this as ProjectDatabase);
  late final ProjectDatabaseAssetDao projectDatabaseAssetDao =
      ProjectDatabaseAssetDao(this as ProjectDatabase);
  late final ChangeLogDao changeLogDao = ChangeLogDao(this as ProjectDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    clips,
    projectAssets,
    changeLogs,
  ];
}

typedef $$TracksTableCreateCompanionBuilder =
    TracksCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> type,
      required int order,
      Value<bool> isVisible,
      Value<bool> isLocked,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$TracksTableUpdateCompanionBuilder =
    TracksCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> type,
      Value<int> order,
      Value<bool> isVisible,
      Value<bool> isLocked,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$TracksTableFilterComposer
    extends Composer<_$ProjectDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVisible => $composableBuilder(
    column: $table.isVisible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocked => $composableBuilder(
    column: $table.isLocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TracksTableOrderingComposer
    extends Composer<_$ProjectDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVisible => $composableBuilder(
    column: $table.isVisible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocked => $composableBuilder(
    column: $table.isLocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$ProjectDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);

  GeneratedColumn<bool> get isVisible =>
      $composableBuilder(column: $table.isVisible, builder: (column) => column);

  GeneratedColumn<bool> get isLocked =>
      $composableBuilder(column: $table.isLocked, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$ProjectDatabase,
          $TracksTable,
          Track,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (Track, BaseReferences<_$ProjectDatabase, $TracksTable, Track>),
          Track,
          PrefetchHooks Function()
        > {
  $$TracksTableTableManager(_$ProjectDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<bool> isVisible = const Value.absent(),
                Value<bool> isLocked = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                name: name,
                type: type,
                order: order,
                isVisible: isVisible,
                isLocked: isLocked,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                required int order,
                Value<bool> isVisible = const Value.absent(),
                Value<bool> isLocked = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TracksCompanion.insert(
                id: id,
                name: name,
                type: type,
                order: order,
                isVisible: isVisible,
                isLocked: isLocked,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$ProjectDatabase,
      $TracksTable,
      Track,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (Track, BaseReferences<_$ProjectDatabase, $TracksTable, Track>),
      Track,
      PrefetchHooks Function()
    >;
typedef $$ClipsTableCreateCompanionBuilder =
    ClipsCompanion Function({
      Value<int> id,
      required int trackId,
      Value<String> name,
      Value<String> type,
      required String sourcePath,
      Value<int?> sourceDurationMs,
      required int startTimeInSourceMs,
      required int endTimeInSourceMs,
      Value<int> startTimeOnTrackMs,
      Value<int?> endTimeOnTrackMs,
      Value<String?> metadata,
      Value<double> previewPositionX,
      Value<double> previewPositionY,
      Value<double> previewWidth,
      Value<double> previewHeight,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ClipsTableUpdateCompanionBuilder =
    ClipsCompanion Function({
      Value<int> id,
      Value<int> trackId,
      Value<String> name,
      Value<String> type,
      Value<String> sourcePath,
      Value<int?> sourceDurationMs,
      Value<int> startTimeInSourceMs,
      Value<int> endTimeInSourceMs,
      Value<int> startTimeOnTrackMs,
      Value<int?> endTimeOnTrackMs,
      Value<String?> metadata,
      Value<double> previewPositionX,
      Value<double> previewPositionY,
      Value<double> previewWidth,
      Value<double> previewHeight,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ClipsTableFilterComposer
    extends Composer<_$ProjectDatabase, $ClipsTable> {
  $$ClipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceDurationMs => $composableBuilder(
    column: $table.sourceDurationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startTimeInSourceMs => $composableBuilder(
    column: $table.startTimeInSourceMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTimeInSourceMs => $composableBuilder(
    column: $table.endTimeInSourceMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startTimeOnTrackMs => $composableBuilder(
    column: $table.startTimeOnTrackMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTimeOnTrackMs => $composableBuilder(
    column: $table.endTimeOnTrackMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get previewPositionX => $composableBuilder(
    column: $table.previewPositionX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get previewPositionY => $composableBuilder(
    column: $table.previewPositionY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get previewWidth => $composableBuilder(
    column: $table.previewWidth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get previewHeight => $composableBuilder(
    column: $table.previewHeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClipsTableOrderingComposer
    extends Composer<_$ProjectDatabase, $ClipsTable> {
  $$ClipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceDurationMs => $composableBuilder(
    column: $table.sourceDurationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startTimeInSourceMs => $composableBuilder(
    column: $table.startTimeInSourceMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTimeInSourceMs => $composableBuilder(
    column: $table.endTimeInSourceMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startTimeOnTrackMs => $composableBuilder(
    column: $table.startTimeOnTrackMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTimeOnTrackMs => $composableBuilder(
    column: $table.endTimeOnTrackMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get previewPositionX => $composableBuilder(
    column: $table.previewPositionX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get previewPositionY => $composableBuilder(
    column: $table.previewPositionY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get previewWidth => $composableBuilder(
    column: $table.previewWidth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get previewHeight => $composableBuilder(
    column: $table.previewHeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClipsTableAnnotationComposer
    extends Composer<_$ProjectDatabase, $ClipsTable> {
  $$ClipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceDurationMs => $composableBuilder(
    column: $table.sourceDurationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startTimeInSourceMs => $composableBuilder(
    column: $table.startTimeInSourceMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endTimeInSourceMs => $composableBuilder(
    column: $table.endTimeInSourceMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startTimeOnTrackMs => $composableBuilder(
    column: $table.startTimeOnTrackMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endTimeOnTrackMs => $composableBuilder(
    column: $table.endTimeOnTrackMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<double> get previewPositionX => $composableBuilder(
    column: $table.previewPositionX,
    builder: (column) => column,
  );

  GeneratedColumn<double> get previewPositionY => $composableBuilder(
    column: $table.previewPositionY,
    builder: (column) => column,
  );

  GeneratedColumn<double> get previewWidth => $composableBuilder(
    column: $table.previewWidth,
    builder: (column) => column,
  );

  GeneratedColumn<double> get previewHeight => $composableBuilder(
    column: $table.previewHeight,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ClipsTableTableManager
    extends
        RootTableManager<
          _$ProjectDatabase,
          $ClipsTable,
          Clip,
          $$ClipsTableFilterComposer,
          $$ClipsTableOrderingComposer,
          $$ClipsTableAnnotationComposer,
          $$ClipsTableCreateCompanionBuilder,
          $$ClipsTableUpdateCompanionBuilder,
          (Clip, BaseReferences<_$ProjectDatabase, $ClipsTable, Clip>),
          Clip,
          PrefetchHooks Function()
        > {
  $$ClipsTableTableManager(_$ProjectDatabase db, $ClipsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ClipsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ClipsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ClipsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> trackId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<int?> sourceDurationMs = const Value.absent(),
                Value<int> startTimeInSourceMs = const Value.absent(),
                Value<int> endTimeInSourceMs = const Value.absent(),
                Value<int> startTimeOnTrackMs = const Value.absent(),
                Value<int?> endTimeOnTrackMs = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<double> previewPositionX = const Value.absent(),
                Value<double> previewPositionY = const Value.absent(),
                Value<double> previewWidth = const Value.absent(),
                Value<double> previewHeight = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ClipsCompanion(
                id: id,
                trackId: trackId,
                name: name,
                type: type,
                sourcePath: sourcePath,
                sourceDurationMs: sourceDurationMs,
                startTimeInSourceMs: startTimeInSourceMs,
                endTimeInSourceMs: endTimeInSourceMs,
                startTimeOnTrackMs: startTimeOnTrackMs,
                endTimeOnTrackMs: endTimeOnTrackMs,
                metadata: metadata,
                previewPositionX: previewPositionX,
                previewPositionY: previewPositionY,
                previewWidth: previewWidth,
                previewHeight: previewHeight,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int trackId,
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                required String sourcePath,
                Value<int?> sourceDurationMs = const Value.absent(),
                required int startTimeInSourceMs,
                required int endTimeInSourceMs,
                Value<int> startTimeOnTrackMs = const Value.absent(),
                Value<int?> endTimeOnTrackMs = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<double> previewPositionX = const Value.absent(),
                Value<double> previewPositionY = const Value.absent(),
                Value<double> previewWidth = const Value.absent(),
                Value<double> previewHeight = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ClipsCompanion.insert(
                id: id,
                trackId: trackId,
                name: name,
                type: type,
                sourcePath: sourcePath,
                sourceDurationMs: sourceDurationMs,
                startTimeInSourceMs: startTimeInSourceMs,
                endTimeInSourceMs: endTimeInSourceMs,
                startTimeOnTrackMs: startTimeOnTrackMs,
                endTimeOnTrackMs: endTimeOnTrackMs,
                metadata: metadata,
                previewPositionX: previewPositionX,
                previewPositionY: previewPositionY,
                previewWidth: previewWidth,
                previewHeight: previewHeight,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClipsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProjectDatabase,
      $ClipsTable,
      Clip,
      $$ClipsTableFilterComposer,
      $$ClipsTableOrderingComposer,
      $$ClipsTableAnnotationComposer,
      $$ClipsTableCreateCompanionBuilder,
      $$ClipsTableUpdateCompanionBuilder,
      (Clip, BaseReferences<_$ProjectDatabase, $ClipsTable, Clip>),
      Clip,
      PrefetchHooks Function()
    >;
typedef $$ProjectAssetsTableCreateCompanionBuilder =
    ProjectAssetsCompanion Function({
      Value<int> id,
      required String name,
      required String sourcePath,
      required String type,
      Value<String?> mimeType,
      Value<int?> durationMs,
      Value<int?> width,
      Value<int?> height,
      Value<double?> fileSize,
      Value<String?> metadataJson,
      Value<String?> thumbnailPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ProjectAssetsTableUpdateCompanionBuilder =
    ProjectAssetsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> sourcePath,
      Value<String> type,
      Value<String?> mimeType,
      Value<int?> durationMs,
      Value<int?> width,
      Value<int?> height,
      Value<double?> fileSize,
      Value<String?> metadataJson,
      Value<String?> thumbnailPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ProjectAssetsTableFilterComposer
    extends Composer<_$ProjectDatabase, $ProjectAssetsTable> {
  $$ProjectAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectAssetsTableOrderingComposer
    extends Composer<_$ProjectDatabase, $ProjectAssetsTable> {
  $$ProjectAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectAssetsTableAnnotationComposer
    extends Composer<_$ProjectDatabase, $ProjectAssetsTable> {
  $$ProjectAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<double> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProjectAssetsTableTableManager
    extends
        RootTableManager<
          _$ProjectDatabase,
          $ProjectAssetsTable,
          ProjectAsset,
          $$ProjectAssetsTableFilterComposer,
          $$ProjectAssetsTableOrderingComposer,
          $$ProjectAssetsTableAnnotationComposer,
          $$ProjectAssetsTableCreateCompanionBuilder,
          $$ProjectAssetsTableUpdateCompanionBuilder,
          (
            ProjectAsset,
            BaseReferences<
              _$ProjectDatabase,
              $ProjectAssetsTable,
              ProjectAsset
            >,
          ),
          ProjectAsset,
          PrefetchHooks Function()
        > {
  $$ProjectAssetsTableTableManager(
    _$ProjectDatabase db,
    $ProjectAssetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ProjectAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$ProjectAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ProjectAssetsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<double?> fileSize = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProjectAssetsCompanion(
                id: id,
                name: name,
                sourcePath: sourcePath,
                type: type,
                mimeType: mimeType,
                durationMs: durationMs,
                width: width,
                height: height,
                fileSize: fileSize,
                metadataJson: metadataJson,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String sourcePath,
                required String type,
                Value<String?> mimeType = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<double?> fileSize = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProjectAssetsCompanion.insert(
                id: id,
                name: name,
                sourcePath: sourcePath,
                type: type,
                mimeType: mimeType,
                durationMs: durationMs,
                width: width,
                height: height,
                fileSize: fileSize,
                metadataJson: metadataJson,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProjectDatabase,
      $ProjectAssetsTable,
      ProjectAsset,
      $$ProjectAssetsTableFilterComposer,
      $$ProjectAssetsTableOrderingComposer,
      $$ProjectAssetsTableAnnotationComposer,
      $$ProjectAssetsTableCreateCompanionBuilder,
      $$ProjectAssetsTableUpdateCompanionBuilder,
      (
        ProjectAsset,
        BaseReferences<_$ProjectDatabase, $ProjectAssetsTable, ProjectAsset>,
      ),
      ProjectAsset,
      PrefetchHooks Function()
    >;
typedef $$ChangeLogsTableCreateCompanionBuilder =
    ChangeLogsCompanion Function({
      Value<int> id,
      required String entity,
      required String entityId,
      required String action,
      Value<String?> oldData,
      Value<String?> newData,
      required int timestamp,
    });
typedef $$ChangeLogsTableUpdateCompanionBuilder =
    ChangeLogsCompanion Function({
      Value<int> id,
      Value<String> entity,
      Value<String> entityId,
      Value<String> action,
      Value<String?> oldData,
      Value<String?> newData,
      Value<int> timestamp,
    });

class $$ChangeLogsTableFilterComposer
    extends Composer<_$ProjectDatabase, $ChangeLogsTable> {
  $$ChangeLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oldData => $composableBuilder(
    column: $table.oldData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newData => $composableBuilder(
    column: $table.newData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChangeLogsTableOrderingComposer
    extends Composer<_$ProjectDatabase, $ChangeLogsTable> {
  $$ChangeLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oldData => $composableBuilder(
    column: $table.oldData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newData => $composableBuilder(
    column: $table.newData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChangeLogsTableAnnotationComposer
    extends Composer<_$ProjectDatabase, $ChangeLogsTable> {
  $$ChangeLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get oldData =>
      $composableBuilder(column: $table.oldData, builder: (column) => column);

  GeneratedColumn<String> get newData =>
      $composableBuilder(column: $table.newData, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$ChangeLogsTableTableManager
    extends
        RootTableManager<
          _$ProjectDatabase,
          $ChangeLogsTable,
          ChangeLog,
          $$ChangeLogsTableFilterComposer,
          $$ChangeLogsTableOrderingComposer,
          $$ChangeLogsTableAnnotationComposer,
          $$ChangeLogsTableCreateCompanionBuilder,
          $$ChangeLogsTableUpdateCompanionBuilder,
          (
            ChangeLog,
            BaseReferences<_$ProjectDatabase, $ChangeLogsTable, ChangeLog>,
          ),
          ChangeLog,
          PrefetchHooks Function()
        > {
  $$ChangeLogsTableTableManager(_$ProjectDatabase db, $ChangeLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ChangeLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ChangeLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ChangeLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> oldData = const Value.absent(),
                Value<String?> newData = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
              }) => ChangeLogsCompanion(
                id: id,
                entity: entity,
                entityId: entityId,
                action: action,
                oldData: oldData,
                newData: newData,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entity,
                required String entityId,
                required String action,
                Value<String?> oldData = const Value.absent(),
                Value<String?> newData = const Value.absent(),
                required int timestamp,
              }) => ChangeLogsCompanion.insert(
                id: id,
                entity: entity,
                entityId: entityId,
                action: action,
                oldData: oldData,
                newData: newData,
                timestamp: timestamp,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChangeLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProjectDatabase,
      $ChangeLogsTable,
      ChangeLog,
      $$ChangeLogsTableFilterComposer,
      $$ChangeLogsTableOrderingComposer,
      $$ChangeLogsTableAnnotationComposer,
      $$ChangeLogsTableCreateCompanionBuilder,
      $$ChangeLogsTableUpdateCompanionBuilder,
      (
        ChangeLog,
        BaseReferences<_$ProjectDatabase, $ChangeLogsTable, ChangeLog>,
      ),
      ChangeLog,
      PrefetchHooks Function()
    >;

class $ProjectDatabaseManager {
  final _$ProjectDatabase _db;
  $ProjectDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$ClipsTableTableManager get clips =>
      $$ClipsTableTableManager(_db, _db.clips);
  $$ProjectAssetsTableTableManager get projectAssets =>
      $$ProjectAssetsTableTableManager(_db, _db.projectAssets);
  $$ChangeLogsTableTableManager get changeLogs =>
      $$ChangeLogsTableTableManager(_db, _db.changeLogs);
}
