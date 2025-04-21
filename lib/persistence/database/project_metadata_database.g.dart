// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_metadata_database.dart';

// ignore_for_file: type=lint
class $ProjectMetadataTableTable extends ProjectMetadataTable
    with TableInfo<$ProjectMetadataTableTable, ProjectMetadata> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectMetadataTableTable(this.attachedDatabase, [this._alias]);
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databasePathMeta = const VerificationMeta(
    'databasePath',
  );
  @override
  late final GeneratedColumn<String> databasePath = GeneratedColumn<String>(
    'database_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _lastModifiedAtMeta = const VerificationMeta(
    'lastModifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastModifiedAt =
      GeneratedColumn<DateTime>(
        'last_modified_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    databasePath,
    createdAt,
    lastModifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_metadata_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectMetadata> instance, {
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
    if (data.containsKey('database_path')) {
      context.handle(
        _databasePathMeta,
        databasePath.isAcceptableOrUnknown(
          data['database_path']!,
          _databasePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databasePathMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_modified_at')) {
      context.handle(
        _lastModifiedAtMeta,
        lastModifiedAt.isAcceptableOrUnknown(
          data['last_modified_at']!,
          _lastModifiedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectMetadata map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectMetadata(
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
      databasePath:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}database_path'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      lastModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_modified_at'],
      ),
    );
  }

  @override
  $ProjectMetadataTableTable createAlias(String alias) {
    return $ProjectMetadataTableTable(attachedDatabase, alias);
  }
}

class ProjectMetadata extends DataClass implements Insertable<ProjectMetadata> {
  final int id;
  final String name;
  final String databasePath;
  final DateTime createdAt;
  final DateTime? lastModifiedAt;
  const ProjectMetadata({
    required this.id,
    required this.name,
    required this.databasePath,
    required this.createdAt,
    this.lastModifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['database_path'] = Variable<String>(databasePath);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastModifiedAt != null) {
      map['last_modified_at'] = Variable<DateTime>(lastModifiedAt);
    }
    return map;
  }

  ProjectMetadataTableCompanion toCompanion(bool nullToAbsent) {
    return ProjectMetadataTableCompanion(
      id: Value(id),
      name: Value(name),
      databasePath: Value(databasePath),
      createdAt: Value(createdAt),
      lastModifiedAt:
          lastModifiedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(lastModifiedAt),
    );
  }

  factory ProjectMetadata.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectMetadata(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      databasePath: serializer.fromJson<String>(json['databasePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastModifiedAt: serializer.fromJson<DateTime?>(json['lastModifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'databasePath': serializer.toJson<String>(databasePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastModifiedAt': serializer.toJson<DateTime?>(lastModifiedAt),
    };
  }

  ProjectMetadata copyWith({
    int? id,
    String? name,
    String? databasePath,
    DateTime? createdAt,
    Value<DateTime?> lastModifiedAt = const Value.absent(),
  }) => ProjectMetadata(
    id: id ?? this.id,
    name: name ?? this.name,
    databasePath: databasePath ?? this.databasePath,
    createdAt: createdAt ?? this.createdAt,
    lastModifiedAt:
        lastModifiedAt.present ? lastModifiedAt.value : this.lastModifiedAt,
  );
  ProjectMetadata copyWithCompanion(ProjectMetadataTableCompanion data) {
    return ProjectMetadata(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      databasePath:
          data.databasePath.present
              ? data.databasePath.value
              : this.databasePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastModifiedAt:
          data.lastModifiedAt.present
              ? data.lastModifiedAt.value
              : this.lastModifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectMetadata(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('databasePath: $databasePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastModifiedAt: $lastModifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, databasePath, createdAt, lastModifiedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectMetadata &&
          other.id == this.id &&
          other.name == this.name &&
          other.databasePath == this.databasePath &&
          other.createdAt == this.createdAt &&
          other.lastModifiedAt == this.lastModifiedAt);
}

class ProjectMetadataTableCompanion extends UpdateCompanion<ProjectMetadata> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> databasePath;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastModifiedAt;
  const ProjectMetadataTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.databasePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastModifiedAt = const Value.absent(),
  });
  ProjectMetadataTableCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String databasePath,
    this.createdAt = const Value.absent(),
    this.lastModifiedAt = const Value.absent(),
  }) : name = Value(name),
       databasePath = Value(databasePath);
  static Insertable<ProjectMetadata> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? databasePath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastModifiedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (databasePath != null) 'database_path': databasePath,
      if (createdAt != null) 'created_at': createdAt,
      if (lastModifiedAt != null) 'last_modified_at': lastModifiedAt,
    });
  }

  ProjectMetadataTableCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? databasePath,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastModifiedAt,
  }) {
    return ProjectMetadataTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      databasePath: databasePath ?? this.databasePath,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
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
    if (databasePath.present) {
      map['database_path'] = Variable<String>(databasePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastModifiedAt.present) {
      map['last_modified_at'] = Variable<DateTime>(lastModifiedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectMetadataTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('databasePath: $databasePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastModifiedAt: $lastModifiedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProjectMetadataDatabase extends GeneratedDatabase {
  _$ProjectMetadataDatabase(QueryExecutor e) : super(e);
  $ProjectMetadataDatabaseManager get managers =>
      $ProjectMetadataDatabaseManager(this);
  late final $ProjectMetadataTableTable projectMetadataTable =
      $ProjectMetadataTableTable(this);
  late final ProjectMetadataDao projectMetadataDao = ProjectMetadataDao(
    this as ProjectMetadataDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [projectMetadataTable];
}

typedef $$ProjectMetadataTableTableCreateCompanionBuilder =
    ProjectMetadataTableCompanion Function({
      Value<int> id,
      required String name,
      required String databasePath,
      Value<DateTime> createdAt,
      Value<DateTime?> lastModifiedAt,
    });
typedef $$ProjectMetadataTableTableUpdateCompanionBuilder =
    ProjectMetadataTableCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> databasePath,
      Value<DateTime> createdAt,
      Value<DateTime?> lastModifiedAt,
    });

class $$ProjectMetadataTableTableFilterComposer
    extends Composer<_$ProjectMetadataDatabase, $ProjectMetadataTableTable> {
  $$ProjectMetadataTableTableFilterComposer({
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

  ColumnFilters<String> get databasePath => $composableBuilder(
    column: $table.databasePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastModifiedAt => $composableBuilder(
    column: $table.lastModifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectMetadataTableTableOrderingComposer
    extends Composer<_$ProjectMetadataDatabase, $ProjectMetadataTableTable> {
  $$ProjectMetadataTableTableOrderingComposer({
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

  ColumnOrderings<String> get databasePath => $composableBuilder(
    column: $table.databasePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastModifiedAt => $composableBuilder(
    column: $table.lastModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectMetadataTableTableAnnotationComposer
    extends Composer<_$ProjectMetadataDatabase, $ProjectMetadataTableTable> {
  $$ProjectMetadataTableTableAnnotationComposer({
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

  GeneratedColumn<String> get databasePath => $composableBuilder(
    column: $table.databasePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastModifiedAt => $composableBuilder(
    column: $table.lastModifiedAt,
    builder: (column) => column,
  );
}

class $$ProjectMetadataTableTableTableManager
    extends
        RootTableManager<
          _$ProjectMetadataDatabase,
          $ProjectMetadataTableTable,
          ProjectMetadata,
          $$ProjectMetadataTableTableFilterComposer,
          $$ProjectMetadataTableTableOrderingComposer,
          $$ProjectMetadataTableTableAnnotationComposer,
          $$ProjectMetadataTableTableCreateCompanionBuilder,
          $$ProjectMetadataTableTableUpdateCompanionBuilder,
          (
            ProjectMetadata,
            BaseReferences<
              _$ProjectMetadataDatabase,
              $ProjectMetadataTableTable,
              ProjectMetadata
            >,
          ),
          ProjectMetadata,
          PrefetchHooks Function()
        > {
  $$ProjectMetadataTableTableTableManager(
    _$ProjectMetadataDatabase db,
    $ProjectMetadataTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ProjectMetadataTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$ProjectMetadataTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$ProjectMetadataTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> databasePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastModifiedAt = const Value.absent(),
              }) => ProjectMetadataTableCompanion(
                id: id,
                name: name,
                databasePath: databasePath,
                createdAt: createdAt,
                lastModifiedAt: lastModifiedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String databasePath,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastModifiedAt = const Value.absent(),
              }) => ProjectMetadataTableCompanion.insert(
                id: id,
                name: name,
                databasePath: databasePath,
                createdAt: createdAt,
                lastModifiedAt: lastModifiedAt,
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

typedef $$ProjectMetadataTableTableProcessedTableManager =
    ProcessedTableManager<
      _$ProjectMetadataDatabase,
      $ProjectMetadataTableTable,
      ProjectMetadata,
      $$ProjectMetadataTableTableFilterComposer,
      $$ProjectMetadataTableTableOrderingComposer,
      $$ProjectMetadataTableTableAnnotationComposer,
      $$ProjectMetadataTableTableCreateCompanionBuilder,
      $$ProjectMetadataTableTableUpdateCompanionBuilder,
      (
        ProjectMetadata,
        BaseReferences<
          _$ProjectMetadataDatabase,
          $ProjectMetadataTableTable,
          ProjectMetadata
        >,
      ),
      ProjectMetadata,
      PrefetchHooks Function()
    >;

class $ProjectMetadataDatabaseManager {
  final _$ProjectMetadataDatabase _db;
  $ProjectMetadataDatabaseManager(this._db);
  $$ProjectMetadataTableTableTableManager get projectMetadataTable =>
      $$ProjectMetadataTableTableTableManager(_db, _db.projectMetadataTable);
}
