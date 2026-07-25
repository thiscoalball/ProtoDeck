import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class ToolSessions extends Table {
  TextColumn get id => text()();
  TextColumn get tool => text()();
  TextColumn get title => text()();
  TextColumn get summary => text()();
  TextColumn get detail => text()();
  BoolColumn get success => boolean()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RemoteProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get protocol => text()();
  TextColumn get host => text()();
  IntColumn get port => integer()();
  TextColumn get username => text().withDefault(const Constant(''))();
  TextColumn get domain => text().withDefault(const Constant(''))();
  TextColumn get shareName => text().withDefault(const Constant(''))();
  TextColumn get authType => text().withDefault(const Constant('password'))();
  TextColumn get secretRef => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class KnownHosts extends Table {
  TextColumn get endpoint => text()();
  TextColumn get algorithm => text()();
  TextColumn get fingerprint => text()();
  DateTimeColumn get trustedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {endpoint};
}

class GeoCacheEntries extends Table {
  TextColumn get address => text()();
  TextColumn get resultJson => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {address};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class TransferJobs extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  TextColumn get direction => text()();
  TextColumn get sourcePath => text()();
  TextColumn get destinationPath => text()();
  TextColumn get status => text()();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get transferredBytes => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    ToolSessions,
    RemoteProfiles,
    KnownHosts,
    GeoCacheEntries,
    AppSettings,
    TransferJobs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults()
    : super(
        driftDatabase(
          name: 'nettools',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  @override
  int get schemaVersion => 1;

  Future<List<ToolSession>> recentSessions({int limit = 100}) {
    return (select(toolSessions)
          ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
          ..limit(limit))
        .get();
  }

  Future<void> putSetting(String key, String value) {
    return into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<String?> getSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((item) => item.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<List<RemoteProfile>> watchRemoteProfiles() {
    return (select(
      remoteProfiles,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).watch();
  }

  Future<void> putRemoteProfile(RemoteProfilesCompanion profile) {
    return into(remoteProfiles).insertOnConflictUpdate(profile);
  }

  Future<void> deleteRemoteProfile(String id) {
    return (delete(remoteProfiles)..where((row) => row.id.equals(id))).go();
  }

  Stream<List<TransferJob>> watchTransferJobs() {
    return (select(
      transferJobs,
    )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).watch();
  }

  Future<void> clearFinishedTransferJobs() {
    return (delete(transferJobs)..where(
          (row) => row.status.isIn(['completed', 'cancelled', 'failed']),
        ))
        .go();
  }
}
