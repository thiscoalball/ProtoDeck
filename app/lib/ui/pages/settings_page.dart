import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/oui/oui_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../widgets/settings/preference_cards.dart';
import 'platform_capabilities_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  OuiDatabaseMetadata? _metadata;
  bool _updating = false;
  double _progress = 0;
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    _refreshMetadata();
  }

  void _refreshMetadata() {
    setState(() => _metadata = ref.read(ouiRepositoryProvider).metadata());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final metadata = _metadata;
    final localizations = context.l10n;
    final strings = localizations.settings;
    return Scaffold(
      appBar: AppBar(title: LocalizedText(strings.pageTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: LocalizedText(strings.pageSubtitle),
          ),
          LanguagePreferenceCard(
            value: state.language,
            onChanged: state.setLanguage,
          ),
          ThemePreferenceCard(
            value: state.themeMode,
            onChanged: state.setThemeMode,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: Text(strings.platformCapabilities),
                subtitle: Text(strings.platformCapabilitiesBody),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PlatformCapabilitiesPage(),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: Text(strings.toolDrafts),
                subtitle: Text(strings.toolDraftsBody),
                trailing: TextButton(
                  onPressed: _clearToolDrafts,
                  child: Text(strings.clearToolDrafts),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.memory),
                        const SizedBox(width: 10),
                        LocalizedText(
                          strings.ouiDatabase,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (metadata != null) ...[
                      _line(
                        strings.generatedAt,
                        DateFormat(
                          'yyyy-MM-dd HH:mm',
                          localizations.localeTag,
                        ).format(metadata.generatedAt.toLocal()),
                      ),
                      _line(
                        strings.records,
                        'MA-L ${metadata.counts['MA-L'] ?? 0} · MA-M ${metadata.counts['MA-M'] ?? 0} · MA-S ${metadata.counts['MA-S'] ?? 0}\n${strings.total} ${NumberFormat.decimalPattern(localizations.localeTag).format(metadata.totalRecords)}',
                      ),
                      _line(
                        strings.databaseSize,
                        '${(metadata.fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
                      ),
                      _line(
                        strings.ieeeModifiedAt,
                        metadata.lastModified.entries
                            .map(
                              (e) =>
                                  '${e.key}: ${e.value ?? localizations.common.unknown}',
                            )
                            .join('\n'),
                      ),
                    ],
                    if (_updating) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _progress),
                      LocalizedText(_progressText),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _updating ? null : _update,
                          icon: const Icon(Icons.system_update),
                          label: LocalizedText(strings.checkForUpdates),
                        ),
                        OutlinedButton.icon(
                          onPressed: _updating ? null : _restore,
                          icon: const Icon(Icons.restore),
                          label: LocalizedText(strings.restoreBundled),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LocalizedText(strings.ouiSourceNote),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.security_outlined),
                title: LocalizedText(strings.privacyTitle),
                subtitle: LocalizedText(strings.privacyBody),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showDetails(
                  title: strings.privacyTitle,
                  body: strings.privacyDetails,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: LocalizedText(strings.permissionsTitle),
                subtitle: LocalizedText(strings.permissionsBody),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showDetails(
                  title: strings.permissionsTitle,
                  body: strings.permissionsDetails,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: LocalizedText(strings.openSourceLicenses),
                subtitle: LocalizedText(strings.openSourceLicensesBody),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'ProtoDeck',
                  applicationVersion: ref
                      .read(buildInfoProvider)
                      .valueOrNull
                      ?.displayVersion,
                  applicationLegalese:
                      'Copyright 2026 ProtoDeck contributors\nApache License 2.0',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: _buildInfoCard(),
          ),
        ],
      ),
    );
  }

  Widget _line(String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: LocalizedText(key)),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );

  Widget _buildInfoCard() {
    final strings = context.l10n.settings;
    return Card(
      child: ref.watch(buildInfoProvider).when(
        loading: () => const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('ProtoDeck'),
          trailing: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, _) => ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('ProtoDeck'),
          subtitle: Text(strings.platforms),
        ),
        data: (info) => ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('${info.applicationName} ${info.displayVersion}'),
          subtitle: Text(
            '${info.displayBuild}\n${info.displayPlatform}',
            style: const TextStyle(fontFamily: 'monospace', height: 1.45),
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: strings.copyBuildInfo,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: info.copyText));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.buildInfoCopied)),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
          ),
        ),
      ),
    );
  }

  Future<void> _clearToolDrafts() async {
    final strings = context.l10n.settings;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.clearDraftsDialogTitle),
        content: Text(strings.clearDraftsDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.clearToolDrafts),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await ref.read(toolDraftRepositoryProvider).clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.draftsCleared)),
      );
    }
  }

  Future<void> _showDetails({required String title, required String body}) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: LocalizedText(title),
          content: SingleChildScrollView(child: SelectableText(body)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: LocalizedText(context.l10n.common.close),
            ),
          ],
        ),
      );

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _progress = 0;
      _progressText = context.l10n.settings.connectingIeee;
    });
    try {
      final result = await ref
          .read(ouiRepositoryProvider)
          .update(
            onProgress: (_, value) {
              if (mounted)
                setState(() {
                  _progressText = context.l10n.settings.updateProgress(value);
                  _progress = value;
                });
            },
          );
      _refreshMetadata();
      if (mounted) {
        final total = result.counts.values.fold<int>(0, (a, b) => a + b);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText(
              result.changed
                  ? context.l10n.settings.updateComplete(total)
                  : context.l10n.settings.ouiUpToDate,
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText(context.l10n.settings.updateFailed(error)),
          ),
        );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _restore() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: LocalizedText(context.l10n.settings.restoreDialogTitle),
        content: LocalizedText(context.l10n.settings.restoreDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: LocalizedText(context.l10n.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: LocalizedText(context.l10n.common.restore),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await ref.read(ouiRepositoryProvider).restoreBundled();
    _refreshMetadata();
  }
}
