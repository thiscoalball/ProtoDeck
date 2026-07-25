import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/structured_payload.dart';
import '../../l10n/app_localizations.dart';

enum StructuredViewMode { tree, code, raw, hex }

class StructuredDataViewer extends StatefulWidget {
  const StructuredDataViewer({
    super.key,
    required this.payload,
    this.initialMode,
    this.maxCodeCharacters = 262144,
  });

  final StructuredPayload payload;
  final StructuredViewMode? initialMode;
  final int maxCodeCharacters;

  @override
  State<StructuredDataViewer> createState() => _StructuredDataViewerState();
}

class _StructuredDataViewerState extends State<StructuredDataViewer> {
  late StructuredViewMode _mode =
      widget.initialMode ??
      (widget.payload.isJson
          ? StructuredViewMode.code
          : widget.payload.isMarkup
          ? StructuredViewMode.code
          : StructuredViewMode.raw);
  final _searchController = TextEditingController();
  bool _wrap = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parseError = widget.payload.format == StructuredPayloadFormat.json
        ? widget.payload.parseError
        : null;
    final modes = <StructuredViewMode>[
      if (widget.payload.canFormat) StructuredViewMode.code,
      if (widget.payload.isJson) StructuredViewMode.tree,
      StructuredViewMode.raw,
      StructuredViewMode.hex,
    ];
    if (!modes.contains(_mode)) _mode = modes.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<StructuredViewMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in modes)
                ButtonSegment(
                  value: mode,
                  icon: Icon(_icon(mode), size: 18),
                  label: LocalizedText(_label(mode)),
                ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: context.tr('在当前内容中搜索'),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => setState(() => _wrap = !_wrap),
              tooltip: context.tr(_wrap ? '关闭自动换行' : '开启自动换行'),
              icon: Icon(_wrap ? Icons.wrap_text : Icons.horizontal_rule),
            ),
            IconButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: widget.payload.formattedText),
              ),
              tooltip: context.tr('复制格式化内容'),
              icon: const Icon(Icons.content_copy_rounded),
            ),
          ],
        ),
        if (parseError case final error?) ...[
          const SizedBox(height: 8),
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: LocalizedText(
                '不是有效 JSON：${error.message}'
                '${error.offset == null ? '' : '（位置 ${error.offset}）'}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() => switch (_mode) {
    StructuredViewMode.tree => _JsonTree(
      value: widget.payload.parsedValue,
      query: _searchController.text,
    ),
    StructuredViewMode.code => _CodeView(
      text: widget.payload.formattedText,
      query: _searchController.text,
      wrap: _wrap,
      maxCharacters: widget.maxCodeCharacters,
      format: widget.payload.format,
    ),
    StructuredViewMode.raw => _PlainView(
      text: widget.payload.rawText,
      query: _searchController.text,
      wrap: _wrap,
      maxCharacters: widget.maxCodeCharacters,
    ),
    StructuredViewMode.hex => _PlainView(
      text: _hexDump(widget.payload.bytes),
      query: _searchController.text,
      wrap: false,
      maxCharacters: widget.maxCodeCharacters,
    ),
  };

  String _label(StructuredViewMode value) => switch (value) {
    StructuredViewMode.tree => '树形',
    StructuredViewMode.code => widget.payload.isMarkup ? '格式化' : '代码',
    StructuredViewMode.raw => '原始',
    StructuredViewMode.hex => 'Hex',
  };

  static IconData _icon(StructuredViewMode value) => switch (value) {
    StructuredViewMode.tree => Icons.account_tree_outlined,
    StructuredViewMode.code => Icons.data_object_rounded,
    StructuredViewMode.raw => Icons.subject_rounded,
    StructuredViewMode.hex => Icons.grid_4x4_rounded,
  };
}

class _JsonTree extends StatelessWidget {
  const _JsonTree({required this.value, required this.query});
  final Object? value;
  final String query;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      _JsonNode(
        name: r'$',
        value: value,
        path: r'$',
        depth: 0,
        query: query.trim().toLowerCase(),
      ),
    ],
  );
}

class _JsonNode extends StatelessWidget {
  const _JsonNode({
    required this.name,
    required this.value,
    required this.path,
    required this.depth,
    required this.query,
  });

