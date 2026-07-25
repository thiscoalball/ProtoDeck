import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Resolves a safe local destination for remote downloads.
///
/// Desktop users choose a directory through the native platform dialog. On
/// mobile, downloads continue to use the app-owned transfer directory so the
/// SSH/SFTP flow does not require broad storage permissions.
class DownloadDestinationService {
  DownloadDestinationService._();

  static String? _lastDesktopDirectory;

  static Future<File?> choose({
    required String fileName,
    String dialogTitle = '选择下载目录',
  }) async {
    final safeName = path.basename(fileName.trim());
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      throw const FormatException('无效的下载文件名');
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
        initialDirectory: _lastDesktopDirectory,
        lockParentWindow: true,
      );
      if (selected == null) return null;
      _lastDesktopDirectory = selected;
      return _availableFile(Directory(selected), safeName);
    }

    final directory = Directory(
      path.join(
        (await getApplicationDocumentsDirectory()).path,
        'ProtoDeckTransfers',
      ),
    );
    await directory.create(recursive: true);
    return _availableFile(directory, safeName);
  }

  static File _availableFile(Directory directory, String fileName) {
    final direct = File(path.join(directory.path, fileName));
    if (!direct.existsSync()) return direct;

    final extension = path.extension(fileName);
    final stem = path.basenameWithoutExtension(fileName);
    for (var index = 1; index < 10000; index++) {
      final candidate = File(
        path.join(directory.path, '$stem ($index)$extension'),
      );
      if (!candidate.existsSync()) return candidate;
    }
    throw StateError('下载目录中存在过多同名文件');
  }
}
