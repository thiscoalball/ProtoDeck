import 'dart:convert';

class StructuredDataChange {
  const StructuredDataChange(this.path, this.before, this.after);
  final String path;
  final Object? before;
  final Object? after;

  String get kind => before == null
      ? 'added'
      : after == null
      ? 'removed'
      : 'changed';
}

class SchemaIssue {
  const SchemaIssue(this.path, this.message);
  final String path;
  final String message;
}

class StructuredDataWorkbenchService {
  Object? parseJson(String source) {
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('JSON 语法错误：${error.message}', source, error.offset);
    }
  }

  String formatJson(
    String source, {
    bool sortKeys = false,
    bool compact = false,
  }) {
    var value = parseJson(source);
    if (sortKeys) value = _sort(value);
    return compact
        ? jsonEncode(value)
        : const JsonEncoder.withIndent('  ').convert(value);
  }

  Map<String, Object?> flatten(String source) {
    final output = <String, Object?>{};
    void visit(Object? value, String path) {
      if (value is Map) {
        if (value.isEmpty) output[path] = <String, Object?>{};
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final escaped = key.replaceAll('~', '~0').replaceAll('/', '~1');
          visit(entry.value, '$path/$escaped');
        }
      } else if (value is List) {
        if (value.isEmpty) output[path] = <Object?>[];
        for (var index = 0; index < value.length; index++) {
          visit(value[index], '$path/$index');
        }
      } else {
        output[path.isEmpty ? '/' : path] = value;
      }
    }

    visit(parseJson(source), '');
    return output;
  }

  List<StructuredDataChange> compare(
    String before,
    String after, {
    int limit = 1000,
  }) {
    final output = <StructuredDataChange>[];
    _compare(r'$', parseJson(before), parseJson(after), output, limit);
    return output;
  }

  List<SchemaIssue> validateSchema(String instanceSource, String schemaSource) {
    final instance = parseJson(instanceSource);
    final schema = parseJson(schemaSource);
    if (schema is! Map) throw const FormatException('JSON Schema 根节点必须是对象');
    final issues = <SchemaIssue>[];
    _validate(instance, schema.cast<Object?, Object?>(), r'$', issues);
    return issues;
  }

  String inferSchema(String source) {
    Object schemaFor(Object? value) {
      if (value == null) return {'type': 'null'};
      if (value is bool) return {'type': 'boolean'};
      if (value is int) return {'type': 'integer'};
      if (value is num) return {'type': 'number'};
      if (value is String) return {'type': 'string'};
      if (value is List) {
        return {
          'type': 'array',
          if (value.isNotEmpty) 'items': schemaFor(value.first),
        };
      }
      if (value is Map) {
        final properties = <String, Object?>{};
        for (final entry in value.entries) {
          properties[entry.key.toString()] = schemaFor(entry.value);
        }
        return {
          'type': 'object',
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          'properties': properties,
          'required': properties.keys.toList(),
        };
      }
      return {'type': 'string'};
    }

    return const JsonEncoder.withIndent(
      '  ',
    ).convert(schemaFor(parseJson(source)));
  }

  String generateModel(String source, String language, {String name = 'Root'}) {
    final value = parseJson(source);
    if (value is! Map) throw const FormatException('生成数据模型需要 JSON Object 根节点');
    final fields = value.entries
        .map((entry) => (entry.key.toString(), entry.value))
        .toList(growable: false);
    String type(Object? value) => switch (language) {
      'TypeScript' => switch (value) {
        bool _ => 'boolean',
        num _ => 'number',
        String _ => 'string',
        List _ => 'unknown[]',
        Map _ => 'Record<string, unknown>',
        _ => 'unknown',
      },
      'Go' => switch (value) {
        bool _ => 'bool',
        int _ => 'int64',
        num _ => 'float64',
        String _ => 'string',
        List _ => '[]any',
        Map _ => 'map[string]any',
        _ => 'any',
      },
      'Java' || 'Kotlin' || 'Dart' => switch (value) {
        bool _ => language == 'Kotlin' ? 'Boolean' : 'bool',
        int _ => language == 'Java' ? 'long' : 'int',
        num _ => language == 'Java' ? 'double' : 'double',
        String _ => 'String',
        List _ => language == 'Dart' ? 'List<Object?>' : 'List<Object>',
        Map _ =>
          language == 'Dart' ? 'Map<String, Object?>' : 'Map<String, Object>',
        _ => language == 'Dart' ? 'Object?' : 'Object',
      },
      _ => 'Object',
    };
    String safe(String value) {
      final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      return RegExp(r'^\d').hasMatch(normalized) ? '_$normalized' : normalized;
    }

    if (language == 'TypeScript') {
      return 'export interface $name {\n${fields.map((e) => '  ${jsonEncode(e.$1)}: ${type(e.$2)};').join('\n')}\n}';
    }
    if (language == 'Go') {
      String title(String value) => value
          .split(RegExp(r'[_\-\s]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join();
      return 'type $name struct {\n${fields.map((e) => '  ${title(e.$1)} ${type(e.$2)} `json:"${e.$1}"`').join('\n')}\n}';
    }
    if (language == 'Kotlin') {
      return 'data class $name(\n${fields.map((e) => '  val ${safe(e.$1)}: ${type(e.$2)}${e == fields.last ? '' : ','}').join('\n')}\n)';
    }
    if (language == 'Java') {
      return 'public final class $name {\n${fields.map((e) => '  public ${type(e.$2)} ${safe(e.$1)};').join('\n')}\n}';
    }
    return 'class $name {\n  const $name({${fields.map((e) => 'required this.${safe(e.$1)}').join(', ')}});\n\n${fields.map((e) => '  final ${type(e.$2)} ${safe(e.$1)};').join('\n')}\n}';
  }

  Object? _sort(Object? value) {
    if (value is List) return value.map(_sort).toList(growable: false);
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()),
        );
      return {
        for (final entry in entries) entry.key.toString(): _sort(entry.value),
      };
    }
    return value;
  }

  void _compare(
    String path,
    Object? before,
    Object? after,
    List<StructuredDataChange> output,
    int limit,
  ) {
    if (output.length >= limit || _deepEqual(before, after)) return;
    if (before is Map && after is Map) {
      final keys = {
        ...before.keys.map((key) => key.toString()),
        ...after.keys.map((key) => key.toString()),
      }.toList()..sort();
      for (final key in keys) {
        if (output.length >= limit) return;
        final left = before.containsKey(key);
        final right = after.containsKey(key);
        final child = RegExp(r'^[A-Za-z_]\w*$').hasMatch(key)
            ? '$path.$key'
            : '$path[${jsonEncode(key)}]';
        if (!left) {
          output.add(StructuredDataChange(child, null, after[key]));
        } else if (!right) {
          output.add(StructuredDataChange(child, before[key], null));
        } else {
          _compare(child, before[key], after[key], output, limit);
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
          output.add(StructuredDataChange(child, null, after[index]));
        } else if (index >= after.length) {
          output.add(StructuredDataChange(child, before[index], null));
        } else {
          _compare(child, before[index], after[index], output, limit);
        }
      }
      return;
    }
    output.add(StructuredDataChange(path, before, after));
  }

  bool _deepEqual(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  void _validate(
    Object? instance,
    Map<Object?, Object?> schema,
    String path,
    List<SchemaIssue> issues,
  ) {
    final expected = schema['type']?.toString();
    if (expected != null && !_matchesType(instance, expected)) {
      issues.add(SchemaIssue(path, '期望 $expected，实际为 ${_type(instance)}'));
      return;
    }
    final enumValues = schema['enum'];
    if (enumValues is List &&
        !enumValues.any((item) => _deepEqual(item, instance))) {
      issues.add(SchemaIssue(path, '值不在 enum 允许范围内'));
    }
    if (instance is Map) {
      final required = schema['required'];
      if (required is List) {
        for (final key in required.map((value) => value.toString())) {
          if (!instance.containsKey(key))
            issues.add(SchemaIssue('$path.$key', '缺少必填字段'));
        }
      }
      final properties = schema['properties'];
      if (properties is Map) {
        for (final entry in properties.entries) {
          final key = entry.key.toString();
          if (instance.containsKey(key) && entry.value is Map) {
            _validate(
              instance[key],
              (entry.value as Map).cast<Object?, Object?>(),
              '$path.$key',
              issues,
            );
          }
        }
      }
    }
    if (instance is List && schema['items'] is Map) {
      for (var index = 0; index < instance.length; index++) {
        _validate(
          instance[index],
          (schema['items'] as Map).cast<Object?, Object?>(),
          '$path[$index]',
          issues,
        );
      }
    }
    if (instance is String) {
      final minLength = schema['minLength'];
      final maxLength = schema['maxLength'];
      if (minLength is num && instance.length < minLength) {
        issues.add(SchemaIssue(path, '长度小于 minLength $minLength'));
      }
      if (maxLength is num && instance.length > maxLength) {
        issues.add(SchemaIssue(path, '长度大于 maxLength $maxLength'));
      }
      final pattern = schema['pattern'];
      if (pattern is String && !RegExp(pattern).hasMatch(instance)) {
        issues.add(SchemaIssue(path, '不匹配 pattern $pattern'));
      }
    }
    if (instance is num) {
      final minimum = schema['minimum'];
      final maximum = schema['maximum'];
      if (minimum is num && instance < minimum) {
        issues.add(SchemaIssue(path, '小于 minimum $minimum'));
      }
      if (maximum is num && instance > maximum) {
        issues.add(SchemaIssue(path, '大于 maximum $maximum'));
      }
    }
  }

  bool _matchesType(Object? value, String type) => switch (type) {
    'null' => value == null,
    'boolean' => value is bool,
    'integer' => value is int,
    'number' => value is num,
    'string' => value is String,
    'array' => value is List,
    'object' => value is Map,
    _ => true,
  };

  String _type(Object? value) => switch (value) {
    null => 'null',
    bool _ => 'boolean',
    int _ => 'integer',
    num _ => 'number',
    String _ => 'string',
    List _ => 'array',
    Map _ => 'object',
    _ => value.runtimeType.toString(),
  };
}
