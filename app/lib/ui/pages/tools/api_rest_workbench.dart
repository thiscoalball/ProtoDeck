import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/structured_payload.dart';
import '../../../services/api_rule_engine.dart';
import '../../../services/api_response_comparison.dart';
import '../../../services/api_workspace_store.dart';
import '../../../services/api_workbench_service.dart';
import '../../widgets/structured_data_viewer.dart';
import 'api_editor_widgets.dart';

class ApiRestWorkbench extends StatefulWidget {
  const ApiRestWorkbench({
    super.key,
    this.initialTemplateId,
    this.environment,
    this.onWorkspaceChanged,
    this.onManageEnvironments,
  });

  final String? initialTemplateId;
  final Map<String, String>? environment;
  final Future<void> Function()? onWorkspaceChanged;
  final VoidCallback? onManageEnvironments;

  @override
  State<ApiRestWorkbench> createState() => _ApiRestWorkbenchState();
}

class _ApiRestWorkbenchState extends State<ApiRestWorkbench> {
  final _service = ApiWorkbenchService();
  final _workspaceStore = ApiWorkspaceStore();
  final _url = TextEditingController(text: 'https://httpbin.org/anything/{id}');
  final _body = TextEditingController(text: '{\n  "hello": "{{name}}"\n}');
  final _bearer = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _apiKeyName = TextEditingController(text: 'X-API-Key');
  final _apiKeyValue = TextEditingController();
  final _responseSearch = TextEditingController();
  final _query = <ApiFieldRow>[ApiFieldRow(name: 'debug', value: 'true')];
  final _path = <ApiFieldRow>[ApiFieldRow(name: 'id', value: '1')];
  final _headers = <ApiFieldRow>[
    ApiFieldRow(name: 'Accept', value: 'application/json'),
  ];
  final _cookies = <ApiFieldRow>[];
  final _form = <ApiFieldRow>[];
  final _files = <_UploadPart>[];
  Map<String, String> _environment = {'name': 'ProtoDeck'};
  List<Map<String, Object?>> _templates = [];
  List<Map<String, Object?>> _history = [];
  Timer? _draftTimer;
  bool _stateLoaded = false;
  String? _lastDraftFingerprint;
  String? _activeTemplateId;
  String _method = 'GET';
  String _auth = 'none';
  String _apiKeyPlacement = 'header';
  String _bodyMode = 'none';
  String _rawContentType = 'text/plain';
  int _requestTab = 0;
  int _responseTab = 0;
  int _timeoutSeconds = 20;
  bool _followRedirects = true;
  bool _allowBadCertificates = false;
  bool _busy = false;
  ApiResponseData? _response;
  ApiResponseData? _previousResponse;
  final _assertions = <ApiAssertionRule>[
    const ApiAssertionRule(
      type: ApiAssertionType.statusRange,
      expected: '200-399',
    ),
  ];
  final _extractions = <ApiExtractionRule>[];
  ApiRuleRun? _ruleRun;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.addListener(_syncPathParameters);
    _loadState();
    _draftTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _saveDraftIfChanged(),
    );
  }

  @override
  void didUpdateWidget(covariant ApiRestWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.environment != oldWidget.environment &&
        widget.environment != null) {
      setState(() => _environment = Map.of(widget.environment!));
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (_stateLoaded) unawaited(_saveDraft(force: true));
    _service.cancel();
    for (final controller in [
      _url,
      _body,
      _bearer,
      _username,
      _password,
      _apiKeyName,
      _apiKeyValue,
      _responseSearch,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final request = _requestComposer();
      final response = _response;
      if (constraints.maxWidth >= 1080 && response != null) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: request),
            const SizedBox(width: 18),
            Container(
              width: 1,
              height: 720,
              color: Theme.of(context).dividerColor,
            ),
            const SizedBox(width: 18),
            Expanded(child: _responseView(response)),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          request,
          if (response != null) ...[
            const SizedBox(height: 18),
            _responseView(response),
          ],
        ],
      );
    },
  );

  Widget _requestComposer() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: LocalizedText(
              'REST 请求',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: widget.onManageEnvironments ?? _editEnvironment,
            icon: const Icon(Icons.data_object),
            tooltip: context.tr('环境变量'),
          ),
          IconButton(
            onPressed: _importCurl,
            icon: const Icon(Icons.content_paste_go_outlined),
            tooltip: context.tr('导入 cURL'),
          ),
          IconButton(
            onPressed: _showRequestHistory,
            icon: const Icon(Icons.history_rounded),
            tooltip: context.tr('请求历史'),
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: context.tr('请求模板'),
            onSelected: _loadTemplate,
            itemBuilder: (_) => [
              if (_templates.isEmpty)
                const PopupMenuItem(
                  enabled: false,
                  child: LocalizedText('暂无保存模板'),
                ),
              for (var index = 0; index < _templates.length; index++)
                PopupMenuItem(
                  value: index,
                  child: LocalizedText(
                    _templates[index]['name']?.toString() ?? '请求',
                  ),
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 10),
      _requestBar(),
      const SizedBox(height: 10),
      LocalizedText(
        '实际 URL：${_previewUrl()}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 12),
      _requestTabs(),
      const SizedBox(height: 10),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(_requestTab),
          child: _requestTabBody(),
        ),
      ),
      const SizedBox(height: 10),
      _requestActions(),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: LocalizedText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  Widget _requestBar() => LayoutBuilder(
    builder: (context, constraints) {
      final method = SizedBox(
        width: constraints.maxWidth < 600 ? 124 : 142,
        child: DropdownButtonFormField<String>(
          key: ValueKey('rest-method-$_method'),
          isExpanded: true,
          initialValue: _method,
          items:
              const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: LocalizedText(value),
                    ),
                  )
                  .toList(),
          onChanged: (value) => setState(() {
            _method = value ?? 'GET';
            if (_method == 'POST' && _bodyMode == 'none') _bodyMode = 'json';
          }),
          decoration: const InputDecoration(labelText: 'Method'),
        ),
      );
      final url = TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'URL',
          hintText: 'https://api.example.com/users/{id}',
        ),
      );
      final send = FilledButton.icon(
        onPressed: _busy ? _cancel : _send,
        icon: Icon(_busy ? Icons.stop : Icons.send),
        label: LocalizedText(_busy ? '取消' : '发送'),
      );
      if (constraints.maxWidth < 600) {
        return Column(
          children: [
            Row(
              children: [
                method,
                const SizedBox(width: 8),
                Expanded(child: url),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: send),
          ],
        );
      }
      return Row(
        children: [
          method,
          const SizedBox(width: 8),
          Expanded(child: url),
          const SizedBox(width: 8),
          send,
        ],
      );
    },
  );

  Widget _requestTabs() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: 0,
          label: LocalizedText(
            'Params ${_enabledCount([..._query, ..._path])}',
          ),
        ),
        ButtonSegment(
          value: 1,
          label: LocalizedText('Headers ${_enabledCount(_headers)}'),
        ),
        const ButtonSegment(value: 2, label: LocalizedText('Auth')),
        ButtonSegment(
          value: 3,
          label: LocalizedText(
            'Body${_bodyMode == 'none' ? '' : ' · $_bodyMode'}',
          ),
        ),
        ButtonSegment(
          value: 4,
          label: LocalizedText('Cookies ${_enabledCount(_cookies)}'),
        ),
        const ButtonSegment(value: 5, label: LocalizedText('设置')),
      ],
      selected: {_requestTab},
      onSelectionChanged: (value) => setState(() => _requestTab = value.first),
    ),
  );

  Widget _requestTabBody() => switch (_requestTab) {
    0 => _paramsPanel(),
    1 => ApiKeyValueEditor(
      rows: _headers,
      onChanged: () => setState(() {}),
      nameHint: 'Header 名称',
      valueHint: '值（支持 {{变量}}）',
    ),
    2 => _authPanel(),
    3 => _bodyPanel(),
    4 => ApiKeyValueEditor(
      rows: _cookies,
      onChanged: () => setState(() {}),
      nameHint: 'Cookie 名称',
      valueHint: '值',
    ),
    _ => _settingsPanel(),
  };

  Widget _paramsPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_path.isNotEmpty) ...[
        const LocalizedText(
          'Path 参数',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        ApiKeyValueEditor(
          rows: _path,
          onChanged: () => setState(() {}),
          nameHint: 'Path 参数',
          valueHint: '替换值',
        ),
        const Divider(),
      ],
      const LocalizedText(
        'Query 参数',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 7),
      ApiKeyValueEditor(
        rows: _query,
        onChanged: () => setState(() {}),
        nameHint: 'Query 名称',
        valueHint: '值',
      ),
    ],
  );

  Widget _authPanel() => Column(
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey('rest-auth-$_auth'),
        initialValue: _auth,
        items: const [
          DropdownMenuItem(value: 'none', child: LocalizedText('No Auth')),
          DropdownMenuItem(
            value: 'bearer',
            child: LocalizedText('Bearer Token'),
          ),
          DropdownMenuItem(value: 'basic', child: LocalizedText('Basic Auth')),
          DropdownMenuItem(value: 'apiKey', child: LocalizedText('API Key')),
        ],
        onChanged: (value) => setState(() => _auth = value ?? 'none'),
        decoration: const InputDecoration(label: LocalizedText('认证类型')),
      ),
      const SizedBox(height: 10),
      if (_auth == 'bearer')
        TextField(
          controller: _bearer,
          obscureText: true,
          decoration: const InputDecoration(
            label: LocalizedText('Token（支持 {{变量}}）'),
          ),
        ),
      if (_auth == 'basic')
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _username,
                decoration: const InputDecoration(label: LocalizedText('用户名')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(label: LocalizedText('密码')),
              ),
            ),
          ],
        ),
      if (_auth == 'apiKey') ...[
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _apiKeyName,
                decoration: const InputDecoration(labelText: 'Key'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _apiKeyValue,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'header', label: LocalizedText('Header')),
            ButtonSegment(value: 'query', label: LocalizedText('Query')),
          ],
          selected: {_apiKeyPlacement},
          onSelectionChanged: (value) =>
              setState(() => _apiKeyPlacement = value.first),
        ),
      ],
    ],
  );

  Widget _bodyPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'none', label: LocalizedText('none')),
            ButtonSegment(value: 'json', label: LocalizedText('JSON')),
            ButtonSegment(
              value: 'form',
              label: LocalizedText('x-www-form-urlencoded'),
            ),
            ButtonSegment(
              value: 'multipart',
              label: LocalizedText('form-data'),
            ),
            ButtonSegment(value: 'raw', label: LocalizedText('Raw')),
          ],
          selected: {_bodyMode},
          onSelectionChanged: (value) =>
              setState(() => _bodyMode = value.first),
        ),
      ),
      const SizedBox(height: 10),
      if (_bodyMode == 'json' || _bodyMode == 'raw') ...[
        if (_bodyMode == 'raw')
          DropdownButtonFormField<String>(
            key: ValueKey('rest-content-type-$_rawContentType'),
            initialValue: _rawContentType,
            items:
                const [
                      'text/plain',
                      'application/xml',
                      'text/html',
                      'application/javascript',
                      'application/octet-stream',
                    ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: LocalizedText(value),
                      ),
                    )
                    .toList(),
            onChanged: (value) =>
                setState(() => _rawContentType = value ?? 'text/plain'),
            decoration: const InputDecoration(labelText: 'Content-Type'),
          ),
        if (_bodyMode == 'raw') const SizedBox(height: 8),
        TextField(
          controller: _body,
          minLines: 8,
          maxLines: 20,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: _bodyMode == 'json' ? 'JSON Body' : 'Raw Body',
            suffixIcon: _bodyMode == 'json'
                ? IconButton(
                    onPressed: _formatBody,
                    icon: const Icon(Icons.auto_fix_high),
                    tooltip: context.tr('格式化 JSON'),
                  )
                : null,
          ),
        ),
      ],
      if (_bodyMode == 'form' || _bodyMode == 'multipart')
        ApiKeyValueEditor(
          rows: _form,
          onChanged: () => setState(() {}),
          nameHint: '字段名',
          valueHint: '字段值',
        ),
      if (_bodyMode == 'multipart') ...[
        for (final part in _files)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.attach_file),
            title: LocalizedText(part.file.name),
            subtitle: LocalizedText('${part.name} · ${part.file.size} B'),
            trailing: IconButton(
              onPressed: () => setState(() => _files.remove(part)),
              icon: const Icon(Icons.close),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file),
          label: const LocalizedText('添加文件字段'),
        ),
      ],
      if (_bodyMode == 'none')
        const Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: LocalizedText('该请求不发送 Body')),
        ),
    ],
  );

  Widget _settingsPanel() => Column(
    children: [
      TextFormField(
        initialValue: '$_timeoutSeconds',
        keyboardType: TextInputType.number,
        onChanged: (value) => _timeoutSeconds = int.tryParse(value) ?? 20,
        decoration: const InputDecoration(label: LocalizedText('超时（秒）')),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _followRedirects,
        onChanged: (value) => setState(() => _followRedirects = value),
        title: const LocalizedText('跟随重定向'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _allowBadCertificates,
        onChanged: (value) => setState(() => _allowBadCertificates = value),
        title: const LocalizedText('忽略 TLS 证书错误'),
        subtitle: const LocalizedText('仅用于调试自签名服务，不建议连接生产环境时开启'),
      ),
    ],
  );

  Widget _requestActions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        onPressed: _saveTemplate,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const LocalizedText('保存用例'),
      ),
      OutlinedButton.icon(
        onPressed: _showTemplateManager,
        icon: const Icon(Icons.folder_open_outlined),
        label: const LocalizedText('管理用例'),
      ),
      OutlinedButton.icon(
        onPressed: _copyCurl,
        icon: const Icon(Icons.terminal),
        label: const LocalizedText('复制 cURL'),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LocalizedText(
          '${_environment.length} 个环境变量',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ),
    ],
  );

  Widget _responseView(ApiResponseData response) {
    final success = response.statusCode >= 200 && response.statusCode < 400;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _metric(
                  '状态',
                  '${response.statusCode} ${response.reason}',
                  success ? Colors.green : Colors.orange,
                ),
                _metric(
                  '耗时',
                  '${response.elapsed.inMilliseconds} ms',
                  Colors.blue,
                ),
                _metric('大小', '${response.bytes} B', Colors.teal),
                _metric(
                  '类型',
                  response.headers['content-type']?.first ?? '未知',
                  Colors.purple,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: 0, label: LocalizedText('Pretty')),
              const ButtonSegment(value: 1, label: LocalizedText('Raw')),
              const ButtonSegment(value: 2, label: LocalizedText('Headers')),
              const ButtonSegment(value: 3, label: LocalizedText('Cookies')),
              const ButtonSegment(value: 4, label: LocalizedText('实际请求')),
              ButtonSegment(
                value: 5,
                enabled: _previousResponse != null,
                label: const LocalizedText('响应对比'),
              ),
            ],
            selected: {_responseTab},
            onSelectionChanged: (value) =>
                setState(() => _responseTab = value.first),
          ),
        ),
        const SizedBox(height: 10),
        if (_responseTab == 1)
          TextField(
            controller: _responseSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hint: LocalizedText('筛选包含关键词的响应行'),
            ),
          ),
        if (_responseTab == 1) const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 150, maxHeight: 560),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _responseTab == 0
              ? SizedBox(height: 420, child: _responseTabBody(response))
              : SingleChildScrollView(child: _responseTabBody(response)),
        ),
        const SizedBox(height: 12),
        _rulesPanel(),
      ],
    );
  }

  Widget _responseTabBody(ApiResponseData response) {
    if (_responseTab == 0) {
      return StructuredDataViewer(
        payload: StructuredPayload(
          rawText: response.body,
          rawBytes: response.rawBytes,
          contentType: response.headers['content-type']?.first,
          source: 'REST',
          direction: 'RX',
          metadata: {
            'statusCode': response.statusCode,
            'headers': response.headers,
            'elapsedMs': response.elapsed.inMilliseconds,
            'finalUrl': response.finalUrl.toString(),
          },
        ),
      );
    }
    if (_responseTab == 2) {
      return SelectableText(
        response.headers.entries
            .map((e) => '${e.key}: ${e.value.join(', ')}')
            .join('\n'),
        style: const TextStyle(fontFamily: 'monospace'),
      );
    }
    if (_responseTab == 3) {
      return SelectableText(
        response.cookies.isEmpty
            ? context.tr('响应未设置 Cookie')
            : response.cookies
                  .map(
                    (c) =>
                        '${c.name}=${c.value}; domain=${c.domain ?? '-'}; path=${c.path ?? '-'}; expires=${c.expires ?? '-'}',
                  )
                  .join('\n\n'),
        style: const TextStyle(fontFamily: 'monospace'),
      );
    }
    if (_responseTab == 4) {
      return SelectableText(
        '${response.requestMethod} ${response.finalUrl}\n${response.requestHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\n')}\n\n${response.requestBody}',
        style: const TextStyle(fontFamily: 'monospace'),
      );
    }
    if (_responseTab == 5) {
      return _responseComparison(response);
    }
    final text = response.body;
    final query = _responseSearch.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? text
        : const LineSplitter()
              .convert(text)
              .where((line) => line.toLowerCase().contains(query))
              .join('\n');
    return SelectableText(
      filtered.isEmpty
          ? context.tr('没有包含“${_responseSearch.text.trim()}”的行')
          : filtered,
      style: const TextStyle(fontFamily: 'monospace'),
    );
  }

  Widget _responseComparison(ApiResponseData current) {
    final previous = _previousResponse;
    if (previous == null) return const LocalizedText('再次发送后可与上次响应对比');
    final comparison = const ApiResponseComparator().compare(previous, current);
    final changes = [...comparison.headerChanges, ...comparison.bodyChanges];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: Icon(
                comparison.statusChanged
                    ? Icons.change_circle
                    : Icons.check_circle,
                size: 18,
              ),
              label: LocalizedText(
                '${previous.statusCode} → ${current.statusCode}',
              ),
            ),
            Chip(
              label: Text(
                context.l10n.toolPages.apiResponseDurationDelta(
                  _signed(comparison.elapsedDeltaMs, suffix: ' ms'),
                ),
              ),
            ),
            Chip(
              label: Text(
                context.l10n.toolPages.apiResponseSizeDelta(
                  _signed(
                    comparison.bytesDelta.toDouble(),
                    suffix: ' B',
                    decimals: 0,
                  ),
                ),
              ),
            ),
            Chip(
              label: Text(
                context.l10n.toolPages.apiResponseChangesSummary(
                  headers: comparison.headerChanges.length,
                  body: comparison.bodyChanges.length,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (comparison.identical)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle, color: Color(0xFF20A879)),
            title: LocalizedText('两次响应内容一致'),
          )
        else ...[
          for (final change in changes.take(200))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                change.kind == 'added'
                    ? Icons.add_circle_outline
                    : change.kind == 'removed'
                    ? Icons.remove_circle_outline
                    : Icons.change_circle_outlined,
                size: 19,
              ),
              title: SelectableText(
                change.path,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: SelectableText(
                '${change.before ?? '∅'}\n→ ${change.after ?? '∅'}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          if (changes.length > 200)
            Text(
              context.l10n.toolPages.apiResponseChangesTruncated(
                shown: 200,
                total: changes.length,
              ),
            ),
        ],
      ],
    );
  }

  String _signed(double value, {required String suffix, int decimals = 1}) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(decimals)}$suffix';

  Widget _rulesPanel() {
    final run = _ruleRun;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: run != null,
        title: const LocalizedText(
          '断言与变量提取',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: LocalizedText(
          run == null
              ? '${_assertions.length} 条断言 · ${_extractions.length} 条提取规则'
              : '${run.assertions.where((item) => item.passed).length}/${run.assertions.length} 断言通过 · '
                    '${run.extractions.where((item) => item.success).length}/${run.extractions.length} 提取成功',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (var index = 0; index < _assertions.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                run == null
                    ? Icons.rule_outlined
                    : run.assertions[index].passed
                    ? Icons.check_circle
                    : Icons.cancel,
                color: run == null
                    ? null
                    : run.assertions[index].passed
                    ? const Color(0xFF20A879)
                    : Theme.of(context).colorScheme.error,
              ),
              title: LocalizedText(_assertions[index].title),
              subtitle: run == null
                  ? null
                  : LocalizedText(
                      run.assertions[index].error ??
                          '实际：${run.assertions[index].actual}',
                    ),
              trailing: IconButton(
                tooltip: context.tr('删除断言'),
                onPressed: () => setState(() {
                  _assertions.removeAt(index);
                  _evaluateRules();
                }),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          for (var index = 0; index < _extractions.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                run == null
                    ? Icons.output_rounded
                    : run.extractions[index].success
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: run?.extractions[index].success == true
                    ? const Color(0xFF20A879)
                    : null,
              ),
              title: LocalizedText('提取为 {{${_extractions[index].variable}}}'),
              subtitle: LocalizedText(
                run == null
                    ? '${_extractions[index].source.name} · ${_extractions[index].selector}'
                    : run.extractions[index].success
                    ? '已写入当前会话：${_masked(run.extractions[index].value ?? '')}'
                    : run.extractions[index].error ?? '提取失败',
              ),
              trailing: IconButton(
                tooltip: context.tr('删除提取规则'),
                onPressed: () => setState(() {
                  _extractions.removeAt(index);
                  _evaluateRules();
                }),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _addAssertion,
                icon: const Icon(Icons.add_task_rounded),
                label: const LocalizedText('添加断言'),
              ),
              FilledButton.tonalIcon(
                onPressed: _addExtraction,
                icon: const Icon(Icons.output_rounded),
                label: const LocalizedText('提取变量'),
              ),
              if (_response != null)
                OutlinedButton.icon(
                  onPressed: () => setState(_evaluateRules),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const LocalizedText('重新执行'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      LocalizedText('$label  '),
      LocalizedText(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );

  int _enabledCount(List<ApiFieldRow> rows) =>
      rows.where((row) => row.enabled && row.name.trim().isNotEmpty).length;

  void _syncPathParameters() {
    final names = RegExp(
      r'\{([^{}]+)\}',
    ).allMatches(_url.text).map((m) => m.group(1)!).toSet();
    var changed = false;
    for (final name in names) {
      if (!_path.any((row) => row.name == name)) {
        _path.add(ApiFieldRow(name: name));
        changed = true;
      }
    }
    final before = _path.length;
    _path.removeWhere((row) => !names.contains(row.name));
    changed |= before != _path.length;
    if (changed && mounted) setState(() {});
  }

  String _resolved(String value) =>
      ApiWorkbenchService.substitute(value, _environment);

  String _previewUrl() {
    try {
      return _buildUrl();
    } on Object {
      return _resolved(_url.text);
    }
  }

  String _buildUrl() {
    var value = _resolved(_url.text.trim());
    for (final row in _path.where(
      (row) => row.enabled && row.name.isNotEmpty,
    )) {
      value = value.replaceAll(
        '{${row.name}}',
        Uri.encodeComponent(_resolved(row.value)),
      );
    }
    var uri = Uri.parse(value);
    final query = <String, List<String>>{
      for (final entry in uri.queryParametersAll.entries)
        entry.key: [...entry.value],
    };
    for (final row in _query.where(
      (row) => row.enabled && row.name.trim().isNotEmpty,
    )) {
      query
          .putIfAbsent(_resolved(row.name.trim()), () => [])
          .add(_resolved(row.value));
    }
    if (_auth == 'apiKey' &&
        _apiKeyPlacement == 'query' &&
        _apiKeyName.text.trim().isNotEmpty) {
      query
          .putIfAbsent(_resolved(_apiKeyName.text.trim()), () => [])
          .add(_resolved(_apiKeyValue.text));
    }
    uri = uri.replace(queryParameters: query.isEmpty ? null : query);
    return uri.toString();
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      for (final entry in enabledFieldMap(_headers).entries)
        _resolved(entry.key): _resolved(entry.value),
    };
    if (_auth == 'bearer')
      headers['Authorization'] = 'Bearer ${_resolved(_bearer.text)}';
    if (_auth == 'basic')
      headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${_resolved(_username.text)}:${_resolved(_password.text)}'))}';
    if (_auth == 'apiKey' &&
        _apiKeyPlacement == 'header' &&
        _apiKeyName.text.trim().isNotEmpty)
      headers[_resolved(_apiKeyName.text.trim())] = _resolved(
        _apiKeyValue.text,
      );
    final cookie = enabledFieldMap(_cookies).entries
        .map((e) => '${_resolved(e.key)}=${_resolved(e.value)}')
        .join('; ');
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  Future<({String text, Uint8List? bytes, String? contentType})>
  _buildBody() async {
    if (_bodyMode == 'none') return (text: '', bytes: null, contentType: null);
    if (_bodyMode == 'json') {
      final text = _resolved(_body.text);
      jsonDecode(text);
      return (
        text: text,
        bytes: null,
        contentType: 'application/json; charset=utf-8',
      );
    }
    if (_bodyMode == 'raw')
      return (
        text: _resolved(_body.text),
        bytes: null,
        contentType: _rawContentType,
      );
    if (_bodyMode == 'form') {
      final text = enabledFieldMap(_form).entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(_resolved(e.key))}=${Uri.encodeQueryComponent(_resolved(e.value))}',
          )
          .join('&');
      return (
        text: text,
        bytes: null,
        contentType: 'application/x-www-form-urlencoded',
      );
    }
    final boundary = '----ProtoDeck${DateTime.now().microsecondsSinceEpoch}';
    final builder = BytesBuilder();
    for (final entry in enabledFieldMap(_form).entries) {
      builder.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="${entry.key}"\r\n\r\n${_resolved(entry.value)}\r\n',
        ),
      );
    }
    for (final upload in _files) {
      final bytes =
          upload.file.bytes ??
          (upload.file.path == null
              ? Uint8List(0)
              : await File(upload.file.path!).readAsBytes());
      builder.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="${upload.name}"; filename="${upload.file.name}"\r\nContent-Type: application/octet-stream\r\n\r\n',
        ),
      );
      builder.add(bytes);
      builder.add(utf8.encode('\r\n'));
    }
    builder.add(utf8.encode('--$boundary--\r\n'));
    return (
      text: '<multipart ${_form.length + _files.length} parts>',
      bytes: builder.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
    );
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await _buildBody();
      final headers = _buildHeaders();
      if (body.contentType != null &&
          !headers.keys.any((key) => key.toLowerCase() == 'content-type'))
        headers['Content-Type'] = body.contentType!;
      final response = await _service.request(
        method: _method,
        url: _buildUrl(),
        headers: headers,
        body: body.text,
        bodyBytes: body.bytes,
        requestBodyPreview: body.text,
        timeout: Duration(seconds: _timeoutSeconds.clamp(1, 300)),
        followRedirects: _followRedirects,
        allowBadCertificates: _allowBadCertificates,
      );
      if (mounted)
        setState(() {
          _previousResponse = _response;
          _response = response;
          _responseTab = 0;
          _evaluateRules();
        });
      unawaited(_recordRequestHistory(response));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '请求失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _evaluateRules() {
    final response = _response;
    if (response == null) {
      _ruleRun = null;
      return;
    }
    final run = ApiRuleEngine().evaluate(
      response,
      assertions: _assertions,
      extractions: _extractions,
    );
    for (final result in run.extractions) {
      if (result.success && result.value != null) {
        _environment[result.rule.variable] = result.value!;
      }
    }
    _ruleRun = run;
  }

  Future<void> _addAssertion() async {
    var type = ApiAssertionType.jsonPathExists;
    final selector = TextEditingController(text: r'$.data');
    final expected = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LocalizedText('添加响应断言'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ApiAssertionType>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    label: LocalizedText('断言类型'),
                  ),
                  items: ApiAssertionType.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: LocalizedText(_assertionLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => type = value ?? type),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: selector,
                  decoration: const InputDecoration(
                    label: LocalizedText('Header 名或 JSONPath'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: expected,
                  decoration: const InputDecoration(
                    label: LocalizedText('期望值 / 范围 / 正则 / 毫秒'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('添加'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      setState(() {
        _assertions.add(
          ApiAssertionRule(
            type: type,
            selector: selector.text.trim(),
            expected: expected.text,
          ),
        );
        _evaluateRules();
      });
    }
    selector.dispose();
    expected.dispose();
  }

  Future<void> _addExtraction() async {
    var source = ApiExtractionSource.jsonPath;
    final variable = TextEditingController(text: 'token');
    final selector = TextEditingController(text: r'$.data.token');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LocalizedText('提取当前会话变量'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: variable,
                  decoration: const InputDecoration(
                    label: LocalizedText('变量名'),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<ApiExtractionSource>(
                  initialValue: source,
                  decoration: const InputDecoration(label: LocalizedText('来源')),
                  items: ApiExtractionSource.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: LocalizedText(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => source = value ?? source),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: selector,
                  decoration: const InputDecoration(
                    label: LocalizedText('JSONPath / Header / Cookie / 正则'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('添加'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true &&
        RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(variable.text.trim())) {
      setState(() {
        _extractions.add(
          ApiExtractionRule(
            variable: variable.text.trim(),
            source: source,
            selector: selector.text.trim(),
          ),
        );
        _evaluateRules();
      });
    }
    variable.dispose();
    selector.dispose();
  }

  void _cancel() {
    _service.cancel();
    setState(() {
      _busy = false;
      _error = '请求已取消';
    });
  }

  void _formatBody() {
    try {
      _body.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(_body.text));
    } on Object catch (error) {
      _show('$error');
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;
    if (file == null || !mounted) return;
    final name = TextEditingController(text: 'file');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('文件字段'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(label: LocalizedText('字段名')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('添加'),
          ),
        ],
      ),
    );
    if (accepted == true)
      setState(
        () => _files.add(
          _UploadPart(
            name.text.trim().isEmpty ? 'file' : name.text.trim(),
            file,
          ),
        ),
      );
    name.dispose();
  }

  Future<void> _copyCurl() async {
    try {
      final body = await _buildBody();
      final value = ApiWorkbenchService.curl(
        method: _method,
        url: _buildUrl(),
        headers: _buildHeaders(),
        body: body.text,
      );
      await Clipboard.setData(ClipboardData(text: value));
      _show('cURL 已复制');
    } on Object catch (error) {
      _show('$error');
    }
  }

  Future<void> _importCurl() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('导入 cURL'),
        content: SizedBox(
          width: 720,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 18,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText:
                  "curl -X POST 'https://api.example.com' -H 'Content-Type: application/json' --data-raw '{\"hello\":\"world\"}'",
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.input_rounded),
            label: const LocalizedText('导入请求'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        final imported = ApiWorkbenchService.parseCurl(controller.text);
        setState(() {
          _method = imported.method;
          _url.text = imported.url;
          _replaceRows(
            _headers,
            imported.headers.entries
                .map(
                  (entry) => ApiFieldRow(name: entry.key, value: entry.value),
                )
                .toList(),
          );
          _body.text = imported.body;
          String? contentType;
          for (final entry in imported.headers.entries) {
            if (entry.key.toLowerCase() == 'content-type') {
              contentType = entry.value.toLowerCase();
              break;
            }
          }
          _bodyMode = imported.body.isEmpty
              ? 'none'
              : contentType?.contains('application/json') == true
              ? 'json'
              : contentType?.contains('application/x-www-form-urlencoded') ==
                    true
              ? 'form'
              : 'raw';
          _rawContentType = contentType ?? 'text/plain';
          _requestTab = imported.body.isEmpty ? 0 : 3;
          _response = null;
          _error = null;
        });
        _show('cURL 请求已导入');
      } on Object catch (error) {
        _show('导入失败：$error');
      }
    }
    controller.dispose();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final env = widget.environment == null
          ? jsonDecode(
                  prefs.getString('api_environment') ?? '{"name":"ProtoDeck"}',
                )
                as Map<String, Object?>
          : widget.environment!.map((key, value) => MapEntry(key, value));
      final templates = await _workspaceStore.loadList(
        ApiWorkspaceStore.templatesKey('rest'),
        legacyKey: 'api_rest_templates',
      );
      final history = await _workspaceStore.loadList(
        ApiWorkspaceStore.sentHistoryKey('rest'),
      );
      final draft = await _workspaceStore.loadMap(
        ApiWorkspaceStore.draftKey('rest'),
      );
      final selectedIndex = widget.initialTemplateId == null
          ? -1
          : templates.indexWhere(
              (item) => item['id']?.toString() == widget.initialTemplateId,
            );
      final selected = selectedIndex < 0 ? null : templates[selectedIndex];
      if (!mounted) return;
      setState(() {
        _environment = env.map((key, value) => MapEntry(key, '$value'));
        _templates = templates.toList(growable: true);
        _history = history.take(100).toList(growable: true);
        if (draft != null) _applyState(draft);
        if (selected != null) {
          // The portable request must not wait for Keychain/Keystore access.
          // Some desktop secure-store backends can take noticeably longer or
          // be unavailable; URL, parameters and body remain usable regardless.
          _applyState(selected);
          _activeTemplateId = widget.initialTemplateId;
        }
        _stateLoaded = true;
        _lastDraftFingerprint = jsonEncode(_snapshot());
      });
      if (selected != null) {
        final selectedId = widget.initialTemplateId;
        final selectedSecrets = await _workspaceStore.loadSecrets(
          'rest_template_$selectedId',
        );
        if (!mounted || widget.initialTemplateId != selectedId) return;
        if (selectedSecrets.isNotEmpty) {
          setState(() {
            _applyState(selected, secrets: selectedSecrets);
            _lastDraftFingerprint = jsonEncode(_snapshot());
          });
        }
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to restore REST workspace: $error\n$stackTrace');
      if (mounted) setState(() => _stateLoaded = true);
    }
  }

  Future<void> _saveTemplate({Map<String, Object?>? overwrite}) async {
    final name = TextEditingController(
      text:
          overwrite?['name']?.toString() ??
          '$_method ${Uri.tryParse(_url.text)?.path ?? '请求'}',
    );
    final folder = TextEditingController(
      text: overwrite?['folder']?.toString() ?? '',
    );
    var saveCredentials = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LocalizedText('保存为调试用例'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(label: LocalizedText('用例名称')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: folder,
                decoration: const InputDecoration(
                  label: LocalizedText('集合文件夹'),
                  hintText: 'Users / Authentication',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: saveCredentials,
                onChanged: (value) =>
                    update(() => saveCredentials = value == true),
                title: const LocalizedText('保存敏感凭据'),
                subtitle: const LocalizedText(
                  'Token、密码、Cookie 与敏感 Header 将写入系统安全存储',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('保存'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      final id =
          overwrite?['id']?.toString() ??
          'rest_${DateTime.now().microsecondsSinceEpoch}';
      final value = <String, Object?>{
        ..._safeSnapshot(),
        'id': id,
        'name': name.text.trim(),
        'folder': folder.text.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      final index = _templates.indexWhere(
        (template) => template['id']?.toString() == id,
      );
      if (index < 0) {
        _templates.insert(0, value);
      } else {
        _templates[index] = value;
      }
      _activeTemplateId = id;
      await _workspaceStore.saveList(
        ApiWorkspaceStore.templatesKey('rest'),
        _templates,
      );
      if (saveCredentials) {
        await _workspaceStore.saveSecrets(
          'rest_template_$id',
          _secretSnapshot(),
        );
      } else {
        await _workspaceStore.deleteSecrets('rest_template_$id');
      }
      await widget.onWorkspaceChanged?.call();
      if (mounted) {
        setState(() {});
        _show(index < 0 ? '用例已保存' : '用例已更新');
      }
    }
    name.dispose();
    folder.dispose();
  }

  Future<void> _loadTemplate(int index) async {
    if (index < 0 || index >= _templates.length) return;
    final value = _templates[index];
    final id = value['id']?.toString() ?? 'legacy_$index';
    final secrets = await _workspaceStore.loadSecrets('rest_template_$id');
    if (!mounted) return;
    setState(() {
      _applyState(value, secrets: secrets);
      _activeTemplateId = id;
    });
    _show('已加载 ${value['name'] ?? '请求用例'}');
  }

  Map<String, Object?> _snapshot() => {
    'method': _method,
    'url': _url.text,
    'query': _query.map((row) => row.toJson()).toList(),
    'path': _path.map((row) => row.toJson()).toList(),
    'headers': _headers.map((row) => row.toJson()).toList(),
    'cookies': _cookies.map((row) => row.toJson()).toList(),
    'form': _form.map((row) => row.toJson()).toList(),
    'bodyMode': _bodyMode,
    'body': _body.text,
    'auth': _auth,
    'username': _username.text,
    'apiKeyName': _apiKeyName.text,
    'apiKeyPlacement': _apiKeyPlacement,
    'rawContentType': _rawContentType,
    'timeoutSeconds': _timeoutSeconds,
    'followRedirects': _followRedirects,
    'allowBadCertificates': _allowBadCertificates,
    'requestTab': _requestTab,
    'assertions': [
      for (final rule in _assertions)
        {
          'type': rule.type.name,
          'selector': rule.selector,
          'expected': rule.expected,
          'enabled': rule.enabled,
        },
    ],
    'extractions': [
      for (final rule in _extractions)
        {
          'variable': rule.variable,
          'source': rule.source.name,
          'selector': rule.selector,
          'group': rule.group,
          'enabled': rule.enabled,
        },
    ],
  };

  Map<String, String> _secretSnapshot() => {
    'bearer': _bearer.text,
    'password': _password.text,
    'apiKeyValue': _apiKeyValue.text,
    'headers': jsonEncode([
      for (final row in _headers)
        if (_sensitiveHeader(row.name)) row.toJson(),
    ]),
    'cookies': jsonEncode([for (final row in _cookies) row.toJson()]),
  };

  Map<String, Object?> _safeSnapshot() {
    final value = Map<String, Object?>.of(_snapshot());
    value['headers'] = [
      for (final row in _headers)
        {...row.toJson(), if (_sensitiveHeader(row.name)) 'value': ''},
    ];
    value['cookies'] = [
      for (final row in _cookies) {...row.toJson(), 'value': ''},
    ];
    value['form'] = [
      for (final row in _form)
        {...row.toJson(), if (_sensitiveFieldName(row.name)) 'value': ''},
    ];
    if (_bodyMode == 'json') value['body'] = _redactJsonText(_body.text);
    return value;
  }

  bool _sensitiveHeader(String name) {
    final normalized = name.trim().toLowerCase();
    return normalized == 'authorization' ||
        normalized == 'proxy-authorization' ||
        normalized == 'cookie' ||
        normalized == 'set-cookie' ||
        normalized.contains('token') ||
        normalized.contains('api-key') ||
        normalized.contains('apikey');
  }

  bool _sensitiveFieldName(String name) => RegExp(
    r'(password|passwd|secret|token|authorization|cookie|private.?key|api.?key)',
    caseSensitive: false,
  ).hasMatch(name);

  String _redactJsonText(String source) {
    if (source.trim().isEmpty) return source;
    try {
      Object? redact(Object? value) {
        if (value is List) return value.map(redact).toList(growable: false);
        if (value is Map) {
          return {
            for (final entry in value.entries)
              entry.key.toString(): _sensitiveFieldName(entry.key.toString())
                  ? ''
                  : redact(entry.value),
          };
        }
        return value;
      }

      return const JsonEncoder.withIndent(
        '  ',
      ).convert(redact(jsonDecode(source)));
    } on Object {
      return source;
    }
  }

  void _applyState(
    Map<String, Object?> value, {
    Map<String, String> secrets = const {},
  }) {
    List<ApiFieldRow> rows(String key) =>
        (value[key] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => ApiFieldRow.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList();
    _method = value['method']?.toString() ?? 'GET';
    _url.text = value['url']?.toString() ?? '';
    _replaceRows(_query, rows('query'));
    _replaceRows(_path, rows('path'));
    _replaceRows(_headers, rows('headers'));
    _replaceRows(_cookies, rows('cookies'));
    void restoreRows(String key, List<ApiFieldRow> target) {
      try {
        final decoded = jsonDecode(secrets[key] ?? '[]');
        if (decoded is! List) return;
        for (final raw in decoded.whereType<Map>()) {
          final saved = ApiFieldRow.fromJson(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          );
          final index = target.indexWhere(
            (row) => row.name.toLowerCase() == saved.name.toLowerCase(),
          );
          if (index < 0) {
            target.add(saved);
          } else {
            target[index].value = saved.value;
          }
        }
      } on Object {
        // Ignore malformed legacy secure values without breaking the request.
      }
    }

    restoreRows('headers', _headers);
    restoreRows('cookies', _cookies);
    _replaceRows(_form, rows('form'));
    _bodyMode = value['bodyMode']?.toString() ?? 'none';
    _body.text = value['body']?.toString() ?? '';
    _auth = value['auth']?.toString() ?? 'none';
    _username.text = value['username']?.toString() ?? '';
    _bearer.text = secrets['bearer'] ?? '';
    _password.text = secrets['password'] ?? '';
    _apiKeyName.text = value['apiKeyName']?.toString() ?? 'X-API-Key';
    _apiKeyValue.text = secrets['apiKeyValue'] ?? '';
    _apiKeyPlacement = value['apiKeyPlacement']?.toString() ?? 'header';
    _rawContentType = value['rawContentType']?.toString() ?? 'text/plain';
    _timeoutSeconds = (value['timeoutSeconds'] as num?)?.toInt() ?? 20;
    _followRedirects = value['followRedirects'] != false;
    _allowBadCertificates = value['allowBadCertificates'] == true;
    _requestTab = (value['requestTab'] as num?)?.toInt().clamp(0, 5) ?? 0;
    _assertions
      ..clear()
      ..addAll(
        (value['assertions'] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => ApiAssertionRule(
                type: ApiAssertionType.values.firstWhere(
                  (type) => type.name == item['type']?.toString(),
                  orElse: () => ApiAssertionType.statusRange,
                ),
                selector: item['selector']?.toString() ?? '',
                expected: item['expected']?.toString() ?? '',
                enabled: item['enabled'] != false,
              ),
            ),
      );
    _extractions
      ..clear()
      ..addAll(
        (value['extractions'] as List<Object?>? ?? const [])
            .whereType<Map>()
            .map(
              (item) => ApiExtractionRule(
                variable: item['variable']?.toString() ?? '',
                source: ApiExtractionSource.values.firstWhere(
                  (source) => source.name == item['source']?.toString(),
                  orElse: () => ApiExtractionSource.jsonPath,
                ),
                selector: item['selector']?.toString() ?? '',
                group: (item['group'] as num?)?.toInt() ?? 1,
                enabled: item['enabled'] != false,
              ),
            ),
      );
  }

  void _replaceRows(List<ApiFieldRow> target, List<ApiFieldRow> source) {
    target
      ..clear()
      ..addAll(source);
  }

  Future<void> _saveDraftIfChanged() async {
    if (!_stateLoaded) return;
    final fingerprint = jsonEncode(_snapshot());
    if (fingerprint == _lastDraftFingerprint) return;
    await _saveDraft(fingerprint: fingerprint);
  }

  Future<void> _saveDraft({String? fingerprint, bool force = false}) async {
    if (!_stateLoaded && !force) return;
    final value = _safeSnapshot();
    final nextFingerprint = fingerprint ?? jsonEncode(value);
    if (!force && nextFingerprint == _lastDraftFingerprint) return;
    await Future.wait([
      _workspaceStore.saveMap(ApiWorkspaceStore.draftKey('rest'), value),
    ]);
    _lastDraftFingerprint = nextFingerprint;
  }

  Future<void> _deleteTemplate(int index) async {
    if (index < 0 || index >= _templates.length) return;
    final removed = _templates.removeAt(index);
    final id = removed['id']?.toString();
    await _workspaceStore.saveList(
      ApiWorkspaceStore.templatesKey('rest'),
      _templates,
    );
    await widget.onWorkspaceChanged?.call();
    if (id != null) await _workspaceStore.deleteSecrets('rest_template_$id');
    if (_activeTemplateId == id) _activeTemplateId = null;
    if (mounted) setState(() {});
  }

  Future<void> _duplicateTemplate(int index) async {
    if (index < 0 || index >= _templates.length) return;
    final source = _templates[index];
    final sourceId = source['id']?.toString();
    final id = 'rest_${DateTime.now().microsecondsSinceEpoch}';
    final copy = <String, Object?>{
      ...source,
      'id': id,
      'name': '${source['name'] ?? '请求'} · 副本',
      'updatedAt': DateTime.now().toIso8601String(),
    };
    _templates.insert(index, copy);
    if (sourceId != null) {
      final secrets = await _workspaceStore.loadSecrets(
        'rest_template_$sourceId',
      );
      if (secrets.isNotEmpty) {
        await _workspaceStore.saveSecrets('rest_template_$id', secrets);
      }
    }
    await _workspaceStore.saveList(
      ApiWorkspaceStore.templatesKey('rest'),
      _templates,
    );
    await widget.onWorkspaceChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _renameTemplate(int index) async {
    if (index < 0 || index >= _templates.length) return;
    final template = _templates[index];
    final name = TextEditingController(
      text: template['name']?.toString() ?? '请求',
    );
    final folder = TextEditingController(
      text: template['folder']?.toString() ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('重命名与移动用例'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(label: LocalizedText('用例名称')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: folder,
              decoration: const InputDecoration(label: LocalizedText('集合文件夹')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('保存'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      _templates[index] = {
        ...template,
        'name': name.text.trim(),
        'folder': folder.text.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await _workspaceStore.saveList(
        ApiWorkspaceStore.templatesKey('rest'),
        _templates,
      );
      await widget.onWorkspaceChanged?.call();
      if (mounted) setState(() {});
    }
    name.dispose();
    folder.dispose();
  }

  Future<void> _showTemplateManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: LocalizedText(
                        '请求用例',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _saveTemplate();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const LocalizedText('保存当前请求'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _templates.isEmpty
                    ? const Center(child: LocalizedText('暂无保存模板'))
                    : ListView.builder(
                        itemCount: _templates.length,
                        itemBuilder: (context, index) {
                          final template = _templates[index];
                          final active =
                              template['id']?.toString() == _activeTemplateId;
                          return ListTile(
                            selected: active,
                            leading: const Icon(Icons.http_rounded),
                            title: LocalizedText(
                              template['name']?.toString() ?? '请求',
                            ),
                            subtitle: LocalizedText(
                              '${template['method'] ?? 'GET'} ${template['url'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _loadTemplate(index);
                            },
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                Navigator.pop(sheetContext);
                                if (action == 'overwrite') {
                                  _saveTemplate(overwrite: template);
                                } else if (action == 'duplicate') {
                                  _duplicateTemplate(index);
                                } else if (action == 'rename') {
                                  _renameTemplate(index);
                                } else if (action == 'delete') {
                                  _deleteTemplate(index);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'overwrite',
                                  child: LocalizedText('用当前请求覆盖'),
                                ),
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: LocalizedText('复制用例'),
                                ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: LocalizedText('重命名与移动'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: LocalizedText('删除用例'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recordRequestHistory(ApiResponseData response) async {
    final entry = <String, Object?>{
      'id': 'rest_history_${DateTime.now().microsecondsSinceEpoch}',
      'method': response.requestMethod,
      'url': response.finalUrl.toString(),
      'statusCode': response.statusCode,
      'elapsedMs': response.elapsed.inMicroseconds / 1000,
      'bytes': response.bytes,
      'updatedAt': DateTime.now().toIso8601String(),
      'request': _safeSnapshot(),
    };
    _history
      ..insert(0, entry)
      ..removeRange(100.clamp(0, _history.length), _history.length);
    await _workspaceStore.saveList(
      ApiWorkspaceStore.sentHistoryKey('rest'),
      _history,
    );
    await widget.onWorkspaceChanged?.call();
  }

  Future<void> _deleteHistory(int index) async {
    if (index < 0 || index >= _history.length) return;
    _history.removeAt(index);
    await _workspaceStore.saveList(
      ApiWorkspaceStore.sentHistoryKey('rest'),
      _history,
    );
    if (mounted) setState(() {});
  }

  Future<void> _clearHistory() async {
    _history.clear();
    await _workspaceStore.saveList(
      ApiWorkspaceStore.sentHistoryKey('rest'),
      _history,
    );
    if (mounted) setState(() {});
  }

  void _loadHistory(int index) {
    if (index < 0 || index >= _history.length) return;
    final request = _history[index]['request'];
    if (request is! Map) return;
    setState(() {
      _applyState(request.map((key, value) => MapEntry(key.toString(), value)));
      _activeTemplateId = null;
      _response = null;
      _error = null;
    });
    _show('历史请求已载入，敏感凭据未恢复');
  }

  Future<void> _showRequestHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: LocalizedText(
                          '请求历史',
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _history.isEmpty
                            ? null
                            : () async {
                                await _clearHistory();
                                updateSheet(() {});
                              },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const LocalizedText('清空历史'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _history.isEmpty
                      ? const Center(child: LocalizedText('暂无请求历史'))
                      : ListView.separated(
                          itemCount: _history.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _history[index];
                            final status = (item['statusCode'] as num?)
                                ?.toInt();
                            final successful = status != null && status < 400;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: successful
                                    ? const Color(
                                        0xFF18A875,
                                      ).withValues(alpha: .1)
                                    : Theme.of(
                                        context,
                                      ).colorScheme.errorContainer,
                                child: Text(
                                  status?.toString() ?? '—',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: successful
                                        ? const Color(0xFF168A5B)
                                        : Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                              title: Text(
                                '${item['method'] ?? 'GET'} ${item['url'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${(item['elapsedMs'] as num?)?.toStringAsFixed(1) ?? '—'} ms · ${item['bytes'] ?? 0} B · ${item['updatedAt'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _loadHistory(index);
                              },
                              trailing: IconButton(
                                tooltip: context.tr('删除'),
                                onPressed: () async {
                                  await _deleteHistory(index);
                                  updateSheet(() {});
                                },
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editEnvironment() async {
    final controller = TextEditingController(
      text: _environment.entries.map((e) => '${e.key}=${e.value}').join('\n'),
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('环境变量'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText: 'base_url=https://api.example.com\ntoken=...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('保存'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      final next = <String, String>{};
      for (final line in const LineSplitter().convert(controller.text)) {
        final i = line.indexOf('=');
        if (i > 0)
          next[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
      _environment = next;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_environment', jsonEncode(next));
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  void _show(String value) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: LocalizedText(value)));
  }
}

class _UploadPart {
  const _UploadPart(this.name, this.file);
  final String name;
  final PlatformFile file;
}

String _assertionLabel(ApiAssertionType value) => switch (value) {
  ApiAssertionType.statusEquals => '状态码等于',
  ApiAssertionType.statusRange => '状态码范围',
  ApiAssertionType.responseTimeMax => '响应时间上限',
  ApiAssertionType.headerExists => 'Header 存在',
  ApiAssertionType.headerEquals => 'Header 等于',
  ApiAssertionType.bodyContains => '正文包含',
  ApiAssertionType.validJson => '有效 JSON',
  ApiAssertionType.jsonPathExists => 'JSONPath 存在',
  ApiAssertionType.jsonPathEquals => 'JSONPath 等于',
  ApiAssertionType.jsonPathRegex => 'JSONPath 正则匹配',
};

String _masked(String value) {
  if (value.length <= 6) return '••••••';
  return '${value.substring(0, 3)}••••${value.substring(value.length - 2)}';
}
