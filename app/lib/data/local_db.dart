import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_db.g.dart';

/// The signed-in user's own profile.
class LocalProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get homeSiteId => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  BoolColumn get active => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Rows from `my_permissions()`; a null site means all sites.
class LocalPermissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text()();
  TextColumn get siteId => text().nullable()();
}

class LocalSites extends Table {
  TextColumn get id => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();
  BoolColumn get isArchived => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalAreas extends Table {
  TextColumn get id => text()();
  TextColumn get siteId => text()();
  TextColumn get name => text()();
  BoolColumn get isArchived => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Function calls waiting to reach Supabase (see API.md section 5).
@DataClassName('OutboxEntry')
class Outbox extends Table {
  TextColumn get clientRef => text()();
  TextColumn get action => text()();
  TextColumn get payload => text()();
  IntColumn get tries => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {clientRef};
}

/// Small JSON copies of online-only lists (chats and their latest
/// messages), so they can be read without signal.
class CachedJson extends Table {
  TextColumn get key => text()();
  TextColumn get json => text()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The asset register at the user's sites (API.md section 10).
class LocalAssets extends Table {
  TextColumn get id => text()();
  TextColumn get siteId => text()();
  TextColumn get areaId => text().nullable()();
  TextColumn get tag => text()();
  TextColumn get name => text()();
  TextColumn get kind => text().nullable()();
  TextColumn get makeModel => text().nullable()();
  TextColumn get serialNo => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// in_service | out_of_service | standby | decommissioned (0012).
  TextColumn get status => text().withDefault(const Constant('in_service'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The tools register at the current site (API.md section 11).
class LocalTools extends Table {
  TextColumn get id => text()();
  TextColumn get siteId => text()();
  TextColumn get code => text().nullable()();
  TextColumn get name => text()();
  TextColumn get kind => text().nullable()();
  TextColumn get serialNo => text().nullable()();
  TextColumn get condition => text()();
  DateTimeColumn get calibrationDue => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get holderId => text().nullable()();

  /// Who has it, also someone outside the app (an issue form).
  TextColumn get holderName => text().nullable()();

  /// The issue form it went out on.
  TextColumn get formId => text().nullable()();
  DateTimeColumn get issuedAt => dateTime().nullable()();
  DateTimeColumn get dueBack => dateTime().nullable()();
  DateTimeColumn get lastCountedAt => dateTime().nullable()();
  BoolColumn get pending => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Names of people, for showing who posted or holds a job.
class LocalPeople extends Table {
  TextColumn get id => text()();
  TextColumn get fullName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Files waiting to be uploaded to storage; sent before outbox actions.
@DataClassName('PendingUpload')
class PendingUploads extends Table {
  TextColumn get id => text()();
  TextColumn get bucket => text()();
  TextColumn get path => text()();
  BlobColumn get bytes => blob()();
  TextColumn get contentType => text()();
  IntColumn get tries => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    LocalProfiles,
    LocalPermissions,
    LocalSites,
    LocalAreas,
    Outbox,
    LocalPeople,
    PendingUploads,
    LocalAssets,
    LocalTools,
    CachedJson,
  ],
)
class LocalDb extends _$LocalDb {
  LocalDb([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'bravura_electrical',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localPeople);
        await m.createTable(pendingUploads);
      }
      if (from < 3) await m.createTable(localAssets);
      if (from < 4) await m.createTable(localTools);
      if (from >= 3 && from < 5) {
        await m.addColumn(localAssets, localAssets.status);
      }
      if (from < 6) {
        // The retired jobs board's copy (versions 1–5).
        await customStatement('drop table if exists local_jobs');
        await m.createTable(cachedJson);
      }
      if (from >= 4 && from < 7) {
        await m.addColumn(localTools, localTools.holderName);
        await m.addColumn(localTools, localTools.formId);
      }
    },
  );

  /// Replaces the cached session data in one transaction.
  Future<void> replaceSession({
    required LocalProfile? profile,
    required List<LocalPermissionsCompanion> permissions,
    required List<LocalSite> sites,
    required List<LocalArea> areas,
  }) {
    return transaction(() async {
      await delete(localProfiles).go();
      await delete(localPermissions).go();
      await delete(localSites).go();
      await delete(localAreas).go();
      if (profile != null) await into(localProfiles).insert(profile);
      await batch((b) {
        b.insertAll(localPermissions, permissions);
        b.insertAll(localSites, sites);
        b.insertAll(localAreas, areas);
      });
    });
  }

  /// Wipes everything, including unsent outbox entries (used on sign-out).
  Future<void> clearAll() {
    return transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
}

extension JsonCache on LocalDb {
  Future<void> saveJson(String key, String json) => into(cachedJson)
      .insertOnConflictUpdate(
        CachedJsonData(key: key, json: json, savedAt: DateTime.now()),
      );

  Future<String?> readJson(String key) async => (await (select(
    cachedJson,
  )..where((c) => c.key.equals(key))).getSingleOrNull())?.json;
}
