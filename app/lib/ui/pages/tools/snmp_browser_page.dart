import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

import '../../../services/network_defaults_service.dart';
import '../../../services/snmp_service.dart';

class SnmpBrowserPage extends StatefulWidget {
  const SnmpBrowserPage({super.key});
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
  final _variables = <SnmpVariable>[];
  int _tab = 0;
  bool _running = false;
  bool _v3 = false;
  SnmpV3SecurityLevel _securityLevel = SnmpV3SecurityLevel.authPriv;
  SnmpV3AuthProtocol _authProtocol = SnmpV3AuthProtocol.sha256;
  String? _error;
  SnmpResponse? _response;

  @override
  void initState() {
    super.initState();
    _loadDefault();
  }

  @override
  void dispose() {
    _service.cancel();
    for (final controller in [
      _host,
      _port,
      _community,
      _v3User,
      _v3AuthPassword,
      _v3PrivacyPassword,
      _oids,
      _walkRoot,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('SNMP 浏览器')),
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
                : (value) => setState(() => _tab = value.first),
          ),
          const SizedBox(height: 14),
          if (_tab == 1)
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
                : (value) => setState(() => _v3 = value.first),
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
                  : (value) => setState(
                      () => _securityLevel = value ?? _securityLevel,
                    ),
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
                          : (value) => setState(
                              () => _authProtocol = value ?? _authProtocol,
                            ),
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

  Widget _results() => Card(
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
        ),
        const Divider(height: 1),
        for (final variable in _variables.take(1000))
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
          ),
        if (_variables.length > 1000)
          Padding(
            padding: const EdgeInsets.all(16),
            child: LocalizedText('已获取 ${_variables.length} 条，页面仅渲染前 1000 条。'),
          ),
      ],
    ),
  );

  Future<void> _loadDefault() async {
    final defaults = await NetworkDefaultsService().load();
    if (mounted && _host.text.isEmpty) {
      setState(() => _host.text = defaults.gateway ?? '192.168.1.1');
    }
  }

  Future<void> _run() async {
    final port = int.tryParse(_port.text);
    if (_host.text.trim().isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _error = '请输入有效设备地址和端口');
      return;
    }
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
                maxRows: 10000,
              )
            : _service.walk(
                host: _host.text,
                community: _community.text,
                rootOid: _walkRoot.text,
                port: port,
                maxRows: 10000,
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
              )
            : await _service.request(
                host: _host.text,
                community: _community.text,
                oids: oids,
                port: port,
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
}
