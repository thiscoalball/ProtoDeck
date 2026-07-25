import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

enum StructuredPayloadFormat { json, xml, html, text, binary }

class StructuredPayload {
  StructuredPayload({
    required this.rawText,
    this.rawBytes,
    this.contentType,
    this.source,
    this.direction,
    this.metadata = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now() {
    format = _detectFormat(
      rawText: rawText,
      rawBytes: rawBytes,
      contentType: contentType,
    );
    if (format == StructuredPayloadFormat.json) {
      try {
        parsedValue = jsonDecode(rawText);
        _jsonParsed = true;
      } on FormatException catch (error) {
        parseError = error;
      }
    } else if (format == StructuredPayloadFormat.xml) {
      try {
        _formattedMarkup = XmlDocument.parse(
          rawText,
        ).toXmlString(pretty: true, indent: '  ');
      } on Object {
        // XML fragments and imperfect responses are still useful. Fall back to
        // the tolerant markup formatter instead of mislabelling them as JSON.
        _formattedMarkup = _formatMarkup(rawText, html: false);
      }
    } else if (format == StructuredPayloadFormat.html) {
      _formattedMarkup = _formatMarkup(rawText, html: true);
    }
  }

  final String rawText;
  final Uint8List? rawBytes;
  final String? contentType;
  final String? source;
  final String? direction;
  final Map<String, Object?> metadata;
  final DateTime timestamp;

  late final StructuredPayloadFormat format;
  Object? parsedValue;
  FormatException? parseError;
  bool _jsonParsed = false;
  String? _formattedMarkup;

  bool get isJson => format == StructuredPayloadFormat.json && _jsonParsed;
  bool get isMarkup =>
      format == StructuredPayloadFormat.xml ||
      format == StructuredPayloadFormat.html;
  bool get canFormat => isJson || isMarkup;
  int get size => rawBytes?.length ?? utf8.encode(rawText).length;

  String get formattedText {
    if (isJson) {
      return const JsonEncoder.withIndent('  ').convert(parsedValue);
    }
    return _formattedMarkup ?? rawText;
  }

  Uint8List get bytes => rawBytes ?? Uint8List.fromList(utf8.encode(rawText));
}

StructuredPayloadFormat _detectFormat({
  required String rawText,
  required Uint8List? rawBytes,
  required String? contentType,
}) {
  final mediaType = (contentType ?? '').split(';').first.trim().toLowerCase();

  if (_isHtmlMediaType(mediaType)) return StructuredPayloadFormat.html;
  if (_isJsonMediaType(mediaType)) return StructuredPayloadFormat.json;
  if (_isXmlMediaType(mediaType)) return StructuredPayloadFormat.xml;
  if (_isBinaryMediaType(mediaType) ||
      (mediaType == 'binary' && rawBytes != null)) {
    return StructuredPayloadFormat.binary;
  }

  // Generic text types and protocol labels such as "text", "message" and
  // "packet" still need content sniffing because many devices omit or send an
  // incorrect Content-Type.
  final sniffed = _sniffTextFormat(rawText);
  if (sniffed != StructuredPayloadFormat.text) return sniffed;
  if (rawBytes != null && _looksBinary(rawBytes)) {
    return StructuredPayloadFormat.binary;
  }
  return StructuredPayloadFormat.text;
}

bool _isJsonMediaType(String value) =>
    value == 'json' ||
    value == 'application/json' ||
    value.endsWith('+json') ||
    value.contains('/json');

bool _isXmlMediaType(String value) =>
    value == 'xml' ||
    value == 'application/xml' ||
    value == 'text/xml' ||
    value.endsWith('+xml') ||
    value.contains('/xml');

bool _isHtmlMediaType(String value) =>
    value == 'html' || value == 'text/html' || value == 'application/xhtml+xml';

bool _isBinaryMediaType(String value) =>
    value == 'application/octet-stream' ||
    value == 'application/pdf' ||
    value == 'application/zip' ||
    value == 'application/gzip' ||
    value.startsWith('image/') ||
    value.startsWith('audio/') ||
    value.startsWith('video/') ||
    value.startsWith('font/');

StructuredPayloadFormat _sniffTextFormat(String source) {
  final text = source.trimLeft();
  if (text.isEmpty) return StructuredPayloadFormat.text;
  final lower = text.toLowerCase();
  if (lower.startsWith('<!doctype html') ||
      lower.startsWith('<html') ||
      lower.startsWith('<head') ||
      lower.startsWith('<body')) {
    return StructuredPayloadFormat.html;
  }
  if (lower.startsWith('<?xml')) return StructuredPayloadFormat.xml;
  if (text.startsWith('{') || text.startsWith('[')) {
    return StructuredPayloadFormat.json;
  }
  if (text.startsWith('<') && RegExp(r'^</?[A-Za-z_:]').hasMatch(text)) {
    final firstTag = RegExp(
      r'^</?([A-Za-z][A-Za-z0-9:-]*)',
    ).firstMatch(text)?.group(1)?.toLowerCase();
    const htmlTags = {
      'a',
      'article',
      'aside',
      'div',
      'footer',
      'form',
      'h1',
      'h2',
      'header',
      'img',
      'input',
      'li',
      'link',
      'main',
      'meta',
      'nav',
      'p',
      'script',
      'section',
      'span',
      'style',
      'table',
      'title',
      'ul',
    };
    return htmlTags.contains(firstTag)
        ? StructuredPayloadFormat.html
        : StructuredPayloadFormat.xml;
  }
  // JSON scalars are accepted only when they can be parsed completely. This
  // keeps ordinary log lines such as "200 OK" classified as plain text.
  try {
    jsonDecode(text);
    return StructuredPayloadFormat.json;
  } on FormatException {
    return StructuredPayloadFormat.text;
  }
}

bool _looksBinary(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  final sampleLength = bytes.length.clamp(0, 4096);
  var controlCharacters = 0;
  for (var index = 0; index < sampleLength; index++) {
    final byte = bytes[index];
    if (byte == 0) return true;
    if (byte < 9 || (byte > 13 && byte < 32)) controlCharacters++;
  }
  return controlCharacters / sampleLength > 0.1;
}

String _formatMarkup(String source, {required bool html}) {
  final tokens = RegExp(
    r'<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<![^>]*>|<[^>]+>|[^<]+',
  ).allMatches(source).map((match) => match.group(0)!).toList();
  if (tokens.isEmpty) return source;
  const htmlVoidTags = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };
  final output = StringBuffer();
  var depth = 0;
  for (final rawToken in tokens) {
    final token = rawToken.trim();
    if (token.isEmpty) continue;
    final closing = token.startsWith('</');
    if (closing && depth > 0) depth--;
    output.writeln('${'  ' * depth}$token');
    if (token.startsWith('<') &&
        !closing &&
        !token.startsWith('<!') &&
        !token.startsWith('<?') &&
        !token.endsWith('/>')) {
      final tag = RegExp(
        r'^<\s*([A-Za-z][A-Za-z0-9:-]*)',
      ).firstMatch(token)?.group(1)?.toLowerCase();
      if (!(html && htmlVoidTags.contains(tag))) depth++;
    }
  }
  return output.toString().trimRight();
}
