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

/// Jobs at the user's sites (API.md section 7). `pending` marks rows changed
/// on this device that the server has not confirmed yet.
class LocalJobs extends Table {
  TextColumn get id => text()();
  TextColumn get siteId => text()();
  TextColumn get areaId => text().nullable()();
  TextColumn get code => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get priority => text()();
  TextColumn get status => text()();
  TextColumn get waitingReason => text().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get assigneeId => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get closeNote => text().nullable()();
  TextColumn get recurrenceId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get pending => boolean().withDefault(const Constant(false))();
  TextColumn get assetId => text().nullable()();
  TextColumn get maintenanceType =>
      text().withDefault(const Constant('corrective'))();
  BoolColumn get isolationRequired =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
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
    LocalJobs,
    LocalPeople,
    PendingUploads,
    LocalAssets,
    LocalTools,
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(localJobs);
        await m.createTable(localPeople);
        await m.createTable(pendingUploads);
      } else if (from < 3) {
        await m.addColumn(localJobs, localJobs.assetId);
        await m.addColumn(localJobs, localJobs.maintenanceType);
        await m.addColumn(localJobs, localJobs.isolationRequired);
      }
      if (from < 3) await m.createTable(localAssets);
      if (from < 4) await m.createTable(localTools);
      if (from >= 3 && from < 5) {
        await m.addColumn(localAssets, localAssets.status);
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
