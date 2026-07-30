import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../models/structured_payload.dart';
import '../../widgets/structured_data_viewer.dart';

import '../../../services/developer_tools_service.dart';
import '../../../services/download_destination_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class DeveloperToolPage extends StatefulWidget {
  const DeveloperToolPage({super.key, required this.mode, this.appState});
  final String mode;
  final AppState? appState;

  @override
  State<DeveloperToolPage> createState() => _DeveloperToolPageState();
}

class _DeveloperToolPageState extends State<DeveloperToolPage> {
  final _service = DeveloperToolsService();
  final _input = TextEditingController();
  final _second = TextEditingController();
  final _third = TextEditingController();
  String _output = '';
  bool _option = false;
  String _choice = '';
  Map<String, String> _digestResults = const {};
  String? _digestSource;
  bool _hashingFile = false;
  bool _regexMultiLine = false;
  bool _regexDotAll = false;
  int _bitWidth = 32;
  ToolDraftRepository? _drafts;
  Timer? _draftTimer;
  bool _draftLoaded = false;
  String? _lastDraftFingerprint;

  String get _title =>
      const {
        'base64': 'Base64 编解码',
        'url_codec': 'URL 编解码',
        'timestamp': '时间戳转换',
        'regex': '正则测试',
        'radix': '进制转换',
        'bits': '位计算器',
        'diff': '文本对比',
        'formatter': '代码格式化',
        'hash': 'Hash / HMAC',
        'jwt': 'JWT 解码器',
        'generator': 'UUID / ULID / 密码',
        'chmod': 'chmod 权限计算',
        'unicode': 'Unicode 转换',
        'html_entity': 'HTML 实体转换',
        'hexdump': 'Hexdump',
        'url_parser': 'URL 解析器',
        'compression': 'Gzip 压缩',
        'data_convert': 'JSON / YAML / CSV 转换',
        'json_query': 'JSONPath 查询',
        'cron': 'Cron 表达式',
        'endian': '字节序与整数',
        'user_agent': 'User-Agent 解析',
      }[widget.mode] ??
      '开发工具';

