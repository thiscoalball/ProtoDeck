import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/api_workspace.dart';
import '../../../services/api_workspace_store.dart';
import 'api_realtime_workbench.dart';
import 'api_rest_workbench.dart';

class ApiWorkbenchPage extends StatefulWidget {
  const ApiWorkbenchPage({super.key});

  @override
  State<ApiWorkbenchPage> createState() => _ApiWorkbenchPageState();
}

class _ApiWorkbenchPageState extends State<ApiWorkbenchPage> {
  final _store = ApiWorkspaceStore();
  final _search = TextEditingController();
  final _selectedTemplate = <int, String?>{};
  final _revisions = <int, int>{};
  List<ApiEnvironmentProfile> _environments = const [
    ApiEnvironmentProfile(
      id: 'default',
      name: 'Default',
      variables: [ApiEnvironmentVariable(name: 'name', value: 'ProtoDeck')],
    ),
  ];
  List<ApiSavedRequestSummary> _savedRequests = const [];
  String? _activeEnvironmentId = 'default';
  int _protocol = 0;
  bool _loading = false;

  static const _protocolNames = ['REST', 'WS', 'SSE', 'MQTT'];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _loadWorkspace();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ApiEnvironmentProfile? get _activeEnvironment {
    if (_environments.isEmpty) return null;
    return _environments.firstWhere(
      (item) => item.id == _activeEnvironmentId,
      orElse: () => _environments.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('API 调试台'),
        actions: [
          if (!wide)
            IconButton(
              tooltip: context.tr('请求集合'),
              onPressed: _showMobileCollections,
              icon: const Icon(Icons.account_tree_outlined),
            ),
          IconButton(
            tooltip: context.tr('管理环境'),
            onPressed: _manageEnvironments,
            icon: const Icon(Icons.tune_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: context.tr('工作区操作'),
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              if (value == 'export') unawaited(_exportWorkspace());
              if (value == 'import') unawaited(_importWorkspace());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_open_outlined),
                  title: LocalizedText('导入工作区'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: LocalizedText('导出工作区'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wide
          ? Row(
              children: [
                SizedBox(width: 286, child: _collectionSidebar()),
                const VerticalDivider(width: 1),
                Expanded(child: _workspace()),
              ],
            )
          : _workspace(),
    );
  }

  Widget _workspace() => Column(
    children: [
      _workspaceToolbar(),
      const Divider(height: 1),
      Expanded(
        child: IndexedStack(
          index: _protocol,
          children: [
            _WorkbenchScroll(
              child: ApiRestWorkbench(
                key: ValueKey(
                  'rest-${_selectedTemplate[0]}-${_revisions[0] ?? 0}',
                ),
                initialTemplateId: _selectedTemplate[0],
                environment: _activeEnvironment?.activeValues,
                onWorkspaceChanged: _refreshSavedRequests,
                onManageEnvironments: _manageEnvironments,
              ),
            ),
            for (var protocol = 1; protocol <= 3; protocol++)
              _WorkbenchScroll(
                child: ApiRealtimeWorkbench(
                  key: ValueKey(
                    '$protocol-${_selectedTemplate[protocol]}-${_revisions[protocol] ?? 0}',
                  ),
                  protocol: protocol,
                  initialTemplateId: _selectedTemplate[protocol],
                  environment: _activeEnvironment?.activeValues,
                  onWorkspaceChanged: _refreshSavedRequests,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _workspaceToolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700;
      final protocols = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (var index = 0; index < _protocolNames.length; index++)
              ButtonSegment(
                value: index,
                icon: compact ? null : Icon(_protocolIcon(index), size: 17),
                label: Text(_protocolNames[index]),
              ),
          ],
          selected: {_protocol},
          onSelectionChanged: (value) =>
              setState(() => _protocol = value.first),
        ),
      );
      final environment = Row(
        children: [
          if (_environments.isNotEmpty)
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(_activeEnvironmentId),
                initialValue: _activeEnvironment?.id,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.public_rounded, size: 18),
                  labelText: context.tr('环境'),
                  isDense: true,
                ),
                items: [
                  for (final item in _environments)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _selectEnvironment,
              ),
            ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: context.tr('新建请求'),
            onPressed: _newRequest,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [protocols, const SizedBox(height: 9), environment],
              )
            : Row(
                children: [
                  Expanded(child: protocols),
                  const SizedBox(width: 12),
                  SizedBox(width: 220, child: environment),
                ],
              ),
      );
    },
  );

  Widget _collectionSidebar({Future<void> Function()? closeAfterSelection}) {
    final query = _search.text.trim().toLowerCase();
    final filtered = _savedRequests.where((item) {
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          item.target.toLowerCase().contains(query);
    }).toList();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: LocalizedText(
                    '请求集合',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('刷新集合'),
                  onPressed: _refreshSavedRequests,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: context.tr('搜索请求或地址'),
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: LocalizedText(
                        '尚未保存请求。打开任一协议并保存为模板后，会显示在这里。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                    children: [
                      for (var protocol = 0; protocol < 4; protocol++)
                        if (filtered.any(
                          (item) => item.protocol == _workspaceId(protocol),
                        )) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 5),
                            child: Row(
                              children: [
                                Icon(_protocolIcon(protocol), size: 16),
                                const SizedBox(width: 7),
                                Text(
                                  _protocolNames[protocol],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._savedRequestGroups(
                            filtered
                                .where(
                                  (value) =>
                                      value.protocol == _workspaceId(protocol),
                                )
                                .toList(),
                            closeAfterSelection: closeAfterSelection,
                          ),
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _savedRequestTile(
    ApiSavedRequestSummary item, {
    Future<void> Function()? closeAfterSelection,
  }) {
    final protocol = _protocolIndex(item.protocol);
    final selected =
        _protocol == protocol && _selectedTemplate[protocol] == item.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: ListTile(
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dense: true,
        leading: Container(
          width: 42,
          alignment: Alignment.center,
          child: Text(
            item.method,
            style: TextStyle(
              color: _methodColor(item.method),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          item.target,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
        onTap: () async {
          setState(() {
            _protocol = protocol;
            _selectedTemplate[protocol] = item.id;
            _revisions[protocol] = (_revisions[protocol] ?? 0) + 1;
          });
          // Rebuild once more after the mobile sheet is fully dismissed. This
          // keeps selection deterministic even when the underlying editor was
          // offstage during the route transition.
          if (closeAfterSelection != null) {
            await closeAfterSelection();
            if (!mounted) return;
            setState(() {
              _revisions[protocol] = (_revisions[protocol] ?? 0) + 1;
            });
          }
        },
      ),
    );
  }

  List<Widget> _savedRequestGroups(
    List<ApiSavedRequestSummary> requests, {
    Future<void> Function()? closeAfterSelection,
  }) {
    final unfiled = requests
        .where((item) => item.folder.trim().isEmpty)
        .toList();
    final folders = <String, List<ApiSavedRequestSummary>>{};
    for (final item in requests.where(
      (item) => item.folder.trim().isNotEmpty,
    )) {
      folders.putIfAbsent(item.folder.trim(), () => []).add(item);
    }
    return [
      for (final item in unfiled)
        _savedRequestTile(item, closeAfterSelection: closeAfterSelection),
      for (final entry in folders.entries)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: 0,
          child: ExpansionTile(
            dense: true,
            initiallyExpanded: true,
            leading: const Icon(Icons.folder_outlined, size: 19),
            title: Text(
              entry.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              context.l10n.toolPages.requestCount(entry.value.length),
            ),
            children: [
              for (final item in entry.value)
                _savedRequestTile(
                  item,
                  closeAfterSelection: closeAfterSelection,
                ),
            ],
          ),
        ),
    ];
  }

  Future<void> _loadWorkspace() async {
    final values = await Future.wait<Object?>([
      _store.loadEnvironments(),
      _store.loadActiveEnvironmentId(),
      _readSavedRequests(),
    ]);
    if (!mounted) return;
    final environments = values[0] as List<ApiEnvironmentProfile>;
    final requested = values[1] as String?;
    setState(() {
      _environments = environments;
      _activeEnvironmentId = environments.any((item) => item.id == requested)
          ? requested
          : environments.isEmpty
          ? null
          : environments.first.id;
      _savedRequests = values[2] as List<ApiSavedRequestSummary>;
      _loading = false;
    });
  }

  Future<List<ApiSavedRequestSummary>> _readSavedRequests() async {
    final result = <ApiSavedRequestSummary>[];
    for (final workspace in const ['rest', 'websocket', 'sse', 'mqtt']) {
      final rows = await _store.loadList(
        ApiWorkspaceStore.templatesKey(workspace),
      );
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final target = switch (workspace) {
          'mqtt' => '${row['mqttHost'] ?? ''}:${row['mqttPort'] ?? ''}',
          _ => row['url']?.toString() ?? '',
        };
        result.add(
          ApiSavedRequestSummary(
            protocol: workspace,
            id: id,
            name: row['name']?.toString() ?? 'Request',
            method: switch (workspace) {
              'rest' => row['method']?.toString() ?? 'GET',
              'websocket' => 'WS',
              'sse' => 'SSE',
              _ => 'MQTT',
            },
            target: target,
            folder: row['folder']?.toString() ?? '',
            updatedAt: DateTime.tryParse(row['updatedAt']?.toString() ?? ''),
          ),
        );
      }
    }
    result.sort((a, b) {
      final left = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return result;
  }

  Future<void> _refreshSavedRequests() async {
    final requests = await _readSavedRequests();
    if (mounted) setState(() => _savedRequests = requests);
  }

  Future<void> _selectEnvironment(String? id) async {
    if (id == null) return;
    await _store.saveActiveEnvironmentId(id);
    if (!mounted) return;
    setState(() {
      _activeEnvironmentId = id;
      for (var protocol = 0; protocol < 4; protocol++) {
        _revisions[protocol] = (_revisions[protocol] ?? 0) + 1;
      }
    });
  }

  void _newRequest() => setState(() {
    _selectedTemplate[_protocol] = null;
    _revisions[_protocol] = (_revisions[_protocol] ?? 0) + 1;
  });

  Future<void> _showMobileCollections() async {
    // A Save operation and this tap can happen in the same frame. Reload from
    // the durable workspace before opening the sheet so it never renders a
    // stale collection snapshot.
    await _refreshSavedRequests();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: _collectionSidebar(
          closeAfterSelection: () async {
            await Navigator.of(sheetContext).maybePop();
          },
        ),
      ),
    );
  }

  Future<void> _manageEnvironments({ApiEnvironmentProfile? seed}) async {
    final current =
        seed ??
        _activeEnvironment ??
        const ApiEnvironmentProfile(
          id: 'default',
          name: 'Default',
          variables: [],
        );
    final name = TextEditingController(text: current.name);
    final rows = current.variables.map(_EnvironmentDraftRow.fromValue).toList();
    if (rows.isEmpty) rows.add(_EnvironmentDraftRow());
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LocalizedText('环境变量'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: context.tr('环境名称')),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < rows.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Checkbox(
                            value: rows[index].enabled,
                            onChanged: (value) => update(
                              () => rows[index].enabled = value ?? true,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: rows[index].name,
                              decoration: InputDecoration(
                                hintText: context.tr('变量名'),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: rows[index].value,
                              obscureText: rows[index].secret,
                              decoration: InputDecoration(
                                hintText: context.tr('当前值'),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: context.tr(
                              rows[index].secret ? '取消敏感标记' : '标记为敏感变量',
                            ),
                            onPressed: () => update(
                              () => rows[index].secret = !rows[index].secret,
                            ),
                            icon: Icon(
                              rows[index].secret
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                            ),
                          ),
                          IconButton(
                            tooltip: context.tr('删除'),
                            onPressed: rows.length == 1
                                ? null
                                : () => update(() {
                                    rows.removeAt(index).dispose();
                                  }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          update(() => rows.add(_EnvironmentDraftRow())),
                      icon: const Icon(Icons.add_rounded),
                      label: const LocalizedText('添加变量'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'new'),
              icon: const Icon(Icons.add_rounded),
              label: const LocalizedText('新建环境'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'duplicate'),
              icon: const Icon(Icons.copy_rounded),
              label: const LocalizedText('复制环境'),
            ),
            if (_environments.length > 1 &&
                _environments.any((item) => item.id == current.id))
              TextButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const LocalizedText('删除环境'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(context.l10n.common.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: const LocalizedText('保存'),
            ),
          ],
        ),
      ),
    );
    void disposeEditors() {
      name.dispose();
      for (final row in rows) {
        row.dispose();
      }
    }

    if (action == 'new' || action == 'duplicate') {
      final next = ApiEnvironmentProfile(
        id: 'environment-${DateTime.now().microsecondsSinceEpoch}',
        name: action == 'duplicate'
            ? '${current.name} Copy'
            : 'New environment',
        variables: action == 'duplicate' ? current.variables : const [],
      );
      disposeEditors();
      await _manageEnvironments(seed: next);
      return;
    }
    if (action == 'delete') {
      final environments = _environments
          .where((item) => item.id != current.id)
          .toList(growable: false);
      await _store.deleteSecrets('environment_${current.id}');
      await _store.saveEnvironments(environments);
      final active = environments.first.id;
      await _store.saveActiveEnvironmentId(active);
      if (mounted) {
        setState(() {
          _environments = environments;
          _activeEnvironmentId = active;
          for (var protocol = 0; protocol < 4; protocol++) {
            _revisions[protocol] = (_revisions[protocol] ?? 0) + 1;
          }
        });
      }
      disposeEditors();
      return;
    }
    if (action == 'save' && name.text.trim().isNotEmpty) {
      final value = ApiEnvironmentProfile(
        id: current.id,
        name: name.text.trim(),
        variables: rows
            .where((item) => item.name.text.trim().isNotEmpty)
            .map((item) => item.valueModel)
            .toList(),
      );
      final environments = [..._environments];
      final index = environments.indexWhere((item) => item.id == value.id);
      if (index < 0) {
        environments.add(value);
      } else {
        environments[index] = value;
      }
      await _store.saveEnvironments(environments);
      await _store.saveActiveEnvironmentId(value.id);
      if (mounted) {
        setState(() {
          _environments = environments;
          _activeEnvironmentId = value.id;
          for (var protocol = 0; protocol < 4; protocol++) {
            _revisions[protocol] = (_revisions[protocol] ?? 0) + 1;
          }
        });
      }
    }
    disposeEditors();
  }

  Future<void> _exportWorkspace() async {
    final dialogTitle = context.tr('导出 API 工作区');
    try {
      final bundle = await _store.exportWorkspace();
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(bundle)),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName:
            'protodeck_api_workspace_${DateTime.now().toIso8601String().substring(0, 10)}.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (path != null) _show('工作区已导出：$path');
    } on Object catch (error) {
      _show('导出失败：$error');
    }
  }

  Future<void> _importWorkspace() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final file = picked == null || picked.files.isEmpty
          ? null
          : picked.files.single;
      if (file == null) return;
      if (file.size > 4 * 1024 * 1024) {
        throw const FormatException('工作区文件不能超过 4 MiB');
      }
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FileSystemException('无法读取所选文件');
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('工作区根节点必须是对象');
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const LocalizedText('导入 API 工作区'),
          content: const LocalizedText(
            '导入文件不包含密码、Token、Cookie 等安全存储内容。合并会按 ID 更新同名模板；替换会清除现有非敏感集合。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: LocalizedText(dialogContext.l10n.common.cancel),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'replace'),
              child: const LocalizedText('替换'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'merge'),
              child: const LocalizedText('合并'),
            ),
          ],
        ),
      );
      if (action == null) return;
      await _store.importWorkspace(
        decoded.map((key, value) => MapEntry(key.toString(), value as Object?)),
        replace: action == 'replace',
      );
      await _loadWorkspace();
      if (mounted) {
        setState(() {
          for (var protocol = 0; protocol < 4; protocol++) {
            _revisions[protocol] = (_revisions[protocol] ?? 0) + 1;
          }
        });
      }
      _show('API 工作区已导入');
    } on Object catch (error) {
      _show('导入失败：$error');
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  static int _protocolIndex(String workspace) => switch (workspace) {
    'websocket' => 1,
    'sse' => 2,
    'mqtt' => 3,
    _ => 0,
  };

  static String _workspaceId(int protocol) => switch (protocol) {
    1 => 'websocket',
    2 => 'sse',
    3 => 'mqtt',
    _ => 'rest',
  };

  static IconData _protocolIcon(int protocol) => switch (protocol) {
    1 => Icons.swap_horiz_rounded,
    2 => Icons.stream_rounded,
    3 => Icons.sensors_rounded,
    _ => Icons.http_rounded,
  };

  static Color _methodColor(String method) => switch (method) {
    'POST' => const Color(0xFFE06B2E),
    'PUT' || 'PATCH' => const Color(0xFF8B63D9),
    'DELETE' => const Color(0xFFD94A5B),
    'WS' => const Color(0xFF367BF5),
    'SSE' => const Color(0xFF19A58C),
    'MQTT' => const Color(0xFF9B6BD8),
    _ => const Color(0xFF18A875),
  };
}

class _WorkbenchScroll extends StatelessWidget {
  const _WorkbenchScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width >= 980 ? 22 : 16,
      16,
      MediaQuery.sizeOf(context).width >= 980 ? 22 : 16,
      32,
    ),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: child,
        ),
      ),
    ],
  );
}

class _EnvironmentDraftRow {
  _EnvironmentDraftRow({
    String name = '',
    String value = '',
    this.enabled = true,
    this.secret = false,
  }) : name = TextEditingController(text: name),
       value = TextEditingController(text: value);

  factory _EnvironmentDraftRow.fromValue(ApiEnvironmentVariable value) =>
      _EnvironmentDraftRow(
        name: value.name,
        value: value.value,
        enabled: value.enabled,
        secret: value.secret,
      );

  final TextEditingController name;
  final TextEditingController value;
  bool enabled;
  bool secret;

  ApiEnvironmentVariable get valueModel => ApiEnvironmentVariable(
    name: name.text.trim(),
    value: value.text,
    enabled: enabled,
    secret: secret,
  );

  void dispose() {
    name.dispose();
    value.dispose();
  }
}
