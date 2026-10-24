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

/// The job cards assigned to the signed-in user, as v_job_cards rows (JSON),
/// so My Assigned Jobs opens with poor signal.
class LocalJobCards extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get syncedAt => dateTime()();

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
    LocalJobCards,
    PendingUploads,
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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(pendingUploads);
      }
      if (from < 3) {
        // The jobs board cache is replaced by the job card cache.
        await customStatement('DROP TABLE IF EXISTS local_jobs');
        await customStatement('DROP TABLE IF EXISTS local_people');
        await m.createTable(localJobCards);
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

  /// Replaces the cached assigned job cards (id → JSON row).
  Future<void> replaceMyJobs(Map<String, String> rows) {
    final now = DateTime.now();
    return transaction(() async {
      await delete(localJobCards).go();
      await batch((b) {
        b.insertAll(localJobCards, [
          for (final e in rows.entries)
            LocalJobCardsCompanion.insert(
              id: e.key,
              payload: e.value,
              syncedAt: now,
            ),
        ]);
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