  @override
  void initState() {
    super.initState();
    _applyDefaults();
    final appState = widget.appState;
    if (appState != null) {
      _drafts = ToolDraftRepository(appState.database);
      _restoreDraft();
      _draftTimer = Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => _saveDraftIfChanged(),
      );
    }
  }

  void _applyDefaults() {
    _choice = switch (widget.mode) {
      'formatter' => 'json',
      'bits' => 'AND',
      'hash' => 'sha256',
      'generator' => 'uuid',
      'data_convert' => 'json_yaml',
      'base64' || 'url_codec' => 'encode',
      _ => '',
    };
    if (widget.mode == 'radix') {
      _input.text = 'FF';
      _second.text = '16';
    }
    if (widget.mode == 'timestamp')
      _input.text = '${DateTime.now().millisecondsSinceEpoch}';
    if (widget.mode == 'cron') _input.text = '*/5 * * * *';
    if (widget.mode == 'generator') _third.text = '5';
    if (widget.mode == 'json_query') {
      _input.text = '{"users":[{"name":"Alice"},{"name":"Bob"}]}';
      _second.text = r'$.users[*].name';
    }
  }

  String get _draftScope => 'tool.developer.${widget.mode}';

  Map<String, Object?> _draftSnapshot() => {
    if (widget.mode != 'jwt') 'input': _input.text,
    if (widget.mode != 'hash' && widget.mode != 'jwt') 'second': _second.text,
    'third': _third.text,
    'option': _option,
    'choice': _choice,
    'regexMultiLine': _regexMultiLine,
    'regexDotAll': _regexDotAll,
    'bitWidth': _bitWidth,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts?.load(_draftScope);
    if (!mounted) return;
    if (draft != null) {
      final payload = draft.payload;
      _input.text = payload['input']?.toString() ?? _input.text;
      _second.text = payload['second']?.toString() ?? _second.text;
      _third.text = payload['third']?.toString() ?? _third.text;
      setState(() {
        _option = payload['option'] == true;
        _choice = payload['choice']?.toString() ?? _choice;
        _regexMultiLine = payload['regexMultiLine'] == true;
        _regexDotAll = payload['regexDotAll'] == true;
        _bitWidth = (payload['bitWidth'] as num?)?.toInt() ?? _bitWidth;
      });
    }
    _draftLoaded = true;
    _lastDraftFingerprint = _draftFingerprint();
  }

  String _draftFingerprint() => _draftSnapshot().toString();

  void _saveDraftIfChanged() {
    if (!_draftLoaded) return;
    final fingerprint = _draftFingerprint();
    if (fingerprint == _lastDraftFingerprint) return;
    _lastDraftFingerprint = fingerprint;
    _drafts?.scheduleSave(_draftScope, _draftSnapshot());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (_draftLoaded && _drafts != null) {
      unawaited(_drafts!.save(_draftScope, _draftSnapshot()));
    }
    _drafts?.dispose();
    _input.dispose();
    _second.dispose();
    _third.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LocalizedText(_title),
      actions: [
        IconButton(
          tooltip: context.tr('恢复默认'),
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.mode == 'base64' || widget.mode == 'url_codec') ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'encode',
                icon: Icon(Icons.lock_outline_rounded),
                label: LocalizedText('编码'),
              ),
              ButtonSegment(
                value: 'decode',
                icon: Icon(Icons.lock_open_rounded),
                label: LocalizedText('解码'),
              ),
            ],
            selected: {_choice},
            onSelectionChanged: (value) =>
                setState(() => _choice = value.first),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.mode == 'timestamp') ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: LocalizedText(
                      '自动识别秒、毫秒、微秒、纳秒和 ISO 8601；支持每行一条批量转换。',
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _input.text =
                          '${DateTime.now().millisecondsSinceEpoch}',
                    ),
                    child: const LocalizedText('填入现在'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.mode == 'regex') ...[
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              label: LocalizedText('常用正则模板'),
              prefixIcon: Icon(Icons.bookmarks_outlined),
            ),
            items: [
              for (var index = 0; index < _regexTemplates.length; index++)
                DropdownMenuItem(
                  value: index,
                  child: LocalizedText(_regexTemplates[index].label),
                ),
            ],
            onChanged: (index) {
              if (index == null) return;
              final template = _regexTemplates[index];
              setState(() {
                _second.text = template.pattern;
                _input.text = template.example;
                _third.text = template.replacement;
              });
            },
          ),
          const SizedBox(height: 12),
        ],
        if (widget.mode == 'generator')
          DropdownButtonFormField<String>(
            initialValue: _choice,
            items: const [
              DropdownMenuItem(value: 'uuid', child: LocalizedText('UUID v4')),
              DropdownMenuItem(value: 'uuid7', child: LocalizedText('UUID v7')),
              DropdownMenuItem(value: 'ulid', child: LocalizedText('ULID')),
              DropdownMenuItem(value: 'password', child: LocalizedText('安全密码')),
              DropdownMenuItem(
                value: 'hex',
                child: LocalizedText('随机 Hex Token'),
              ),
              DropdownMenuItem(
                value: 'base64url',
                child: LocalizedText('随机 Base64URL Token'),
              ),
            ],
            onChanged: (v) => setState(() => _choice = v ?? 'uuid'),
            decoration: const InputDecoration(label: LocalizedText('类型')),
          ),
        if (widget.mode == 'data_convert')
          DropdownButtonFormField<String>(
            initialValue: _choice,
            items: const [
              DropdownMenuItem(
                value: 'json_yaml',
                child: LocalizedText('JSON → YAML'),
              ),
              DropdownMenuItem(
                value: 'yaml_json',
                child: LocalizedText('YAML → JSON'),
              ),
              DropdownMenuItem(
                value: 'csv_json',
                child: LocalizedText('CSV → JSON'),
              ),
              DropdownMenuItem(
                value: 'json_csv',
                child: LocalizedText('JSON → CSV'),
              ),
            ],
            onChanged: (v) => setState(() => _choice = v ?? 'json_yaml'),
            decoration: const InputDecoration(label: LocalizedText('转换方向')),
          ),
        if (widget.mode == 'formatter')
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'json', label: LocalizedText('JSON')),
              ButtonSegment(value: 'xml', label: LocalizedText('XML')),
              ButtonSegment(value: 'yaml', label: LocalizedText('YAML')),
              ButtonSegment(value: 'sql', label: LocalizedText('SQL')),
            ],
            selected: {_choice},
            onSelectionChanged: (v) => setState(() => _choice = v.first),
          ),
        if (widget.mode == 'bits')
          DropdownButtonFormField<String>(
            initialValue: _choice,
            items: const ['AND', 'OR', 'XOR', 'NOT', 'SHL', 'SHR', 'ROL', 'ROR']
                .map((v) => DropdownMenuItem(value: v, child: LocalizedText(v)))
                .toList(),
            onChanged: (v) => setState(() => _choice = v ?? 'AND'),
            decoration: const InputDecoration(label: LocalizedText('运算')),
          ),
        if (widget.mode == 'hash')
          TextField(
            controller: _second,
            decoration: const InputDecoration(
              label: LocalizedText('HMAC 密钥（留空为普通 Hash）'),
            ),
          ),
        if (widget.mode == 'jwt')
          TextField(
            controller: _second,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              label: LocalizedText('HMAC 验签密钥（可选）'),
              helper: LocalizedText('仅支持 HS256 / HS384 / HS512，密钥不会保存到草稿'),
            ),
          ),
        if (widget.mode == 'generator')
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _second,
                  enabled: const {
                    'password',
                    'hex',
                    'base64url',
                  }.contains(_choice),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    label: LocalizedText(
                      _choice == 'password' ? '密码长度（默认 24）' : '随机字节数（默认 24）',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _third,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    label: LocalizedText('生成数量（1～100）'),
                  ),
                ),
              ),
            ],
          ),
        if (widget.mode == 'json_query')
          TextField(
            controller: _second,
            decoration: InputDecoration(
              labelText: context.tr(r'JSONPath（如 $.users[0].name）'),
            ),
          ),
        if (widget.mode == 'regex')
          TextField(
            controller: _second,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              label: LocalizedText('正则表达式'),
              hint: LocalizedText(r'例如：\b\d{1,3}(?:\.\d{1,3}){3}\b'),
            ),
          ),
        if (widget.mode == 'diff')
          TextField(
            controller: _second,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(label: LocalizedText('修改后的文本')),
          ),
        if (widget.mode == 'radix')
          TextField(
            controller: _second,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              label: LocalizedText('源进制（2～36）'),
            ),
          ),
        if (widget.mode == 'bits')
          TextField(
            controller: _second,
            decoration: const InputDecoration(label: LocalizedText('右操作数')),
          ),
        if (widget.mode == 'regex') ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const LocalizedText('忽略大小写'),
                selected: _option,
                onSelected: (value) => setState(() => _option = value),
              ),
              FilterChip(
                label: const LocalizedText('多行模式'),
                selected: _regexMultiLine,
                onSelected: (value) => setState(() => _regexMultiLine = value),
              ),
              FilterChip(
                label: const LocalizedText('点号匹配换行'),
                selected: _regexDotAll,
                onSelected: (value) => setState(() => _regexDotAll = value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _third,
            decoration: const InputDecoration(
              label: LocalizedText('替换表达式（可选）'),
              helper: LocalizedText(r'支持 $1、$2 等捕获组引用'),
            ),
          ),
        ],
        if (widget.mode == 'bits') ...[
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 8, label: Text('8 bit')),
              ButtonSegment(value: 16, label: Text('16 bit')),
              ButtonSegment(value: 32, label: Text('32 bit')),
              ButtonSegment(value: 64, label: Text('64 bit')),
            ],
            selected: {_bitWidth},
            onSelectionChanged: (value) =>
                setState(() => _bitWidth = value.first),
          ),
        ],
        if (_presets.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const LocalizedText(
                  '常用示例',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final preset in _presets)
                  ActionChip(
                    avatar: const Icon(Icons.bolt_rounded, size: 16),
                    label: LocalizedText(preset.label),
                    onPressed: () => setState(() {
                      _input.text = preset.input;
                      if (preset.second != null) _second.text = preset.second!;
                      if (preset.choice != null) _choice = preset.choice!;
                    }),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: LocalizedText(
                '输入内容',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: context.tr('从剪贴板粘贴'),
              onPressed: _pasteInput,
              icon: const Icon(Icons.content_paste_rounded),
            ),
            IconButton(
              tooltip: context.tr('从文件载入'),
              onPressed: _loadInputFile,
              icon: const Icon(Icons.file_open_outlined),
            ),
            if (_canSwap)
              IconButton(
                tooltip: context.tr('交换输入与结果'),
                onPressed: _output.isEmpty ? null : _swapInputAndOutput,
                icon: const Icon(Icons.swap_vert_rounded),
              ),
            IconButton(
              tooltip: context.tr('清空输入'),
              onPressed: _input.text.isEmpty
                  ? null
                  : () => setState(_input.clear),
              icon: const Icon(Icons.clear_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _input,
          minLines: widget.mode == 'radix' || widget.mode == 'generator'
              ? 1
              : widget.mode == 'timestamp'
              ? 4
              : 5,
          maxLines: 14,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: context.tr(widget.mode == 'diff' ? '原文本' : '输入'),
          ),
        ),
        if ({
          'base64',
          'url_codec',
          'diff',
          'formatter',
          'unicode',
          'html_entity',
          'hexdump',
          'compression',
          'endian',
        }.contains(widget.mode))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _option,
            onChanged: (v) => setState(() => _option = v),
            title: LocalizedText(switch (widget.mode) {
              'base64' => 'URL-safe',
              'url_codec' => '完整 URL',
              'diff' => '按单词',
              'formatter' => '压缩',
              'unicode' || 'html_entity' || 'hexdump' || 'compression' => '解码',
              'endian' => '64 位（关闭为 32 位）',
              _ => '选项',
            }),
          ),
        if (widget.mode == 'hash')
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _hashingFile ? null : _run,
                icon: const Icon(Icons.calculate_outlined),
                label: const LocalizedText('计算文本'),
              ),
              OutlinedButton.icon(
                onPressed: _hashingFile ? null : _pickAndHashFile,
                icon: const Icon(Icons.upload_file_rounded),
                label: LocalizedText(_hashingFile ? '正在计算…' : '选择文件计算'),
              ),
            ],
          )
        else
          FilledButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.play_arrow),
            label: const LocalizedText('执行'),
          ),
        if (_hashingFile) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 16),
        if (widget.mode == 'hash' && _digestResults.isNotEmpty)
          _DigestResultList(
            source: _digestSource ?? '输入文本',
            isHmac: _second.text.isNotEmpty && _digestSource == '输入文本',
            results: _digestResults,
          ),
        if (widget.mode == 'hash' && _output.startsWith('错误：'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LocalizedText(
              _output,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_output.isNotEmpty && widget.mode != 'hash')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: LocalizedText(
                          '结果',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: _output)),
                        tooltip: context.tr('复制全部'),
                        icon: const Icon(Icons.copy),
                      ),
                      IconButton(
                        onPressed: _exportOutput,
                        tooltip: context.tr('导出结果'),
                        icon: const Icon(Icons.download_outlined),
                      ),
                    ],
                  ),
                  if (StructuredPayload(rawText: _output).canFormat)
                    SizedBox(
                      height: 420,
                      child: StructuredDataViewer(
                        payload: StructuredPayload(
                          rawText: _output,
                          source: '开发工具',
                        ),
                      ),
                    )
                  else
                    _PlainResultList(text: _output),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  bool get _canSwap => const {
    'base64',
    'url_codec',
    'unicode',
    'html_entity',
    'hexdump',
    'compression',
    'formatter',
  }.contains(widget.mode);

  Future<void> _pasteInput() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null) return;
    setState(() => _input.text = text);
  }

  Future<void> _loadInputFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: context.tr('选择输入文件'),
      allowMultiple: false,
      withData: false,
      lockParentWindow: true,
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final file = File(path);
      final size = await file.length();
      if (size > 8 * 1024 * 1024) {
        throw const FormatException('文本文件不能超过 8 MiB');
      }
      final text = await file.readAsString();
      if (mounted) setState(() => _input.text = text);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('读取失败：$error')));
      }
    }
  }

  void _swapInputAndOutput() {
    final previousInput = _input.text;
    setState(() {
      _input.text = _output;
      _output = previousInput;
      if (widget.mode == 'base64' || widget.mode == 'url_codec') {
        _choice = _choice == 'encode' ? 'decode' : 'encode';
      } else if ({
        'unicode',
        'html_entity',
        'hexdump',
        'compression',
      }.contains(widget.mode)) {
        _option = !_option;
      }
    });
  }

  Future<void> _exportOutput() async {
    final saved = await DownloadDestinationService.saveBytes(
      bytes: Uint8List.fromList(utf8.encode(_output)),
      dialogTitle: context.tr('导出结果'),
      fileName: '${widget.mode}_result.txt',
      allowedExtensions: const ['txt'],
      mimeType: 'text/plain',
    );
    if (saved == null || !mounted) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText('已保存：${saved.displayLocation}')),
      );
    }
  }

  Future<void> _reset() async {
    await _drafts?.reset(_draftScope);
    if (!mounted) return;
    setState(() {
      _input.clear();
      _second.clear();
      _third.clear();
      _output = '';
      _digestResults = const {};
      _digestSource = null;
      _option = false;
      _regexMultiLine = false;
      _regexDotAll = false;
      _bitWidth = 32;
      _applyDefaults();
    });
    _lastDraftFingerprint = _draftFingerprint();
  }

  void _run() {
    try {
      if (widget.mode == 'hash') {
        _digestResults = const {};
        _digestSource = null;
      }
      final result = switch (widget.mode) {
        'base64' =>
          _choice == 'decode'
              ? _service.base64DecodeText(_input.text, urlSafe: _option)
              : _service.base64EncodeText(_input.text, urlSafe: _option),
        'url_codec' =>
          _choice == 'decode'
              ? _service.urlDecode(_input.text, fullUrl: _option)
              : _service.urlEncode(_input.text, fullUrl: _option),
        'timestamp' => _timestampReport(),
        'regex' => _regexReport(),
        'radix' => _radix(),
        'bits' =>
          _service
              .bitCalculate(
                left: _input.text,
                operation: _choice,
                right: _second.text,
                width: _bitWidth,
              )
              .entries
              .map((e) => '${e.key}: ${e.value}')
              .join('\n'),
        'diff' =>
          _service
              .diff(_input.text, _second.text, byWord: _option)
              .map(
                (p) =>
                    '${switch (p.kind) {
                      DiffKind.equal => ' ',
                      DiffKind.added => '+',
                      DiffKind.removed => '-',
                    }} ${p.text}',
              )
              .join('\n'),
        'formatter' => _service.formatCode(
          _input.text,
          _choice,
          compact: _option,
        ),
        'hash' => _runTextDigest(),
        'jwt' => _service.decodeJwt(_input.text, secret: _second.text),
        'generator' => _generateBatch(),
        'chmod' => _service.chmodConvert(_input.text),
        'unicode' => _service.unicodeConvert(_input.text, decode: _option),
        'html_entity' => _service.htmlEntityConvert(
          _input.text,
          decode: _option,
        ),
        'hexdump' => _service.hexDump(_input.text, decode: _option),
        'url_parser' => _service.inspectUrl(_input.text),
        'compression' => _service.compression(_input.text, decode: _option),
        'data_convert' => _service.convertStructuredData(_input.text, _choice),
        'json_query' => _service.queryJson(_input.text, _second.text),
        'cron' => _service.nextCronRuns(_input.text),
        'endian' => _service.endianView(_input.text, width: _option ? 64 : 32),
        'user_agent' => _service.parseUserAgent(_input.text),
        _ => '',
      };
      setState(() => _output = result.isEmpty ? '无匹配结果' : result);
    } on Object catch (e) {
      setState(() => _output = '错误：$e');
    }
  }

  String _runTextDigest() {
    final results = _service.digestAll(_input.text, key: _second.text);
    _digestResults = results;
    _digestSource = '输入文本';
    return results.values.join('\n');
  }

  Future<void> _pickAndHashFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: context.tr('选择要计算 Hash 的文件'),
      allowMultiple: false,
      withData: false,
      lockParentWindow: true,
    );
    final selected = picked?.files.single;
    if (selected?.path == null) return;
    setState(() {
      _hashingFile = true;
      _output = '';
      _digestResults = const {};
      _digestSource = selected!.name;
    });
    try {
      final file = File(selected!.path!);
      final results = await _service.digestFile(file);
      final size = await file.length();
      if (!mounted) return;
      setState(() {
        _digestResults = results;
        _digestSource = '${selected.name} · ${_formatBytes(size)}';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _output = '错误：$error');
    } finally {
      if (mounted) setState(() => _hashingFile = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  }

  String _radix() {
    final source = int.tryParse(_second.text.trim());
    if (source == null) throw const FormatException('请填写 2～36 的源进制');
    return _service
        .radixRepresentations(_input.text, source)
        .entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }

  String _timestampReport() {
    final results = _service.inspectTimestamps(_input.text);
    return results
        .map(
          (row) => row.entries
              .map((entry) => '${entry.key}: ${entry.value}')
              .join('\n'),
        )
        .join('\n\n${'─' * 28}\n\n');
  }

  String _regexReport() {
    if (_second.text.isEmpty) throw const FormatException('请输入正则表达式');
    final matches = _service.testRegex(
      _second.text,
      _input.text,
      caseSensitive: !_option,
      multiLine: _regexMultiLine,
      dotAll: _regexDotAll,
    );
    final buffer = StringBuffer('匹配数量: ${matches.length}\n');
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      buffer
        ..writeln('\n#${index + 1}  ${match.start}..${match.end}')
        ..writeln('完整匹配: ${match.text}')
        ..writeln(
          match.groups.isEmpty
              ? '捕获组: 无'
              : '捕获组: ${[for (var group = 0; group < match.groups.length; group++) r'$'
                      '${group + 1}=${match.groups[group] ?? '<未匹配>'}'].join(', ')}',
        );
    }
    if (_third.text.isNotEmpty) {
      buffer
        ..writeln('\n${'─' * 28}')
        ..writeln('替换预览:')
        ..write(
          _service.regexReplace(
            _second.text,
            _input.text,
            _third.text,
            caseSensitive: !_option,
            multiLine: _regexMultiLine,
            dotAll: _regexDotAll,
          ),
        );
    }
    return buffer.toString().trimRight();
  }

  String _generateBatch() {
    final count = int.tryParse(_third.text.trim()) ?? 1;
    if (count < 1 || count > 100) {
      throw const FormatException('生成数量必须为 1～100');
    }
    final length = int.tryParse(_second.text.trim()) ?? 24;
    return [
      for (var index = 0; index < count; index++)
        _service.generate(_choice, length: length),
    ].join('\n');
  }

  List<_InputPreset> get _presets => switch (widget.mode) {
    'base64' => const [
      _InputPreset('UTF-8 文本', 'ProtoDeck network toolkit'),
      _InputPreset('JSON', '{"name":"ProtoDeck","ok":true}'),
    ],
    'url_codec' => const [
      _InputPreset('查询参数', 'keyword=network tools&platform=Android'),
      _InputPreset('完整网址', 'https://example.com/search?q=network tools'),
    ],
    'chmod' => const [
      _InputPreset('常用 755', '755'),
      _InputPreset('文件 644', '644'),
      _InputPreset('私钥 600', '600'),
      _InputPreset('符号权限', 'rwxr-x---'),
    ],
    'cron' => const [
      _InputPreset('每 5 分钟', '*/5 * * * *'),
      _InputPreset('每小时', '0 * * * *'),
      _InputPreset('每天零点', '0 0 * * *'),
      _InputPreset('工作日 9 点', '0 9 * * 1-5'),
      _InputPreset('英文星期', '0 9 * * MON-FRI'),
      _InputPreset('每周宏', '@weekly'),
    ],
    'json_query' => const [
      _InputPreset(
        '数组字段',
        '{"users":[{"name":"Alice"},{"name":"Bob"}]}',
        second: r'$.users[*].name',
      ),
      _InputPreset(
        '嵌套字段',
        '{"data":{"network":{"gateway":"192.168.1.1"}}}',
        second: r'$.data.network.gateway',
      ),
      _InputPreset(
        '条件过滤',
        '{"devices":[{"name":"router","online":true},{"name":"nas","online":false}]}',
        second: r'$.devices[?(@.online == true)].name',
      ),
      _InputPreset(
        '递归查找',
        '{"site":{"gateway":"192.168.1.1","backup":{"gateway":"10.0.0.1"}}}',
        second: r'$..gateway',
      ),
    ],
    'formatter' => const [
      _InputPreset(
        'JSON',
        '{"name":"ProtoDeck","items":[1,2]}',
        choice: 'json',
      ),
      _InputPreset(
        'XML',
        '<root><item id="1">value</item></root>',
        choice: 'xml',
      ),
      _InputPreset(
        'YAML',
        'name: ProtoDeck\nitems:\n  - one\n  - two',
        choice: 'yaml',
      ),
      _InputPreset(
        'SQL',
        'select id,name from users where active=1 order by name',
        choice: 'sql',
      ),
    ],
    'url_parser' => const [
      _InputPreset(
        'HTTPS URL',
        'https://user:pass@example.com:8443/api/items?q=network#result',
      ),
      _InputPreset('IPv6 URL', 'http://[2001:db8::1]:8080/status'),
    ],
    'endian' => const [
      _InputPreset('32 位整数', '0x12345678'),
      _InputPreset('十进制', '305419896'),
    ],
    'user_agent' => const [
      _InputPreset(
        'Chrome / Windows',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36',
      ),
      _InputPreset(
        'Android WebView',
        'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Version/4.0 Chrome/126.0 Mobile Safari/537.36; wv',
      ),
    ],
    'jwt' => const [
      _InputPreset(
        '示例 Token',
        'eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiI0MiIsIm5hbWUiOiJQcm90b0RlY2sifQ.',
      ),
    ],
    'data_convert' => const [
      _InputPreset(
        'JSON → YAML',
        '{"name":"ProtoDeck","port":8080}',
        choice: 'json_yaml',
      ),
      _InputPreset(
        'YAML → JSON',
        'name: ProtoDeck\nport: 8080',
        choice: 'yaml_json',
      ),
      _InputPreset(
        'CSV → JSON',
        'name,port\nProtoDeck,8080',
        choice: 'csv_json',
      ),
    ],
    'unicode' => const [_InputPreset('中英文', 'ProtoDeck network toolkit')],
    'html_entity' => const [
      _InputPreset('HTML 片段', '<div class="tool">ProtoDeck & network</div>'),
    ],
    'hexdump' => const [
      _InputPreset('协议文本', 'GET / HTTP/1.1\r\nHost: example.com'),
    ],
    'compression' => const [
      _InputPreset('重复文本', 'ProtoDeck ProtoDeck ProtoDeck network toolkit'),
    ],
    'diff' => const [
      _InputPreset(
        '配置差异',
        'host=192.168.1.1\nport=80\ntls=false',
        second: 'host=192.168.1.1\nport=443\ntls=true',
      ),
    ],
    _ => const [],
  };
}

