import 'dart:io';

import 'package:nettools_mobile/core/oui/oui_database_builder.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final projectRoot = Directory.current;
  final cacheDirectory = Directory(
    p.join(projectRoot.path, '.tooling-data', 'ieee-oui'),
  );
  final outputFile = File(
    p.join(projectRoot.path, 'assets', 'data', 'ieee_oui.db'),
  );
  final builder = OuiDatabaseBuilder();
  try {
    final result = await builder.downloadAndBuild(
      cacheDirectory: cacheDirectory,
      outputFile: outputFile,
      previousDatabase: outputFile.existsSync() ? outputFile : null,
      onProgress: (message, progress) {
        stdout.writeln('${(progress * 100).toStringAsFixed(0)}% $message');
      },
    );
    stdout.writeln('SQLite: ${result.outputPath}');
    stdout.writeln('Records: ${result.counts} (${result.totalRecords})');
  } finally {
    builder.close();
  }
}
