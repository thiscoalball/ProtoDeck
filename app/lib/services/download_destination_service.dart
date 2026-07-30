import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// The result of an explicit user-facing download or export.
///
/// [location] is a filesystem path on desktop and a content URI on Android.
/// It is intended for display only; callers must not assume an Android content
/// URI can be opened with [File].
class UserSavedFile {
  const UserSavedFile({required this.name, required this.location});

  final String name;
  final String location;

  String get displayLocation =>
      location.startsWith('content://') ? name : location;
}

/// Handles files that the user explicitly asked to download or export.
///
/// Remote files are first streamed into a private *temporary* file. Android
/// then copies that file through Storage Access Framework into the document
/// selected by the user. Windows and Linux use a native Save As dialog. App
/// databases, drafts, caches and saved API cases intentionally do not use this
/// service because they are application-internal data.
class DownloadDestinationService {
  DownloadDestinationService._();

  static const MethodChannel _native = MethodChannel('nettools/native');
  static String? _lastDesktopDirectory;

  /// Creates a uniquely named staging file suitable for streaming a large
  /// SSH/SFTP/SMB download without retaining the entire file in memory.
  static Future<File> createStagingFile({required String fileName}) async {
    final safeName = safeFileName(fileName);
    final root = await getTemporaryDirectory();
    final directory = Directory(path.join(root.path, 'download_staging'));
    await directory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return File(path.join(directory.path, '${stamp}_$safeName'));
  }

  /// Opens the platform Save As UI and moves/copies [stagingFile] to the
  /// user-selected destination. The staging file is removed on every outcome.
  static Future<UserSavedFile?> saveStagedFile({
    required File stagingFile,
    required String fileName,
    String? dialogTitle,
    String? mimeType,
    List<String>? allowedExtensions,
  }) async {
    final safeName = safeFileName(fileName);
    var keepStagingFile = false;
    try {
      if (Platform.isAndroid) {
        final result = await _native.invokeMapMethod<String, Object?>(
          'saveStagedFile',
          <String, Object?>{
            'sourcePath': stagingFile.path,
            'fileName': safeName,
            'mimeType': mimeType ?? _mimeTypeFor(safeName),
          },
        );
        if (result == null) return null;
        return UserSavedFile(
          name: (result['displayName'] as String?) ?? safeName,
          location: (result['uri'] as String?) ?? safeName,
        );
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final selected = await FilePicker.platform.saveFile(
          dialogTitle: dialogTitle,
          fileName: safeName,
          initialDirectory: _lastDesktopDirectory,
          type: allowedExtensions == null || allowedExtensions.isEmpty
              ? FileType.any
              : FileType.custom,
          allowedExtensions: allowedExtensions,
          lockParentWindow: true,
        );
        if (selected == null) return null;
        final target = File(selected);
        _lastDesktopDirectory = target.parent.path;
        await target.parent.create(recursive: true);
        if (path.canonicalize(target.path) ==
            path.canonicalize(stagingFile.path)) {
          keepStagingFile = true;
        } else {
          final sink = target.openWrite();
          try {
            await sink.addStream(stagingFile.openRead());
          } finally {
            await sink.close();
          }
        }
        return UserSavedFile(
          name: path.basename(target.path),
          location: target.path,
        );
      }

      // Fallback for any future mobile platform. file_picker owns the platform
      // document write in this branch.
      final selected = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: safeName,
        type: allowedExtensions == null || allowedExtensions.isEmpty
            ? FileType.any
            : FileType.custom,
        allowedExtensions: allowedExtensions,
        bytes: await stagingFile.readAsBytes(),
      );
      if (selected == null) return null;
      return UserSavedFile(name: safeName, location: selected);
    } finally {
      if (!keepStagingFile && await stagingFile.exists()) {
        await stagingFile.delete();
      }
    }
  }

  /// Saves an in-memory export through the same user-visible destination flow.
  static Future<UserSavedFile?> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String? dialogTitle,
    String? mimeType,
    List<String>? allowedExtensions,
  }) async {
    final staging = await createStagingFile(fileName: fileName);
    try {
      await staging.writeAsBytes(bytes, flush: true);
      return await saveStagedFile(
        stagingFile: staging,
        fileName: fileName,
        dialogTitle: dialogTitle,
        mimeType: mimeType,
        allowedExtensions: allowedExtensions,
      );
    } catch (_) {
      if (await staging.exists()) await staging.delete();
      rethrow;
    }
  }

  static Future<void> discardStagingFile(File file) async {
    if (await file.exists()) await file.delete();
  }

  static String safeFileName(String input) {
    var value = path.basename(input.trim());
    value = value.replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_');
    value = value.replaceAll(RegExp(r'[. ]+$'), '');
    if (value.isEmpty || value == '.' || value == '..') {
      value = 'download.bin';
    }
    final stem = path.basenameWithoutExtension(value).toUpperCase();
    const reserved = <String>{
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };
    if (reserved.contains(stem)) value = '_$value';
    return value;
  }

  static String _mimeTypeFor(String fileName) =>
      switch (path.extension(fileName).toLowerCase()) {
        '.csv' => 'text/csv',
        '.html' || '.htm' => 'text/html',
        '.json' => 'application/json',
        '.jsonl' => 'application/x-ndjson',
        '.log' || '.txt' => 'text/plain',
        '.pcap' => 'application/vnd.tcpdump.pcap',
        '.pcapng' => 'application/x-pcapng',
        '.png' => 'image/png',
        '.svg' => 'image/svg+xml',
        '.xml' => 'application/xml',
        '.yaml' || '.yml' => 'application/yaml',
        _ => 'application/octet-stream',
      };
}