class _InputPreset {
  const _InputPreset(this.label, this.input, {this.second, this.choice});

  final String label;
  final String input;
  final String? second;
  final String? choice;
}

class _RegexTemplate {
  const _RegexTemplate(
    this.label,
    this.pattern,
    this.example, {
    this.replacement = '',
  });

  final String label;
  final String pattern;
  final String example;
  final String replacement;
}

const _regexTemplates = <_RegexTemplate>[
  _RegexTemplate(
    '邮箱地址',
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    'support@example.com\ninvalid@@example',
  ),
  _RegexTemplate(
    'IPv4 地址',
    r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b',
    'gateway=192.168.8.1\ninvalid=999.1.1.1',
  ),
  _RegexTemplate(
    'MAC 地址',
    r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b',
    'router 94:83:c4:c4:a6:63\nnot-a-mac',
  ),
  _RegexTemplate(
    'URL',
    r'https?://[^\s<>"\x27]+',
    'Docs: https://example.com/api?q=network',
  ),
  _RegexTemplate(
    'UUID',
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b',
    '550e8400-e29b-41d4-a716-446655440000',
  ),
  _RegexTemplate(
    '日期 YYYY-MM-DD',
    r'\b(\d{4})-(0[1-9]|1[0-2])-([0-2]\d|3[01])\b',
    'release=2026-07-27',
    replacement: r'$1/$2/$3',
  ),
  _RegexTemplate('中国大陆手机号', r'(?<!\d)1[3-9]\d{9}(?!\d)', 'phone=13800138000'),
  _RegexTemplate(
    '十六进制颜色',
    r'(?<![0-9A-Fa-f])#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\b',
    'primary #3478F6, overlay #3478F680',
  ),
];

class _PlainResultList extends StatelessWidget {
  const _PlainResultList({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final localizedText = context.tr(text);
    final lines = const LineSplitter().convert(localizedText);
    if (lines.length < 2) {
      return SelectableText(
        localizedText,
        style: const TextStyle(fontFamily: 'monospace'),
      );
    }
    final visible = lines.take(250).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visible.length; index++)
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: .45),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SelectableText(
                      visible[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.tr('复制本行'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: visible[index])),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                ),
              ],
            ),
          ),
        if (lines.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: LocalizedText(
              '结果共有 ${lines.length} 行，页面仅显示前 ${visible.length} 行；复制全部或导出可获得完整结果。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _DigestResultList extends StatelessWidget {
  const _DigestResultList({
    required this.source,
    required this.isHmac,
    required this.results,
  });

  final String source;
  final bool isHmac;
  final Map<String, String> results;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            isHmac ? 'HMAC 计算结果' : 'Hash 计算结果',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          LocalizedText(
            source,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in results.entries) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: LocalizedText(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      entry.value,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('复制 ${entry.key}'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: entry.value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: LocalizedText('已复制 ${entry.key}')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 19),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}
