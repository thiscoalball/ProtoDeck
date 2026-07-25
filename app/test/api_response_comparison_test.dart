import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/api_response_comparison.dart';
import 'package:nettools_mobile/services/api_workbench_service.dart';

void main() {
  test('compares JSON semantically and reports response metadata deltas', () {
    final previous = _response(
      status: 200,
      body: '{"user":{"id":1,"name":"Alice"},"items":[1,2]}',
      headers: {
        'content-type': ['application/json'],
        'x-version': ['1'],
      },
      elapsedMs: 120,
    );
    final current = _response(
      status: 201,
      body: '{"items":[1,3,4],"user":{"id":1,"name":"Bob"}}',
      headers: {
        'Content-Type': ['application/json'],
        'x-version': ['2'],
      },
      elapsedMs: 95,
    );

    final result = const ApiResponseComparator().compare(previous, current);

    expect(result.semanticJson, isTrue);
    expect(result.statusChanged, isTrue);
    expect(result.elapsedDeltaMs, -25);
    expect(
      result.headerChanges.map((item) => item.path),
      contains('x-version'),
    );
    expect(
      result.bodyChanges.map((item) => item.path),
      containsAll([r'$.items[1]', r'$.items[2]', r'$.user.name']),
    );
  });

  test('falls back to line comparison for non JSON responses', () {
    final result = const ApiResponseComparator().compare(
      _response(body: 'one\ntwo\n'),
      _response(body: 'one\nthree\n'),
    );
    expect(result.semanticJson, isFalse);
    expect(result.bodyChanges.single.path, 'line 2');
    expect(result.bodyChanges.single.before, 'two');
    expect(result.bodyChanges.single.after, 'three');
  });
}

ApiResponseData _response({
  int status = 200,
  String body = '',
  Map<String, List<String>> headers = const {},
  int elapsedMs = 10,
}) => ApiResponseData(
  statusCode: status,
  reason: 'OK',
  headers: headers,
  body: body,
  elapsed: Duration(milliseconds: elapsedMs),
  bytes: body.length,
  finalUrl: Uri.parse('https://example.test'),
  rawBytes: Uint8List.fromList(body.codeUnits),
  cookies: const <Cookie>[],
  requestMethod: 'GET',
  requestHeaders: const {},
  requestBody: '',
);