  final String name;
  final Object? value;
  final String path;
  final int depth;
  final String query;

  @override
  Widget build(BuildContext context) {
    final children = _children();
    final matches =
        query.isEmpty ||
        name.toLowerCase().contains(query) ||
        _preview(value).toLowerCase().contains(query);
    if (children == null) {
      return ListTile(
        dense: true,
        minTileHeight: 42,
        leading: Icon(_valueIcon(value), size: 18, color: _valueColor(value)),
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$name: ',
                style: const TextStyle(
                  color: Color(0xFF2864C8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: _preview(value),
                style: TextStyle(color: _valueColor(value)),
              ),
            ],
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        tileColor: matches && query.isNotEmpty
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        trailing: IconButton(
          tooltip: context.tr('复制值'),
          onPressed: () => Clipboard.setData(
            ClipboardData(text: value is String ? value as String : '$value'),
          ),
          icon: const Icon(Icons.copy_rounded, size: 17),
        ),
      );
    }
    final count = children.length;
    return ExpansionTile(
      initiallyExpanded: depth < 2,
      tilePadding: EdgeInsets.only(left: depth * 8.0, right: 4),
      childrenPadding: const EdgeInsets.only(left: 10),
      leading: Icon(
        value is List ? Icons.data_array_rounded : Icons.data_object_rounded,
        size: 19,
        color: const Color(0xFF3578F6),
      ),
      title: Text(
        '$name  ${value is List ? '[$count]' : '{$count}'}',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: IconButton(
        tooltip: context.tr('复制路径 $path'),
        onPressed: () => Clipboard.setData(ClipboardData(text: path)),
        icon: const Icon(Icons.content_copy_rounded, size: 17),
      ),
      children: [
        for (final entry in children)
          _JsonNode(
            name: entry.$1,
            value: entry.$2,
            path: entry.$3,
            depth: depth + 1,
            query: query,
          ),
      ],
    );
  }

  List<(String, Object?, String)>? _children() {
    if (value is Map) {
      return (value as Map).entries
          .map(
            (entry) =>
                (entry.key.toString(), entry.value, '$path.${entry.key}'),
          )
          .toList(growable: false);
    }
    if (value is List) {
      return (value as List)
          .asMap()
          .entries
          .map(
            (entry) => ('[${entry.key}]', entry.value, '$path[${entry.key}]'),
          )
          .toList(growable: false);
    }
    return null;
  }
}

class _CodeView extends StatelessWidget {
  const _CodeView({
    required this.text,
    required this.query,
    required this.wrap,
    required this.maxCharacters,
    required this.format,
  });
  final String text;
  final String query;
  final bool wrap;
  final int maxCharacters;
  final StructuredPayloadFormat format;

  @override
  Widget build(BuildContext context) {
    final clipped = text.length > maxCharacters
        ? '${text.substring(0, maxCharacters)}\n${context.tr('… 内容过大，仅显示前 $maxCharacters 个字符')}'
        : text;
    final lines = const LineSplitter().convert(clipped);
    return ListView.builder(
      scrollDirection: wrap ? Axis.vertical : Axis.horizontal,
      itemCount: wrap ? lines.length : 1,
      itemBuilder: (context, index) {
        if (!wrap) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++)
                  _codeLine(context, i + 1, lines[i]),
              ],
            ),
          );
        }
        return _codeLine(context, index + 1, lines[index]);
      },
    );
  }

  Widget _codeLine(BuildContext context, int number, String line) {
    final found =
        query.isNotEmpty && line.toLowerCase().contains(query.toLowerCase());
    return Container(
      color: found ? Theme.of(context).colorScheme.primaryContainer : null,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '$number',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              switch (format) {
                StructuredPayloadFormat.json => _highlightJsonLine(line),
                StructuredPayloadFormat.xml ||
                StructuredPayloadFormat.html => _highlightMarkupLine(line),
                _ => TextSpan(text: line),
              },
              softWrap: wrap,
              style: const TextStyle(fontFamily: 'monospace', height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

TextSpan _highlightMarkupLine(String line) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<[/!?]?[A-Za-z_:][A-Za-z0-9_:.-]*|\s[A-Za-z_:][A-Za-z0-9_:.-]*(?=\s*=)|"[^"]*"|\x27[^\x27]*\x27|/?>|&(?:#\d+|#x[0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]+);',
  );
  var offset = 0;
  for (final match in pattern.allMatches(line)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: line.substring(offset, match.start)));
    }
    final token = match.group(0)!;
    final color = token.startsWith('<!--') || token.startsWith('<![CDATA[')
        ? const Color(0xFF7B8496)
        : token.startsWith('"') || token.startsWith("'")
        ? const Color(0xFF008A72)
        : token.startsWith('&')
        ? const Color(0xFFD97706)
        : token.startsWith(' ') &&
              RegExp(r'[\w:.-]$').hasMatch(token.trimRight())
        ? const Color(0xFF2864C8)
        : const Color(0xFF7955C8);
    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(color: color),
      ),
    );
    offset = match.end;
  }
  if (offset < line.length) spans.add(TextSpan(text: line.substring(offset)));
  return TextSpan(children: spans);
}

