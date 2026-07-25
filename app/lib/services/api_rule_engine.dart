import 'dart:convert';

import 'api_workbench_service.dart';

enum ApiAssertionType {
  statusEquals,
  statusRange,
  responseTimeMax,
  headerExists,
  headerEquals,
  bodyContains,
  validJson,
  jsonPathExists,
  jsonPathEquals,
  jsonPathRegex,
}

class ApiAssertionRule {
  const ApiAssertionRule({
    required this.type,
    this.selector = '',
    this.expected = '',
    this.enabled = true,
  });
  final ApiAssertionType type;
  final String selector;
  final String expected;
  final bool enabled;

  String get title => switch (type) {
    ApiAssertionType.statusEquals => '状态码等于 $expected',
    ApiAssertionType.statusRange => '状态码位于 $expected',
    ApiAssertionType.responseTimeMax => '响应时间小于 $expected ms',
    ApiAssertionType.headerExists => 'Header $selector 存在',
    ApiAssertionType.headerEquals => 'Header $selector 等于 $expected',
    ApiAssertionType.bodyContains => '正文包含 $expected',
    ApiAssertionType.validJson => '正文是有效 JSON',
    ApiAssertionType.jsonPathExists => '$selector 存在',
    ApiAssertionType.jsonPathEquals => '$selector 等于 $expected',
    ApiAssertionType.jsonPathRegex => '$selector 匹配 /$expected/',
  };
}

class ApiAssertionResult {
  const ApiAssertionResult({
    required this.rule,
    required this.passed,
    required this.actual,
    this.error,
  });
  final ApiAssertionRule rule;
  final bool passed;
  final String actual;
  final String? error;
}

enum ApiExtractionSource { jsonPath, header, cookie, bodyRegex, statusCode }

class ApiExtractionRule {
  const ApiExtractionRule({
    required this.variable,
    required this.source,
    this.selector = '',
    this.group = 1,
    this.enabled = true,
  });
  final String variable;
  final ApiExtractionSource source;
  final String selector;
  final int group;
  final bool enabled;
}

class ApiExtractionResult {
  const ApiExtractionResult({
    required this.rule,
    required this.success,
    this.value,
    this.error,
  });
  final ApiExtractionRule rule;
  final bool success;
  final String? value;
  final String? error;
}

class ApiRuleRun {
  const ApiRuleRun({required this.assertions, required this.extractions});
  final List<ApiAssertionResult> assertions;
  final List<ApiExtractionResult> extractions;
}

class ApiRuleEngine {
  ApiRuleRun evaluate(
    ApiResponseData response, {
    List<ApiAssertionRule> assertions = const [],
    List<ApiExtractionRule> extractions = const [],
  }) {
    Object? json;
    Object? jsonError;
    try {
      json = jsonDecode(response.body);
    } on Object catch (error) {
      jsonError = error;
    }
    return ApiRuleRun(
      assertions: [
        for (final rule in assertions.where((rule) => rule.enabled))
          _assert(response, rule, json, jsonError),
      ],
      extractions: [
        for (final rule in extractions.where((rule) => rule.enabled))
          _extract(response, rule, json, jsonError),
      ],
    );
  }

