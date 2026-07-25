import 'dart:convert';

import 'api_workbench_service.dart';

class ApiResponseChange {
  const ApiResponseChange(this.path, this.before, this.after);

  final String path;
  final String? before;
  final String? after;

  String get kind => before == null
      ? 'added'
      : after == null
      ? 'removed'
      : 'changed';
}

class ApiResponseComparison {
  const ApiResponseComparison({
    required this.statusChanged,
    required this.elapsedDeltaMs,
    required this.bytesDelta,
    required this.headerChanges,
    required this.bodyChanges,
    required this.bodyIdentical,
    required this.semanticJson,
  });

  final bool statusChanged;
  final double elapsedDeltaMs;
  final int bytesDelta;
  final List<ApiResponseChange> headerChanges;
  final List<ApiResponseChange> bodyChanges;
  final bool bodyIdentical;
  final bool semanticJson;

  bool get identical =>
      !statusChanged &&
      headerChanges.isEmpty &&
      bodyIdentical &&
      bytesDelta == 0;
}

class ApiResponseComparator {
  const ApiResponseComparator();

  ApiResponseComparison compare(
    ApiResponseData previous,
    ApiResponseData current, {
    int maxBodyChanges = 500,
  }) {
    final headers = <ApiResponseChange>[];
    final names = <String>{
      ...previous.headers.keys.map((item) => item.toLowerCase()),
      ...current.headers.keys.map((item) => item.toLowerCase()),
    }.toList()..sort();
    for (final name in names) {
      final before = _header(previous.headers, name);
      final after = _header(current.headers, name);
      if (before != after) headers.add(ApiResponseChange(name, before, after));
    }

    final body = <ApiResponseChange>[];
    var semanticJson = false;
    try {
      final before = jsonDecode(previous.body);
      final after = jsonDecode(current.body);
      semanticJson = true;
      _compareJson(r'$', before, after, body, maxBodyChanges);
    } on FormatException {
      _compareLines(previous.body, current.body, body, maxBodyChanges);
    }

    return ApiResponseComparison(
      statusChanged: previous.statusCode != current.statusCode,
      elapsedDeltaMs:
          (current.elapsed - previous.elapsed).inMicroseconds / 1000,
      bytesDelta: current.bytes - previous.bytes,
      headerChanges: List.unmodifiable(headers),
      bodyChanges: List.unmodifiable(body),
      bodyIdentical: previous.body == current.body,
      semanticJson: semanticJson,
    );
  }

  String? _header(Map<String, List<String>> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value.join(', ');
    }
    return null;
  }

  void _compareJson(
    String path,
    Object? before,
    Object? after,
    List<ApiResponseChange> output,
    int limit,
  ) {
    if (output.length >= limit || before == after) return;
    if (before is Map && after is Map) {
      final keys = <String>{
        ...before.keys.map((item) => item.toString()),
        ...after.keys.map((item) => item.toString()),
      }.toList()..sort();
      for (final key in keys) {
        if (output.length >= limit) return;
        final hasBefore = before.containsKey(key);
        final hasAfter = after.containsKey(key);
        final escaped = _escapePath(key);
        final child = escaped.startsWith('[')
            ? '$path$escaped'
            : '$path.$escaped';
        if (!hasBefore) {
          output.add(ApiResponseChange(child, null, _display(after[key])));
        } else if (!hasAfter) {
          output.add(ApiResponseChange(child, _display(before[key]), null));
        } else {
          _compareJson(child, before[key], after[key], output, limit);
        }
      }
      return;
    }
    if (before is List && after is List) {
      final length = before.length > after.length
          ? before.length
          : after.length;
      for (var index = 0; index < length && output.length < limit; index++) {
        final child = '$path[$index]';
        if (index >= before.length) {
          output.add(ApiResponseChange(child, null, _display(after[index])));
        } else if (index >= after.length) {
          output.add(ApiResponseChange(child, _display(before[index]), null));
        } else {
          _compareJson(child, before[index], after[index], output, limit);
        }
      }
      return;
    }
    output.add(ApiResponseChange(path, _display(before), _display(after)));
  }

  void _compareLines(
    String before,
    String after,
    List<ApiResponseChange> output,
    int limit,
  ) {
    final left = const LineSplitter().convert(before);
    final right = const LineSplitter().convert(after);
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length && output.length < limit; index++) {
      final a = index < left.length ? left[index] : null;
      final b = index < right.length ? right[index] : null;
      if (a != b) output.add(ApiResponseChange('line ${index + 1}', a, b));
    }
  }

  String _escapePath(String key) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)
      ? key
      : '[${jsonEncode(key)}]';

  String _display(Object? value) {
    if (value is String) return value;
    return jsonEncode(value);
  }
}
