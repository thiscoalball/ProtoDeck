import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/network_configuration.dart';
import '../../../services/download_destination_service.dart';
import '../../../services/network_configuration_service.dart';
import '../../../state/app_state.dart';

class NetworkConfigurationPage extends StatefulWidget {
  const NetworkConfigurationPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<NetworkConfigurationPage> createState() =>
      _NetworkConfigurationPageState();
}

class _NetworkConfigurationPageState extends State<NetworkConfigurationPage> {
  final _configuration = NetworkConfigurationService();
  late final _templates = NetworkConfigurationTemplateRepository(
    widget.appState.database,
  );
  late final _restorePoints = NetworkConfigurationRestorePointRepository(
    widget.appState.database,
  );

  final _name = TextEditingController();
  final _address = TextEditingController();
  final _prefix = TextEditingController(text: '24');
  final _gateway = TextEditingController();
  final _dns = TextEditingController();
  final _metric = TextEditingController();
  final _routes = TextEditingController();
  final _templateSearch = TextEditingController();

  List<NetworkInterfaceConfiguration> _interfaces = const [];
  List<NetworkConfigurationTemplate> _saved = const [];
  NetworkConfigurationRestorePoint? _restorePoint;
  NetworkConfigurationApplyResult? _result;
  NetworkConnectivityReport? _connectivity;
  String? _interfaceName;
  String? _editingTemplateId;
  NetworkAddressMode _mode = NetworkAddressMode.dhcp;
  NetworkInterfaceMatchMode _matchMode = NetworkInterfaceMatchMode.exactName;
  Set<NetworkDiagnosticKind> _diagnostics = NetworkDiagnosticKind.values
      .toSet();
  bool _loading = true;
  bool _applying = false;
  bool _diagnosing = false;
  bool _restoring = false;
  String _search = '';
  String? _error;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  NetworkInterfaceConfiguration? get _selectedInterface => _interfaces
      .where((value) => value.interfaceName == _interfaceName)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _templateSearch.addListener(() {
      if (mounted) setState(() => _search = _templateSearch.text.trim());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _prefix.dispose();
    _gateway.dispose();
    _dns.dispose();
    _metric.dispose();
    _routes.dispose();
    _templateSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _configuration.inspector.listInterfaces(),
        _templates.load(),
        _restorePoints.load(),
      ]);
      if (!mounted) return;
      final interfaces = values[0] as List<NetworkInterfaceConfiguration>;
      final selected =
          interfaces
              .where((value) => value.interfaceName == _interfaceName)
              .firstOrNull ??
          interfaces.where((value) => value.isDefault).firstOrNull ??
          interfaces.where((value) => value.connected).firstOrNull ??
          interfaces.firstOrNull;
      setState(() {
        _interfaces = interfaces;
        _saved = values[1] as List<NetworkConfigurationTemplate>;
        _restorePoint = values[2] as NetworkConfigurationRestorePoint?;
        _interfaceName = selected?.interfaceName;
        if (_editingTemplateId == null && selected != null) {
          _seedFromInterface(selected, force: false);
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshInterfaces() async {
    try {
      final values = await _configuration.inspector.listInterfaces();
      if (!mounted) return;
      setState(() => _interfaces = values);
    } on Object catch (error) {
      _showError(error);
    }
  }

  void _seedFromInterface(
    NetworkInterfaceConfiguration value, {
    required bool force,
  }) {
    if (force || _address.text.isEmpty) {
      _address.text = value.address ?? '';
      _prefix.text = '${value.prefixLength ?? 24}';
    }
    if (force || _gateway.text.isEmpty) _gateway.text = value.gateway ?? '';
    if (force || _dns.text.isEmpty) _dns.text = value.dnsServers.join(', ');
    if (force || _metric.text.isEmpty) {
      _metric.text = value.interfaceMetric?.toString() ?? '';
    }
    if (force || _routes.text.isEmpty) {
      _routes.text = value.routes
          .map(
            (route) =>
                '${route.destination}, ${route.gateway}, ${route.metric}',
          )
          .join('\n');
    }
    if (force) _mode = value.mode;
  }

  void _selectInterface(String? name) {
    final selected = _interfaces
        .where((value) => value.interfaceName == name)
        .firstOrNull;
    setState(() {
      _interfaceName = name;
      _editingTemplateId = null;
      _result = null;
      _connectivity = null;
      if (selected != null) _seedFromInterface(selected, force: true);
    });
  }

  NetworkConfigurationTemplate _buildTemplate({String? id}) {
    final selected = _selectedInterface;
    final template = NetworkConfigurationTemplate(
      id:
          id ??
          _editingTemplateId ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty
          ? '${_interfaceName ?? ''} ${_mode == NetworkAddressMode.dhcp ? 'DHCP' : 'Static'}'
          : _name.text.trim(),
      interfaceName: _interfaceName ?? '',
      interfaceMatchMode: _matchMode,
      interfaceMacAddress: selected?.macAddress,
      interfaceTransport: selected?.transport,
      mode: _mode,
      address: _mode == NetworkAddressMode.staticIpv4
          ? _address.text.trim()
          : null,
      prefixLength: int.tryParse(_prefix.text.trim()) ?? 24,
      gateway:
          _mode == NetworkAddressMode.staticIpv4 &&
              _gateway.text.trim().isNotEmpty
          ? _gateway.text.trim()
          : null,
      dnsServers: _mode == NetworkAddressMode.staticIpv4
          ? _splitValues(_dns.text)
          : const [],
      interfaceMetric: int.tryParse(_metric.text.trim()),
      staticRoutes: _parseRoutes(_routes.text),
      diagnostics: _diagnostics,
      updatedAt: DateTime.now(),
    );
    template.validate();
    return template;
  }

  List<NetworkStaticRoute> _parseRoutes(String source) {
    final result = <NetworkStaticRoute>[];
    for (final (index, raw) in source.split(RegExp(r'\r?\n')).indexed) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'[,;\s]+'));
      if (parts.length < 2 || parts.length > 3) {
        throw FormatException('静态路由第 ${index + 1} 行格式应为：目标CIDR, 网关, Metric');
      }
      final route = NetworkStaticRoute(
        destination: parts[0],
        gateway: parts[1],
        metric: parts.length == 3 ? int.tryParse(parts[2]) ?? 100 : 100,
      );
      route.validate();
      result.add(route);
    }
    return result;
  }