  ApiAssertionResult _assert(
    ApiResponseData response,
    ApiAssertionRule rule,
    Object? json,
    Object? jsonError,
  ) {
    try {
      late bool passed;
      late String actual;
      switch (rule.type) {
        case ApiAssertionType.statusEquals:
          actual = '${response.statusCode}';
          passed = response.statusCode == int.parse(rule.expected);
        case ApiAssertionType.statusRange:
          actual = '${response.statusCode}';
          final match = RegExp(
            r'^(\d+)\s*[-.]\.?\s*(\d+)$',
          ).firstMatch(rule.expected);
          if (match == null) throw const FormatException('范围应写成 200-299');
          passed =
              response.statusCode >= int.parse(match.group(1)!) &&
              response.statusCode <= int.parse(match.group(2)!);
        case ApiAssertionType.responseTimeMax:
          actual = '${response.elapsed.inMilliseconds} ms';
          passed = response.elapsed.inMilliseconds < int.parse(rule.expected);
        case ApiAssertionType.headerExists:
          actual = _header(response.headers, rule.selector) == null
              ? '不存在'
              : '存在';
          passed = _header(response.headers, rule.selector) != null;
        case ApiAssertionType.headerEquals:
          actual =
              _header(response.headers, rule.selector)?.join(', ') ?? '不存在';
          passed = actual == rule.expected;
        case ApiAssertionType.bodyContains:
          actual = response.body.contains(rule.expected) ? '已包含' : '未包含';
          passed = response.body.contains(rule.expected);
        case ApiAssertionType.validJson:
          actual = jsonError == null ? '有效 JSON' : '$jsonError';
          passed = jsonError == null;
        case ApiAssertionType.jsonPathExists:
          if (jsonError != null) throw FormatException('响应不是 JSON：$jsonError');
          final value = resolveJsonPath(json, rule.selector);
          actual = value == null ? 'null' : _string(value);
          passed = value != null;
        case ApiAssertionType.jsonPathEquals:
          if (jsonError != null) throw FormatException('响应不是 JSON：$jsonError');
          final value = resolveJsonPath(json, rule.selector);
          actual = _string(value);
          passed = actual == rule.expected;
        case ApiAssertionType.jsonPathRegex:
          if (jsonError != null) throw FormatException('响应不是 JSON：$jsonError');
          final value = resolveJsonPath(json, rule.selector);
          actual = _string(value);
          passed = RegExp(rule.expected).hasMatch(actual);
      }
      return ApiAssertionResult(rule: rule, passed: passed, actual: actual);
    } on Object catch (error) {
      return ApiAssertionResult(
        rule: rule,
        passed: false,
        actual: '',
        error: '$error',
      );
    }
  }

  ApiExtractionResult _extract(
    ApiResponseData response,
    ApiExtractionRule rule,
    Object? json,
    Object? jsonError,
  ) {
    try {
      Object? value;
      switch (rule.source) {
        case ApiExtractionSource.jsonPath:
          if (jsonError != null) throw FormatException('响应不是 JSON：$jsonError');
          value = resolveJsonPath(json, rule.selector);
        case ApiExtractionSource.header:
          value = _header(response.headers, rule.selector)?.join(', ');
        case ApiExtractionSource.cookie:
          value = response.cookies
              .where(
                (cookie) =>
                    cookie.name.toLowerCase() == rule.selector.toLowerCase(),
              )
              .firstOrNull
              ?.value;
        case ApiExtractionSource.bodyRegex:
          final match = RegExp(
            rule.selector,
            multiLine: true,
            dotAll: true,
          ).firstMatch(response.body);
          if (match != null && rule.group <= match.groupCount)
            value = match.group(rule.group);
        case ApiExtractionSource.statusCode:
          value = response.statusCode;
      }
      if (value == null) throw const FormatException('没有提取到值');
      return ApiExtractionResult(
        rule: rule,
        success: true,
        value: _string(value),
      );
    } on Object catch (error) {
      return ApiExtractionResult(rule: rule, success: false, error: '$error');
    }
  }
}

Object? resolveJsonPath(Object? root, String expression) {
  var current = root;
  final path = expression.trim();
  if (!path.startsWith(r'$')) throw const FormatException(r'JSONPath 必须以 $ 开头');
  final rest = path.substring(1);
  final matches = RegExp(
    r'\.([A-Za-z0-9_-]+)|\[([0-9]+|\*)\]',
  ).allMatches(rest).toList();
  if (matches.map((match) => match.group(0)!).join() != rest)
    throw const FormatException(r'当前支持 $.name、[0] 和 [*]');
  for (final match in matches) {
    final key = match.group(1);
    final index = match.group(2);
    if (key != null) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else if (current is List) {
        current = [
          for (final item in current)
            if (item is Map && item.containsKey(key)) item[key],
        ];
      } else {
        return null;
      }
    } else if (index == '*') {
      if (current is! List) return null;
    } else {
      final position = int.parse(index!);
      if (current is! List || position < 0 || position >= current.length)
        return null;
      current = current[position];
    }
  }
  return current;
}

List<String>? _header(Map<String, List<String>> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name.trim().toLowerCase())
      return entry.value;
  }
  return null;
}

String _string(Object? value) => value is String ? value : jsonEncode(value);

extension _FirstOrNullApi<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
