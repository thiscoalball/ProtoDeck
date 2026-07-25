import 'package:drift/drift.dart';

import '../data/app_database.dart';

class TransferJobTracker {
  TransferJobTracker({
    required this.database,
    required this.profileId,
    required this.direction,
    required this.sourcePath,
    required this.destinationPath,
    required this.totalBytes,
  }) : id = 'transfer_${DateTime.now().microsecondsSinceEpoch}';

  final AppDatabase database;
  final String profileId;
  final String direction;
  final String sourcePath;
  final String destinationPath;
  final int totalBytes;
  final String id;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  bool _finished = false;

  Future<void> start() {
    final now = DateTime.now();
    return database
        .into(database.transferJobs)
        .insert(
          TransferJobsCompanion.insert(
            id: id,
            profileId: profileId,
            direction: direction,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            status: 'running',
            totalBytes: Value(totalBytes > 0 ? totalBytes : null),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> progress(int bytes, {bool force = false}) async {
    if (_finished) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastWrite) < const Duration(milliseconds: 500))
      return;
    _lastWrite = now;
    await (database.update(
      database.transferJobs,
    )..where((row) => row.id.equals(id))).write(
      TransferJobsCompanion(
        transferredBytes: Value(bytes),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> pause(int bytes) => _status('paused', bytes: bytes);
  Future<void> resume(int bytes) => _status('running', bytes: bytes);
  Future<void> complete(int bytes) =>
      _status('completed', bytes: bytes, finish: true);
  Future<void> cancel(int bytes) =>
      _status('cancelled', bytes: bytes, finish: true);
  Future<void> fail(int bytes, Object error) =>
      _status('failed', bytes: bytes, error: '$error', finish: true);

  Future<void> _status(
    String status, {
    required int bytes,
    String? error,
    bool finish = false,
  }) async {
    if (_finished) return;
    if (finish) _finished = true;
    await (database.update(
      database.transferJobs,
    )..where((row) => row.id.equals(id))).write(
      TransferJobsCompanion(
        status: Value(status),
        transferredBytes: Value(bytes),
        error: Value(error),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