  Future<void> _saveTemplate() async {
    try {
      final template = _buildTemplate();
      await _templates.save(template);
      final saved = await _templates.load();
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _editingTemplateId = template.id;
      });
      _show('网络配置模板已保存');
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _apply({NetworkConfigurationTemplate? source}) async {
    if (_applying || _restoring) return;
    try {
      var template = source ?? _buildTemplate();
      final resolved = _configuration.inspector.resolveInterface(
        template,
        _interfaces,
      );
      if (resolved == null) {
        throw StateError('没有找到与模板匹配的网卡');
      }
      template = template.copyWith(interfaceName: resolved.interfaceName);
      if (template.mode == NetworkAddressMode.staticIpv4) {
        final conflict = await _configuration.inspector.checkIpv4Conflict(
          interfaceName: template.interfaceName,
          address: template.address!,
        );
        if (!mounted) return;
        if (!await _confirmConflict(conflict)) return;
      }
      final differences = _configuration.inspector.differences(
        resolved,
        template,
      );
      if (!mounted || !await _confirmApply(template, differences)) return;
      setState(() {
        _applying = true;
        _result = null;
        _connectivity = null;
      });
      final point = await _configuration.inspector.captureRestorePoint(
        template.interfaceName,
      );
      await _restorePoints.save(point);
      if (mounted) setState(() => _restorePoint = point);
      final result = await _configuration.apply(template, restorePoint: point);
      if (!mounted) return;
      setState(() => _result = result);
      await _refreshInterfaces();
      if (result.success) await _runDiagnostics(template: template);
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<bool> _confirmConflict(IpConflictCheckResult result) async {
    if (result.state == IpConflictState.clear) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              result.state == IpConflictState.suspected
                  ? Icons.warning_amber_rounded
                  : Icons.help_outline_rounded,
              color: result.state == IpConflictState.suspected
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.tertiary,
            ),
            title: LocalizedText(
              result.state == IpConflictState.suspected
                  ? '地址可能已被占用'
                  : '无法确定地址是否空闲',
            ),
            content: LocalizedText(
              [
                result.message,
                if (result.macAddress != null) 'MAC: ${result.macAddress}',
                '这项检测只提供风险提示，仍可继续应用。',
              ].join('\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const LocalizedText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const LocalizedText('仍然继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmApply(
    NetworkConfigurationTemplate template,
    List<NetworkConfigurationDifference> differences,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const LocalizedText('确认网络配置变更'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText('目标网卡：${template.interfaceName}'),
                const SizedBox(height: 12),
                for (final item in differences)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 105, child: LocalizedText(item.label)),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: item.before,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const TextSpan(text: '  →  '),
                                TextSpan(
                                  text: item.after,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: item.changed
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const LocalizedText('配置写入失败时才会自动恢复。网关、DNS 或互联网暂时不可用只显示警告。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_rounded),
              label: const LocalizedText('应用配置'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _runDiagnostics({NetworkConfigurationTemplate? template}) async {
    if (_diagnosing) return;
    try {
      final target = template ?? _buildTemplate();
      setState(() => _diagnosing = true);
      final report = await _configuration.inspector.runDiagnostics(
        template: target,
      );
      if (mounted) setState(() => _connectivity = report);
      await _refreshInterfaces();
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  Future<void> _restoreLast() async {
    final point = _restorePoint;
    if (point == null || _restoring) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('恢复上一次配置'),
        content: LocalizedText(
          '将 ${point.interfaceName} 恢复到 ${_formatTime(point.capturedAt)} 保存的状态。该操作也会短暂中断连接。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('确认恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      setState(() => _restoring = true);
      final result = await _configuration.restore(point);
      if (!mounted) return;
      setState(() {
        _result = result;
        _connectivity = null;
      });
      if (result.success) await _load();
    } on Object catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _loadTemplate(NetworkConfigurationTemplate template) {
    final resolved = _configuration.inspector.resolveInterface(
      template,
      _interfaces,
    );
    setState(() {
      _editingTemplateId = template.id;
      _name.text = template.name;
      _interfaceName = resolved?.interfaceName ?? template.interfaceName;
      _matchMode = template.interfaceMatchMode;
      _mode = template.mode;
      _address.text = template.address ?? '';
      _prefix.text = '${template.prefixLength}';
      _gateway.text = template.gateway ?? '';
      _dns.text = template.dnsServers.join(', ');
      _metric.text = template.interfaceMetric?.toString() ?? '';
      _routes.text = template.staticRoutes
          .map(
            (route) =>
                '${route.destination}, ${route.gateway}, ${route.metric}',
          )
          .join('\n');
      _diagnostics = {...template.diagnostics};
      _result = null;
      _connectivity = null;
    });
  }

  Future<void> _copyTemplate(NetworkConfigurationTemplate template) async {
    final copy = template.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '${template.name} Copy',
      updatedAt: DateTime.now(),
    );
    await _templates.save(copy);
    if (mounted) setState(() => _saved = [..._saved, copy]);
  }

  Future<void> _renameTemplate(NetworkConfigurationTemplate template) async {
    final controller = TextEditingController(text: template.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('重命名模板'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(label: LocalizedText('模板名称')),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const LocalizedText('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await _templates.save(
      template.copyWith(name: value, updatedAt: DateTime.now()),
    );
    final saved = await _templates.load();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _deleteTemplate(NetworkConfigurationTemplate template) async {
    await _templates.delete(template.id);
    final saved = await _templates.load();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _exportTemplates() async {
    try {
      final dialogTitle = context.tr('导出网络配置模板');
      final source = await _templates.exportJson();
      final bytes = Uint8List.fromList(utf8.encode(source));
      final saved = await DownloadDestinationService.saveBytes(
        bytes: bytes,
        dialogTitle: dialogTitle,
        fileName: 'protodeck_network_templates.json',
        allowedExtensions: const ['json'],
        mimeType: 'application/json',
      );
      if (saved == null) return;
      if (!mounted) return;
      _show('模板已导出：${saved.displayLocation}');
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _importTemplates() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        lockParentWindow: true,
      );
      final file = picked?.files.singleOrNull;
      if (file == null) return;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FileSystemException('无法读取模板文件');
      final count = await _templates.importJson(utf8.decode(bytes));
      final saved = await _templates.load();
      if (mounted) setState(() => _saved = saved);
      _show('已导入 $count 个网络配置模板');
    } on Object catch (error) {
      _showError(error);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: LocalizedText(message)));
  }

  void _showError(Object error) => _show('$error');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('网络地址配置'),
      actions: [
        if (_restorePoint != null)
          IconButton(
            tooltip: context.tr('恢复上一次配置'),
            onPressed: _applying || _restoring ? null : _restoreLast,
            icon: _restoring
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.settings_backup_restore_rounded),
          ),
        IconButton(
          tooltip: context.tr('刷新'),
          onPressed: _loading || _applying ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: !_isDesktop
        ? const _UnsupportedConfiguration()
        : _loading && _interfaces.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              if (_error != null) _errorCard(),
              _adapterCard(),
              const SizedBox(height: 14),
              _editorCard(),
              if (_result != null) ...[
                const SizedBox(height: 14),
                _configurationResultCard(_result!),
              ],
              if (_connectivity != null || _diagnosing) ...[
                const SizedBox(height: 14),
                _connectivityCard(),
              ],
              const SizedBox(height: 22),
              _templatesSection(),
            ],
          ),
  );

  Widget _errorCard() => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.error_outline_rounded),
      title: const LocalizedText('读取网络接口失败'),
      subtitle: SelectableText(_error!),
    ),
  );

  Widget _adapterCard() {
    final selected = _selectedInterface;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LocalizedText(
                    '目标网卡',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (selected?.isDefault == true)
                  const Chip(
                    avatar: Icon(Icons.route_rounded, size: 17),
                    label: LocalizedText('默认路由'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_interfaceName),
              initialValue:
                  _interfaces.any(
                    (value) => value.interfaceName == _interfaceName,
                  )
                  ? _interfaceName
                  : null,
              decoration: const InputDecoration(label: LocalizedText('网络接口')),
              items: [
                for (final value in _interfaces)
                  DropdownMenuItem(
                    value: value.interfaceName,
                    child: Text(
                      '${value.interfaceName}  ·  ${_transportName(value.transport)}${value.isDefault ? '  ·  默认' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _applying ? null : _selectInterface,
            ),
            if (selected != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 10,
                children: [
                  _detail('描述', selected.description),
                  _detail('状态', selected.status),
                  _detail('MAC', selected.macAddress ?? '未提供'),
                  _detail('链路速率', selected.linkSpeed ?? '未提供'),
                  _detail(
                    '当前 IPv4',
                    selected.address == null
                        ? '无'
                        : '${selected.address}/${selected.prefixLength}',
                  ),
                  _detail('网关', selected.gateway ?? '无'),
                  _detail(
                    'DNS',
                    selected.dnsServers.isEmpty
                        ? '自动/无'
                        : selected.dnsServers.join(', '),
                  ),
                  _detail(
                    'Metric',
                    selected.interfaceMetric?.toString() ?? '自动',
                  ),
                  if (selected.profileName != null)
                    _detail('Profile', selected.profileName!),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );

  Widget _editorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            '配置编辑',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const LocalizedText('应用前会显示参数差异并保存独立恢复点。联网失败不会自动回滚。'),
          const SizedBox(height: 18),
          SegmentedButton<NetworkAddressMode>(
            segments: const [
              ButtonSegment(
                value: NetworkAddressMode.dhcp,
                icon: Icon(Icons.autorenew_rounded),
                label: LocalizedText('自动获取（DHCP）'),
              ),
              ButtonSegment(
                value: NetworkAddressMode.staticIpv4,
                icon: Icon(Icons.pin_outlined),
                label: LocalizedText('静态 IPv4'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _applying
                ? null
                : (value) => setState(() => _mode = value.single),
          ),
          if (_mode == NetworkAddressMode.staticIpv4) ...[
            const SizedBox(height: 16),
            _addressFields(),
          ],
          const SizedBox(height: 14),
          _advancedFields(),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !_applying,
            decoration: const InputDecoration(
              label: LocalizedText('模板名称（可选）'),
              hintText: 'Office LAN',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<NetworkInterfaceMatchMode>(
            key: ValueKey(_matchMode),
            initialValue: _matchMode,
            decoration: const InputDecoration(label: LocalizedText('模板网卡匹配方式')),
            items: const [
              DropdownMenuItem(
                value: NetworkInterfaceMatchMode.exactName,
                child: LocalizedText('按接口名称精确匹配'),
              ),
              DropdownMenuItem(
                value: NetworkInterfaceMatchMode.macAddress,
                child: LocalizedText('优先按 MAC 地址匹配'),
              ),
              DropdownMenuItem(
                value: NetworkInterfaceMatchMode.defaultTransport,
                child: LocalizedText('匹配同类型默认网卡'),
              ),
            ],
            onChanged: _applying
                ? null
                : (value) => setState(() => _matchMode = value ?? _matchMode),
          ),
          const SizedBox(height: 16),
          const LocalizedText('应用后独立检测'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final kind in NetworkDiagnosticKind.values)
                FilterChip(
                  selected: _diagnostics.contains(kind),
                  label: LocalizedText(_diagnosticName(kind)),
                  onSelected: _applying
                      ? null
                      : (selected) => setState(() {
                          if (selected) {
                            _diagnostics.add(kind);
                          } else {
                            _diagnostics.remove(kind);
                          }
                        }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _applying ? null : _saveTemplate,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const LocalizedText('保存为模板'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _applying || _interfaces.isEmpty ? null : _apply,
                  icon: _applying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.compare_arrows_rounded),
                  label: LocalizedText(_applying ? '正在应用' : '预览并应用'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _addressFields() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 560;
      final address = TextField(
        controller: _address,
        enabled: !_applying,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          label: LocalizedText('IPv4 地址'),
          hintText: '192.0.2.10',
        ),
      );
      final prefix = TextField(
        controller: _prefix,
        enabled: !_applying,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(label: LocalizedText('前缀长度')),
      );
      return Column(
        children: [
          if (wide)
            Row(
              children: [
                Expanded(flex: 3, child: address),
                const SizedBox(width: 10),
                Expanded(child: prefix),
              ],
            )
          else ...[
            address,
            const SizedBox(height: 12),
            prefix,
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _gateway,
            enabled: !_applying,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              label: LocalizedText('默认网关（可选）'),
              helper: LocalizedText('纯局域网或设备直连可留空'),
              hintText: '192.0.2.1',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dns,
            enabled: !_applying,
            decoration: const InputDecoration(
              label: LocalizedText('DNS 服务器'),
              helperText: 'Separate multiple addresses with commas',
              hintText: '223.5.5.5, 1.1.1.1',
            ),
          ),
        ],
      );
    },
  );

  Widget _advancedFields() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: EdgeInsets.zero,
    title: const LocalizedText('高级路由与 Metric'),
    subtitle: const LocalizedText('可选；留空时使用系统默认值'),
    children: [
      TextField(
        controller: _metric,
        enabled: !_applying,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          label: LocalizedText('接口 Metric（可选）'),
          hintText: '25',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _routes,
        enabled: !_applying,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          label: LocalizedText('静态路由（每行一条）'),
          helper: LocalizedText('格式：目标CIDR, 网关, Metric'),
          hintText: '192.168.20.0/24, 192.168.8.1, 100',
        ),
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _configurationResultCard(NetworkConfigurationApplyResult result) {
    final color = result.success
        ? const Color(0xFF2FA778)
        : const Color(0xFFD95562);
    return Card(
      color: color.withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.success
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LocalizedText(
                    result.success ? 'IP 配置已写入' : 'IP 配置写入失败',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LocalizedText(result.message),
            if (result.requiresElevation)
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: LocalizedText('需要管理员权限或有效的 Polkit 授权。'),
              ),
            if (result.rollbackAttempted)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: LocalizedText(
                  result.rollbackSucceeded
                      ? '写入失败，已自动恢复原配置。'
                      : '写入失败且自动恢复未完成，请手动检查系统网络设置。',
                ),
              ),
            if (result.verification.isNotEmpty) ...[
              const Divider(height: 24),
              const LocalizedText('实际配置核对'),
              const SizedBox(height: 6),
              for (final item in result.verification)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.matches
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    color: item.matches
                        ? const Color(0xFF2FA778)
                        : const Color(0xFFE39A36),
                  ),
                  title: LocalizedText(item.label),
                  subtitle: Text(
                    '${context.tr('期望')}: ${context.tr(item.expected)}\n'
                    '${context.tr('实际')}: ${context.tr(item.actual)}'
                    '${item.detail == null ? '' : '\n${context.tr(item.detail!)}'}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectivityCard() {
    final report = _connectivity;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        '独立联网检测',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (report != null)
                        LocalizedText(
                          '上次检测：${_formatTime(report.checkedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _diagnosing || _applying ? null : _runDiagnostics,
                  icon: _diagnosing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: LocalizedText(_diagnosing ? '检测中' : '重新检测'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const LocalizedText('网关、DNS 或互联网失败不会回滚 IP 配置；上级设备就绪后可随时重新检测。'),
            if (report != null) ...[
              const SizedBox(height: 10),
              for (final check in report.checks)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _checkIcon(check.state),
                    color: _checkColor(check.state),
                  ),
                  title: LocalizedText(check.title),
                  subtitle: LocalizedText(
                    '${check.detail}${check.latencyMs == null ? '' : ' · ${check.latencyMs!.toStringAsFixed(0)} ms'}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _templatesSection() {
    final normalized = _search.toLowerCase();
    final shown = _saved
        .where((value) {
          if (normalized.isEmpty) return true;
          return '${value.name} ${value.interfaceName} ${value.address ?? ''}'
              .toLowerCase()
              .contains(normalized);
        })
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LocalizedText(
                '配置模板',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: context.tr('导入模板'),
              onPressed: _importTemplates,
              icon: const Icon(Icons.file_upload_outlined),
            ),
            IconButton(
              tooltip: context.tr('导出模板'),
              onPressed: _saved.isEmpty ? null : _exportTemplates,
              icon: const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _templateSearch,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            label: LocalizedText('搜索模板'),
          ),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: LocalizedText('尚未保存网络配置模板'),
            ),
          )
        else
          for (final template in shown)
            Card(
              child: ListTile(
                leading: Icon(
                  template.mode == NetworkAddressMode.dhcp
                      ? Icons.autorenew_rounded
                      : Icons.pin_outlined,
                ),
                title: LocalizedText(template.name),
                subtitle: Text(
                  '${template.interfaceName} · ${template.mode == NetworkAddressMode.dhcp ? 'DHCP' : '${template.address}/${template.prefixLength}'} · ${_matchModeName(template.interfaceMatchMode)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _applying
                          ? null
                          : () => _apply(source: template),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const LocalizedText('一键应用'),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'load') _loadTemplate(template);
                        if (value == 'copy') unawaited(_copyTemplate(template));
                        if (value == 'rename')
                          unawaited(_renameTemplate(template));
                        if (value == 'delete')
                          unawaited(_deleteTemplate(template));
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'load',
                          child: LocalizedText('载入编辑'),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: LocalizedText('复制模板'),
                        ),
                        PopupMenuItem(
                          value: 'rename',
                          child: LocalizedText('重命名'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: LocalizedText('删除模板'),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () => _loadTemplate(template),
              ),
            ),
      ],
    );
  }

  IconData _checkIcon(NetworkCheckState state) => switch (state) {
    NetworkCheckState.passed => Icons.check_circle_rounded,
    NetworkCheckState.warning => Icons.warning_amber_rounded,
    NetworkCheckState.notApplicable => Icons.remove_circle_outline_rounded,
    NetworkCheckState.pending ||
    NetworkCheckState.running => Icons.schedule_rounded,
  };

  Color _checkColor(NetworkCheckState state) => switch (state) {
    NetworkCheckState.passed => const Color(0xFF2FA778),
    NetworkCheckState.warning => const Color(0xFFE39A36),
    NetworkCheckState.notApplicable => Theme.of(context).colorScheme.outline,
    NetworkCheckState.pending ||
    NetworkCheckState.running => Theme.of(context).colorScheme.primary,
  };

  static String _transportName(String value) => switch (value) {
    'wifi' => 'Wi-Fi',
    'vpn' => 'VPN',
    'virtual' => '虚拟网卡',
    _ => '以太网',
  };

  static String _diagnosticName(NetworkDiagnosticKind value) => switch (value) {
    NetworkDiagnosticKind.adapter => '网卡链路',
    NetworkDiagnosticKind.gateway => '默认网关',
    NetworkDiagnosticKind.dns => 'DNS',
    NetworkDiagnosticKind.internet => '互联网',
  };

  static String _matchModeName(NetworkInterfaceMatchMode value) =>
      switch (value) {
        NetworkInterfaceMatchMode.exactName => '接口名',
        NetworkInterfaceMatchMode.macAddress => 'MAC',
        NetworkInterfaceMatchMode.defaultTransport => '默认同类型',
      };

  static String _formatTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';

  static List<String> _splitValues(String source) => source
      .split(RegExp(r'[,;\s]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

class _UnsupportedConfiguration extends StatelessWidget {
  const _UnsupportedConfiguration();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: LocalizedText('Android 仅展示当前网络参数，不提供系统 IP 配置入口。'),
    ),
  );
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension _IterableSingleOrNull<T> on Iterable<T> {
  T? get singleOrNull => length == 1 ? first : null;
}