class _PlainView extends StatelessWidget {
  const _PlainView({
    required this.text,
    required this.query,
    required this.wrap,
    required this.maxCharacters,
  });
  final String text;
  final String query;
  final bool wrap;
  final int maxCharacters;

  @override
  Widget build(BuildContext context) {
    final clipped = text.length > maxCharacters
        ? '${text.substring(0, maxCharacters)}\n${context.tr('… 内容过大，仅显示前 $maxCharacters 个字符')}'
        : text;
    return SingleChildScrollView(
      scrollDirection: wrap ? Axis.vertical : Axis.horizontal,
      child: SizedBox(
        width: wrap ? MediaQuery.sizeOf(context).width - 36 : null,
        child: SelectableText(
          clipped,
          style: const TextStyle(fontFamily: 'monospace', height: 1.45),
        ),
      ),
    );
  }
}

TextSpan _highlightJsonLine(String line) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'("(?:\\.|[^"\\])*")(?=\s*:)|("(?:\\.|[^"\\])*")|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false)\b|\bnull\b',
  );
  var offset = 0;
  for (final match in pattern.allMatches(line)) {
    if (match.start > offset)
      spans.add(TextSpan(text: line.substring(offset, match.start)));
    final token = match.group(0)!;
    final color = match.group(1) != null
        ? const Color(0xFF2864C8)
        : match.group(2) != null
        ? const Color(0xFF008A72)
        : token == 'null'
        ? const Color(0xFF7B8496)
        : token == 'true' || token == 'false'
        ? const Color(0xFFD97706)
        : const Color(0xFF7955C8);
    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(color: color),
      ),
    );
    offset = match.end;
  }
  if (offset < line.length) spans.add(TextSpan(text: line.substring(offset)));
  return TextSpan(children: spans);
}

String _preview(Object? value) => switch (value) {
  null => 'null',
  String() => '"$value"',
  _ => '$value',
};

Color _valueColor(Object? value) => switch (value) {
  null => const Color(0xFF7B8496),
  String() => const Color(0xFF008A72),
  bool() => const Color(0xFFD97706),
  num() => const Color(0xFF7955C8),
  _ => const Color(0xFF253044),
};

IconData _valueIcon(Object? value) => switch (value) {
  null => Icons.remove_circle_outline,
  String() => Icons.text_fields_rounded,
  bool() => Icons.toggle_on_outlined,
  num() => Icons.numbers_rounded,
  _ => Icons.data_object_rounded,
};

String _hexDump(List<int> bytes) {
  final output = StringBuffer();
  for (var offset = 0; offset < bytes.length; offset += 16) {
    final end = (offset + 16).clamp(0, bytes.length);
    final row = bytes.sublist(offset, end);
    output.write(offset.toRadixString(16).padLeft(8, '0').toUpperCase());
    output.write('  ');
    for (var i = 0; i < 16; i++) {
      if (i < row.length) {
        output.write(row[i].toRadixString(16).padLeft(2, '0').toUpperCase());
      } else {
        output.write('  ');
      }
      output.write(i == 7 ? '  ' : ' ');
    }
    output.write(' |');
    for (final byte in row) {
      output.write(byte >= 32 && byte <= 126 ? String.fromCharCode(byte) : '.');
    }
    output.writeln('|');
  }
  return output.toString();
}
