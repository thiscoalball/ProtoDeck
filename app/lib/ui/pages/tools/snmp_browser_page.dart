import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/network_defaults_service.dart';
import '../../../services/snmp_service.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';

class SnmpBrowserPage extends StatefulWidget {
  const SnmpBrowserPage({super.key, required this.appState});

  final AppState appState;
  @override
  State<SnmpBrowserPage> createState() => _SnmpBrowserPageState();
}

class _SnmpBrowserPageState extends State<SnmpBrowserPage> {
  final _service = SnmpService();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '161');
  final _community = TextEditingController(text: 'public');
  final _v3User = TextEditingController();
  final _v3AuthPassword = TextEditingController();
  final _v3PrivacyPassword = TextEditingController();
  final _oids = TextEditingController(
    text: '1.3.6.1.2.1.1.1.0\n1.3.6.1.2.1.1.5.0',
  );
  final _walkRoot = TextEditingController(text: '1.3.6.1.2.1.1');
  final _timeout = TextEditingController(text: '3000');
  final _retries = TextEditingController(text: '1');
  final _maxRepetitions = TextEditingController(text: '20');
  final _maxRows = TextEditingController(text: '2000');
  final _filter = TextEditingController();
  final _variables = <SnmpVariable>[];
  int _tab = 0;
  bool _running = false;
  bool _v3 = false;
  SnmpV3SecurityLevel _securityLevel = SnmpV3SecurityLevel.authPriv;
  SnmpV3AuthProtocol _authProtocol = SnmpV3AuthProtocol.sha256;
  String? _error;
  SnmpResponse? _response;
  SnmpOperation _operation = SnmpOperation.get;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    for (final controller in [
      _host,
      _port,
      _v3User,
      _oids,
      _walkRoot,
      _timeout,
      _retries,
      _maxRepetitions,
      _maxRows,
      _filter,
    ]) {
      controller.addListener(_saveDraft);
    }
    unawaited(_restoreDraftAndDefault());
  }

  @override
  void dispose() {
    _service.cancel();
    if (_draftLoaded) unawaited(_drafts.save('tool.snmp', _draftValue()));
    _drafts.dispose();
    for (final controller in [
      _host,
      _port,
      _community,
      _v3User,
      _v3AuthPassword,
      _v3PrivacyPassword,
      _oids,
      _walkRoot,
      _timeout,
      _retries,
      _maxRepetitions,
      _maxRows,
      _filter,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('SNMP 浏览器'),
      actions: [
        IconButton(
          onPressed: _running ? null : _restoreDefaults,
          tooltip: context.tr('恢复默认'),
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _connectionCard(),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.info_outline),
                label: LocalizedText('设备概览'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.search),
                label: LocalizedText('OID 查询'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.account_tree_outlined),
                label: LocalizedText('Walk'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: _running
                ? null
                : (value) {
                    setState(() => _tab = value.first);
                    _saveDraft();
                  },
          ),
          const SizedBox(height: 14),
          if (_tab == 1)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<SnmpOperation>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: SnmpOperation.get, label: Text('GET')),
                    ButtonSegment(
                      value: SnmpOperation.getNext,
                      label: Text('GET NEXT'),
                    ),
                    ButtonSegment(
                      value: SnmpOperation.getBulk,
                      label: Text('GET BULK'),
                    ),
                  ],
                  selected: {_operation},
                  onSelectionChanged: _running
                      ? null
                      : (value) {
                          setState(() => _operation = value.first);
                          _saveDraft();
                        },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _oids,
                  enabled: !_running,
                  minLines: 4,
                  maxLines: 9,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    label: LocalizedText('OID，每行一个'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _oidPresets.entries
                      .map(
                        (entry) => ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 16),
                          label: Text(entry.key),
                          onPressed: () => _appendOid(entry.value),
                        ),
                      )
                      .toList(),
                ),
              ],
            )
          else if (_tab == 2)
            TextField(
              controller: _walkRoot,
              enabled: !_running,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                label: LocalizedText('Walk 根 OID'),
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LocalizedText(
                  '查询 sysDescr、sysObjectID、sysUpTime、sysContact、sysName 与 sysLocation。',
                ),
              ),
            ),
          const SizedBox(height: 12),
          _requestOptions(),
          const SizedBox(height: 12),
          if (_running)
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const LocalizedText('停止任务'),
            )
          else
            FilledButton.icon(
              onPressed: _run,
              icon: Icon(
                _tab == 2
                    ? Icons.account_tree_outlined
                    : Icons.play_arrow_rounded,
              ),
              label: LocalizedText(_tab == 2 ? '开始 Walk' : '发送查询'),
            ),
          if (_running) const LinearProgressIndicator(),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: LocalizedText(error),
              ),
            ),
          ],
          if (_variables.isNotEmpty) ...[
            const SizedBox(height: 18),
            _results(),
          ],
        ],
      ),
    ),
  );

  Widget _connectionCard() => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _host,
                  enabled: !_running,
                  decoration: const InputDecoration(
                    label: LocalizedText('设备地址'),
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _port,
                  enabled: !_running,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(label: LocalizedText('端口')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: LocalizedText('SNMP v2c')),
              ButtonSegment(value: true, label: LocalizedText('SNMP v3')),
            ],
            selected: {_v3},
            onSelectionChanged: _running
                ? null
                : (value) {
                    setState(() => _v3 = value.first);
                    _saveDraft();
                  },
          ),
          const SizedBox(height: 10),
          if (!_v3)
            TextField(
              controller: _community,
              enabled: !_running,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'SNMP v2c Community',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            )
          else ...[
            TextField(
              controller: _v3User,
              enabled: !_running,
              decoration: const InputDecoration(
                label: LocalizedText('USM 用户名'),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<SnmpV3SecurityLevel>(
              initialValue: _securityLevel,
              decoration: const InputDecoration(label: LocalizedText('安全等级')),
              items: SnmpV3SecurityLevel.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: LocalizedText(value.name),
                    ),
                  )
                  .toList(),
              onChanged: _running
                  ? null
                  : (value) {
                      setState(() => _securityLevel = value ?? _securityLevel);
                      _saveDraft();
                    },
            ),
            if (_securityLevel != SnmpV3SecurityLevel.noAuthNoPriv) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 132,
                    child: DropdownButtonFormField<SnmpV3AuthProtocol>(
                      initialValue: _authProtocol,
                      decoration: const InputDecoration(
                        label: LocalizedText('认证算法'),
                      ),
                      items: SnmpV3AuthProtocol.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: LocalizedText(value.name.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: _running
                          ? null
                          : (value) {
                              setState(
                                () => _authProtocol = value ?? _authProtocol,
                              );
                              _saveDraft();
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _v3AuthPassword,
                      enabled: !_running,
                      obscureText: true,
                      decoration: const InputDecoration(
                        label: LocalizedText('认证密码'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_securityLevel == SnmpV3SecurityLevel.authPriv) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _v3PrivacyPassword,
                enabled: !_running,
                obscureText: true,
                decoration: const InputDecoration(
                  label: LocalizedText('AES-128 隐私密码'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 8),
          LocalizedText(
            '凭据只保留在当前页面内。v3 支持 Engine Discovery、MD5/SHA-1/SHA-256 与 AES-128；SNMP SET 未启用。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _requestOptions() => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      leading: const Icon(Icons.tune_rounded),
      title: const LocalizedText('请求参数'),
      subtitle: LocalizedText(
        '${_timeout.text} ms · ${context.tr('重试')} ${_retries.text}${_tab == 2 ? ' · ${context.tr('最多')} ${_maxRows.text}' : ''}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Row(
          children: [
            Expanded(child: _numberField(_timeout, '超时 ms')),
            const SizedBox(width: 10),
            Expanded(child: _numberField(_retries, '重试次数')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _numberField(_maxRepetitions, 'Bulk 每批数量')),
            const SizedBox(width: 10),
            Expanded(child: _numberField(_maxRows, 'Walk 最大行数')),
          ],
        ),
      ],
    ),
  );

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        enabled: !_running,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(label: LocalizedText(label)),
      );

  Widget _results() {
    final query = _filter.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _variables
        : _variables
              .where(
                (item) =>
                    item.oid.toLowerCase().contains(query) ||
                    item.type.toLowerCase().contains(query) ||
                    item.value.toLowerCase().contains(query) ||
                    (commonSnmpOids[item.oid] ?? '').toLowerCase().contains(
                      query,
                    ),
              )
              .toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            title: LocalizedText(
              '返回 ${_variables.length} 个变量',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: _response == null
                ? null
                : LocalizedText(
                    '${_response!.address} · ${_response!.elapsed.inMilliseconds} ms',
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _variables.isEmpty ? null : _copyAll,
                  icon: const Icon(Icons.copy_all_outlined),
                  tooltip: context.tr('复制全部'),
                ),
                IconButton(
                  onPressed: _variables.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.download_outlined),
                  tooltip: context.tr('导出 CSV'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _filter,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_alt_outlined),
                label: LocalizedText('筛选 OID、名称、类型或值'),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Divider(height: 1),
          for (final variable in visible.take(1000))
            ListTile(
              title: SelectableText(
                '${commonSnmpOids[variable.oid] ?? variable.oid}  [${variable.type}]',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: SelectableText(
                variable.value,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              trailing: IconButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: '${variable.oid}\t${variable.value}'),
                ),
                tooltip: context.tr('复制 OID 与值'),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
          if (visible.length > 1000)
            Padding(
              padding: const EdgeInsets.all(16),
              child: LocalizedText('已获取 ${_variables.length} 条，页面仅渲染前 1000 条。'),
            ),
        ],
      ),
    );
  }

  Future<void> _loadDefault() async {
    final defaults = await NetworkDefaultsService().load();
    if (mounted && _host.text.isEmpty) {
      setState(() => _host.text = defaults.gateway ?? '192.168.1.1');
    }
  }

  Map<String, Object?> _draftValue() => {
    'host': _host.text,
    'port': _port.text,
    'v3': _v3,
    'v3User': _v3User.text,
    'tab': _tab,
    'securityLevel': _securityLevel.name,
    'authProtocol': _authProtocol.name,
    'oids': _oids.text,
    'walkRoot': _walkRoot.text,
    'operation': _operation.name,
    'timeout': _timeout.text,
    'retries': _retries.text,
    'maxRepetitions': _maxRepetitions.text,
    'maxRows': _maxRows.text,
    'filter': _filter.text,
    // Community and SNMPv3 passwords are credentials and never normal drafts.
  };

  Future<void> _restoreDraftAndDefault() async {
    final draft = await _drafts.load('tool.snmp');
    if (!mounted) return;
    if (draft != null) {
      _host.text = draft.payload['host']?.toString() ?? '';
      _port.text = draft.payload['port']?.toString() ?? _port.text;
      _v3 = draft.payload['v3'] == true;
      _v3User.text = draft.payload['v3User']?.toString() ?? '';
      _tab = (draft.payload['tab'] as num?)?.toInt().clamp(0, 2) ?? _tab;
      _securityLevel = SnmpV3SecurityLevel.values.firstWhere(
        (value) => value.name == draft.payload['securityLevel'],
        orElse: () => _securityLevel,
      );
      _authProtocol = SnmpV3AuthProtocol.values.firstWhere(
        (value) => value.name == draft.payload['authProtocol'],
        orElse: () => _authProtocol,
      );
      _oids.text = draft.payload['oids']?.toString() ?? _oids.text;
      _walkRoot.text = draft.payload['walkRoot']?.toString() ?? _walkRoot.text;
      _operation = SnmpOperation.values.firstWhere(
        (value) => value.name == draft.payload['operation'],
        orElse: () => _operation,
      );
      _timeout.text = draft.payload['timeout']?.toString() ?? _timeout.text;
      _retries.text = draft.payload['retries']?.toString() ?? _retries.text;
      _maxRepetitions.text =
          draft.payload['maxRepetitions']?.toString() ?? _maxRepetitions.text;
      _maxRows.text = draft.payload['maxRows']?.toString() ?? _maxRows.text;
      _filter.text = draft.payload['filter']?.toString() ?? '';
    }
    _draftLoaded = true;
    await _loadDefault();
    if (mounted) setState(() {});
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.snmp', _draftValue());
  }

  Future<void> _exportCsv() async {
    try {
      String safe(String value) =>
          value.trimLeft().startsWith(RegExp(r'[=+\-@]')) ? "'$value" : value;
      final csvText = Csv().encode([
        const ['OID', 'Name', 'Type', 'Value'],
        for (final variable in _variables)
          [
            safe(variable.oid),
            safe(commonSnmpOids[variable.oid] ?? ''),
            safe(variable.type),
            safe(variable.value),
          ],
      ]);
      final bytes = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(csvText),
      ]);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.tr('导出 SNMP 结果'),
        fileName: 'protodeck_snmp_${DateTime.now().millisecondsSinceEpoch}.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
      );
      if (path != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('已保存：$path')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText('导出失败：$error')));
      }
    }
  }

  Future<void> _run() async {
    final port = int.tryParse(_port.text);
    final timeoutMs = int.tryParse(_timeout.text);
    final retries = int.tryParse(_retries.text);
    final maxRepetitions = int.tryParse(_maxRepetitions.text);
    final maxRows = int.tryParse(_maxRows.text);
    if (_host.text.trim().isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _error = '请输入有效设备地址和端口');
      return;
    }
    if (timeoutMs == null ||
        timeoutMs < 100 ||
        timeoutMs > 60000 ||
        retries == null ||
        retries < 0 ||
        retries > 10 ||
        maxRepetitions == null ||
        maxRepetitions < 1 ||
        maxRepetitions > 100 ||
        maxRows == null ||
        maxRows < 1 ||
        maxRows > 100000) {
      setState(() => _error = '请求参数超出有效范围');
      return;
    }
    final timeout = Duration(milliseconds: timeoutMs);
    setState(() {
      _running = true;
      _error = null;
      _variables.clear();
      _response = null;
    });
    try {
      if (_tab == 2) {
        final stream = _v3
            ? _service.walkV3(
                host: _host.text,
                credentials: _credentials(),
                rootOid: _walkRoot.text,
                port: port,
                maxRows: maxRows,
                maxRepetitions: maxRepetitions,
                timeout: timeout,
              )
            : _service.walk(
                host: _host.text,
                community: _community.text,
                rootOid: _walkRoot.text,
                port: port,
                maxRows: maxRows,
                maxRepetitions: maxRepetitions,
                timeout: timeout,
              );
        await for (final variables in stream) {
          if (!mounted || !_running) break;
          setState(() {
            _variables
              ..clear()
              ..addAll(variables);
          });
        }
      } else {
        final oids = _tab == 0
            ? commonSnmpOids.keys.where((oid) => oid.endsWith('.0')).toList()
            : _oids.text
                  .split(RegExp(r'[\r\n,]+'))
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList();
        final response = _v3
            ? await _service.requestV3(
                host: _host.text,
                credentials: _credentials(),
                oids: oids,
                port: port,
                operation: _operation,
                maxRepetitions: maxRepetitions,
                timeout: timeout,
                retries: retries,
              )
            : await _service.request(
                host: _host.text,
                community: _community.text,
                oids: oids,
                port: port,
                operation: _operation,
                maxRepetitions: maxRepetitions,
                timeout: timeout,
                retries: retries,
              );
        if (mounted) {
          setState(() {
            _response = response;
            _variables.addAll(response.variables);
          });
        }
      }
    } on SnmpCancelled {
      // User stopped the session.
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  SnmpV3Credentials _credentials() => SnmpV3Credentials(
    username: _v3User.text.trim(),
    securityLevel: _securityLevel,
    authProtocol: _authProtocol,
    authPassword: _v3AuthPassword.text,
    privacyPassword: _v3PrivacyPassword.text,
  );

  void _stop() {
    _service.cancel();
    setState(() => _running = false);
  }

  void _appendOid(String oid) {
    final values = _oids.text
        .split(RegExp(r'[\r\n,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    values.add(oid);
    _oids.text = values.join('\n');
  }

  Future<void> _copyAll() => Clipboard.setData(
    ClipboardData(
      text: _variables
          .map((item) => '${item.oid}\t${item.type}\t${item.value}')
          .join('\n'),
    ),
  );

  Future<void> _restoreDefaults() async {
    await _drafts.reset('tool.snmp');
    if (!mounted) return;
    setState(() {
      _port.text = '161';
      _v3 = false;
      _v3User.clear();
      _tab = 0;
      _operation = SnmpOperation.get;
      _oids.text = '1.3.6.1.2.1.1.1.0\n1.3.6.1.2.1.1.5.0';
      _walkRoot.text = '1.3.6.1.2.1.1';
      _timeout.text = '3000';
      _retries.text = '1';
      _maxRepetitions.text = '20';
      _maxRows.text = '2000';
      _filter.clear();
      _variables.clear();
      _error = null;
    });
    await _loadDefault();
  }
}

const _oidPresets = <String, String>{
  'System': '1.3.6.1.2.1.1',
  'Interfaces': '1.3.6.1.2.1.2.2',
  'IP': '1.3.6.1.2.1.4',
  'TCP': '1.3.6.1.2.1.6',
  'UDP': '1.3.6.1.2.1.7',
  'LLDP': '1.0.8802.1.1.2',
};
