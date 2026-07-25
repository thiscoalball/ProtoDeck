import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/oui/oui_repository.dart';
import '../../../services/tool_draft_repository.dart';
import '../../../state/app_state.dart';
import '../../../state/providers.dart';

enum _OuiLookupMode { mac, organization }

class OuiLookupPage extends ConsumerStatefulWidget {
  const OuiLookupPage({super.key, required this.appState, this.initialMac});

  final AppState appState;
  final String? initialMac;

  @override
  ConsumerState<OuiLookupPage> createState() => _OuiLookupPageState();
}

class _OuiLookupPageState extends ConsumerState<OuiLookupPage> {
  final _mac = TextEditingController(text: '00:00:0C:00:00:00');
  final _organization = TextEditingController();
  _OuiLookupMode _mode = _OuiLookupMode.mac;
  OuiMatch? _match;
  OuiOrganizationSearchResult? _organizationResult;
  String? _message;
  bool _searching = false;
  Timer? _debounce;
  late final ToolDraftRepository _drafts;
  bool _draftLoaded = false;

  @override
  void initState() {
    super.initState();
    _drafts = ToolDraftRepository(widget.appState.database);
    _mac.addListener(_saveDraft);
    _organization.addListener(_saveDraft);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_draftLoaded) unawaited(_drafts.save('tool.oui', _draftValue()));
    _drafts.dispose();
    _mac.dispose();
    _organization.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('MAC 厂商查询')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<_OuiLookupMode>(
          segments: const [
            ButtonSegment(
              value: _OuiLookupMode.mac,
              icon: Icon(Icons.memory_outlined),
              label: LocalizedText('MAC 查厂商'),
            ),
            ButtonSegment(
              value: _OuiLookupMode.organization,
              icon: Icon(Icons.corporate_fare_outlined),
              label: LocalizedText('厂商查前缀'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (values) {
            _debounce?.cancel();
            setState(() {
              _mode = values.first;
              _message = null;
            });
            _saveDraft();
          },
        ),
        const SizedBox(height: 18),
        if (_mode == _OuiLookupMode.mac) _macLookup() else _reverseLookup(),
        const SizedBox(height: 14),
        if (_message case final message?)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LocalizedText(message),
            ),
          ),
        if (_mode == _OuiLookupMode.mac && _match != null) _macResult(_match!),
        if (_mode == _OuiLookupMode.organization && _organizationResult != null)
          _organizationResults(_organizationResult!),
        const SizedBox(height: 12),
        LocalizedText(
          _mode == _OuiLookupMode.mac
              ? '查询完全使用离线 IEEE MA-L、MA-M、MA-S 数据，并按 36/28/24 位最长前缀匹配。'
              : '反向查询展示厂商在 IEEE 登记的前缀和理论地址范围，不代表这些地址当前均有实际设备使用。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _macLookup() => Column(
    children: [
      TextField(
        controller: _mac,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _lookupMac(),
        decoration: const InputDecoration(
          label: LocalizedText('MAC 地址'),
          hintText: 'AA:BB:CC:DD:EE:FF',
          prefixIcon: Icon(Icons.router_outlined),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _lookupMac,
          icon: const Icon(Icons.search),
          label: const LocalizedText('离线查询'),
        ),
      ),
    ],
  );

  Widget _reverseLookup() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _organization,
        textInputAction: TextInputAction.search,
        onChanged: _scheduleOrganizationSearch,
        onSubmitted: (_) => _searchOrganization(),
        decoration: InputDecoration(
          label: LocalizedText('公司或厂商名称'),
          hint: LocalizedText('例如 Cisco、Huawei、Apple'),
          prefixIcon: const Icon(Icons.corporate_fare_outlined),
          suffixIcon: _organization.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _debounce?.cancel();
                    _organization.clear();
                    setState(() {
                      _organizationResult = null;
                      _message = null;
                    });
                  },
                  icon: const Icon(Icons.clear),
                  tooltip: context.tr('清空'),
                ),
        ),
      ),
      const SizedBox(height: 8),
      LocalizedText(
        '支持名称片段匹配，搜索结果按完全匹配、名称开头、名称包含排序。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _searching ? null : _searchOrganization,
          icon: _searching
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: LocalizedText(_searching ? '正在搜索' : '搜索 IEEE 厂商登记'),
        ),
      ),
    ],
  );

  Widget _macResult(OuiMatch match) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            match.organizationName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _row('标准化 MAC', match.normalizedMac),
          _row('IEEE 注册表', '${match.registry} · ${match.prefixLength} bit'),
          _row('Assignment', match.assignment),
          _row(
            '组织地址',
            match.organizationAddress.isEmpty ? '—' : match.organizationAddress,
          ),
          _row(
            '地址属性',
            '${match.isMulticast ? '组播' : '单播'} · ${match.isLocallyAdministered ? '本地管理' : '全局管理'}',
          ),
          if (match.isLocallyAdministered)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LocalizedText('此 MAC 设置了本地管理位，厂商匹配结果可能没有实际意义。'),
            ),
          if (match.alternativeOrganizations.isNotEmpty)
            _row('历史登记', match.alternativeOrganizations.join('；')),
        ],
      ),
    ),
  );

  Widget _organizationResults(OuiOrganizationSearchResult result) {
    if (result.items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LocalizedText('没有找到匹配的 IEEE 厂商登记。可尝试英文名称或更短的关键词。'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: LocalizedText(
                  '找到 ${result.totalMatches} 个已登记前缀',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (result.truncated)
                LocalizedText(
                  '显示前 ${result.items.length} 个',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        for (final item in result.items) _organizationPrefixCard(item),
      ],
    );
  }

  Map<String, Object?> _draftValue() => {
    'mac': _mac.text,
    'organization': _organization.text,
    'mode': _mode.name,
  };

  Future<void> _restoreDraft() async {
    final draft = await _drafts.load('tool.oui');
    if (!mounted) return;
    if (draft != null) {
      _mac.text = draft.payload['mac']?.toString() ?? _mac.text;
      _organization.text =
          draft.payload['organization']?.toString() ?? _organization.text;
      _mode = _OuiLookupMode.values.firstWhere(
        (value) => value.name == draft.payload['mode'],
        orElse: () => _mode,
      );
    }
    final initialMac = widget.initialMac?.trim();
    if (initialMac != null && initialMac.isNotEmpty) {
      _mac.text = initialMac;
      _mode = _OuiLookupMode.mac;
    }
    setState(() {});
    _draftLoaded = true;
  }

  void _saveDraft() {
    if (_draftLoaded) _drafts.scheduleSave('tool.oui', _draftValue());
  }

  Widget _organizationPrefixCard(OuiOrganizationPrefix item) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LocalizedText(
                  item.organizationName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: LocalizedText(
                  '${item.registry} · /${item.prefixLength}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              IconButton(
                onPressed: () => _copy(item.formattedPrefix),
                icon: const Icon(Icons.copy, size: 19),
                tooltip: context.tr('复制前缀'),
              ),
            ],
          ),
          SelectableText(
            item.formattedPrefix,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _compactRow('Assignment', item.assignment),
          _compactRow('地址范围', '${item.firstAddress} — ${item.lastAddress}'),
          if (item.organizationAddress.isNotEmpty)
            _compactRow('注册地址', item.organizationAddress),
        ],
      ),
    ),
  );

  Widget _row(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: LocalizedText(name)),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );

  Widget _compactRow(String name, String value) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: LocalizedText(
            name,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    ),
  );

  void _lookupMac() {
    try {
      final match = ref.read(ouiRepositoryProvider).lookup(_mac.text);
      setState(() {
        _match = match;
        _message = match == null ? 'IEEE 数据库中未找到匹配前缀，不推测厂商。' : null;
      });
    } on Object catch (error) {
      setState(() {
        _match = null;
        _message = '$error';
      });
    }
  }

  void _scheduleOrganizationSearch(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _organizationResult = null;
        _message = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), _searchOrganization);
  }

  Future<void> _searchOrganization() async {
    _debounce?.cancel();
    if (_searching) return;
    setState(() {
      _searching = true;
      _message = null;
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final result = ref
          .read(ouiRepositoryProvider)
          .searchOrganizations(_organization.text);
      if (!mounted) return;
      setState(() => _organizationResult = result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _organizationResult = null;
        _message = '$error';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: LocalizedText('已复制 MAC 前缀')));
  }
}
