import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../data/app_database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../widgets/page_header.dart';
import 'smb_browser_page.dart';
import 'ssh_terminal_page.dart';
import 'ssh_tunnel_page.dart';
import 'transfer_center_page.dart';

class RemoteHomePage extends StatefulWidget {
  const RemoteHomePage({super.key, required this.appState});

  final AppState appState;

  @override
  State<RemoteHomePage> createState() => _RemoteHomePageState();
}

class _RemoteHomePageState extends State<RemoteHomePage> {
  final List<_RemoteSessionEntry> _sessions = [];
  int _activeSession = -1;

  AppState get appState => widget.appState;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _activeSession + 1,
      children: [
        _home(context),
        for (var index = 0; index < _sessions.length; index++)
          KeyedSubtree(
            key: ValueKey(_sessions[index].id),
            child: PopScope<void>(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && mounted) setState(() => _activeSession = -1);
              },
              child: _sessions[index].page,
            ),
          ),
      ],
    );
  }

  Widget _home(BuildContext context) {
    final strings = context.l10n.remote;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: strings.title,
            subtitle: strings.subtitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TransferCenterPage(appState: appState),
                    ),
                  ),
                  icon: const Icon(Icons.sync_alt),
                  tooltip: strings.transferCenter,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  tooltip: strings.newConnection,
                  onSelected: (value) =>
                      value == 'smb' ? _openSmb(context) : _openSsh(context),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'ssh',
                      child: LocalizedText('SSH / SFTP'),
                    ),
                    PopupMenuItem(
                      value: 'smb',
                      child: LocalizedText('SMB2 / SMB3'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_sessions.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            sliver: SliverToBoxAdapter(child: _activeSessionsCard(context)),
          ),
        StreamBuilder<List<RemoteProfile>>(
          stream: appState.database.watchRemoteProfiles(),
          builder: (context, snapshot) {
            final profiles = snapshot.data ?? const <RemoteProfile>[];
            if (profiles.isEmpty) {
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(child: _emptyCard(context)),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: profiles.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: LocalizedText(
                        strings.savedConnections,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    );
                  }
                  return _profileCard(context, profiles[index - 1]);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _activeSessionsCard(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFF20B77A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: LocalizedText(
                  '激活会话',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              LocalizedText('${_sessions.length} 个'),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < _sessions.length; index++)
                InputChip(
                  avatar: Icon(
                    _sessions[index].protocol == 'smb'
                        ? Icons.folder_shared_outlined
                        : Icons.terminal_rounded,
                    size: 18,
                  ),
                  label: Text(_sessions[index].label),
                  onPressed: () => setState(() => _activeSession = index),
                  onDeleted: () => _closeSession(index),
                  deleteButtonTooltipMessage: context.tr('关闭并断开会话'),
                ),
            ],
          ),
          const SizedBox(height: 7),
          LocalizedText(
            '切换页面不会断开连接；点击会话右侧关闭按钮才会释放连接。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyCard(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(26),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1028446D),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 132,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF397CF7), Color(0xFF70C4F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final size in [102.0, 70.0])
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .18),
                    ),
                  ),
                ),
              const Icon(Icons.terminal_rounded, size: 45, color: Colors.white),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LocalizedText(
          context.l10n.remote.emptyTitle,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        LocalizedText(
          context.l10n.remote.emptyBody,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openSsh(context),
                icon: const Icon(Icons.terminal),
                label: LocalizedText(context.l10n.remote.newSsh),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openSmb(context),
                icon: const Icon(Icons.folder_shared_outlined),
                label: LocalizedText(context.l10n.remote.newSmb),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _profileCard(BuildContext context, RemoteProfile profile) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      minVerticalPadding: 12,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          profile.protocol == 'smb'
              ? Icons.folder_shared_outlined
              : Icons.terminal_rounded,
          color: Theme.of(context).colorScheme.primary,
          size: 23,
        ),
      ),
      title: LocalizedText(
        profile.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: LocalizedText(
        profile.protocol == 'smb'
            ? '\\\\${profile.host}\\${profile.shareName}\nSMB2 / SMB3'
            : '${profile.username}@${profile.host}:${profile.port}\n${profile.authType == 'privateKey' ? context.l10n.remote.privateKeyAuth : context.l10n.remote.passwordAuth}',
      ),
      isThreeLine: true,
      onTap: () => profile.protocol == 'smb'
          ? _openSmb(context, profile: profile)
          : _openSsh(context, profile: profile, autoConnect: true),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.arrow_forward_rounded,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'connect') {
                profile.protocol == 'smb'
                    ? _openSmb(context, profile: profile)
                    : _openSsh(context, profile: profile, autoConnect: true);
              }
              if (action == 'edit' && profile.protocol == 'ssh') {
                _openSsh(context, profile: profile);
              }
              if (action == 'tunnel' && profile.protocol == 'ssh') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SshTunnelPage(appState: appState, profile: profile),
                  ),
                );
              }
              if (action == 'delete') _delete(context, profile);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'connect',
                child: LocalizedText(context.l10n.remote.connectNow),
              ),
              if (profile.protocol == 'ssh')
                PopupMenuItem(
                  value: 'tunnel',
                  child: LocalizedText(context.l10n.remote.sshTunnel),
                ),
              PopupMenuItem(
                value: 'edit',
                child: LocalizedText(context.l10n.remote.editProfile),
              ),
              PopupMenuItem(
                value: 'delete',
                child: LocalizedText(context.l10n.common.delete),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _delete(BuildContext context, RemoteProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LocalizedText(context.l10n.remote.deleteTitle(profile.name)),
        content: LocalizedText(context.l10n.remote.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: LocalizedText(context.l10n.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: LocalizedText(context.l10n.common.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (profile.secretRef != null) {
      await const FlutterSecureStorage().delete(key: profile.secretRef!);
    }
    await appState.database.deleteRemoteProfile(profile.id);
  }

  void _openSsh(
    BuildContext context, {
    RemoteProfile? profile,
    bool autoConnect = false,
  }) {
    final stableId = profile == null
        ? 'ssh:new:${DateTime.now().microsecondsSinceEpoch}'
        : 'ssh:${profile.id}';
    final existing = _sessions.indexWhere((session) => session.id == stableId);
    if (existing >= 0) {
      setState(() => _activeSession = existing);
      return;
    }
    final page = SshTerminalPage(
      appState: appState,
      profile: profile,
      autoConnect: autoConnect,
      onLeave: _showRemoteHome,
    );
    setState(() {
      _sessions.add(
        _RemoteSessionEntry(
          id: stableId,
          protocol: 'ssh',
          label: profile?.name ?? context.tr('新建 SSH'),
          page: page,
        ),
      );
      _activeSession = _sessions.length - 1;
    });
  }

  void _openSmb(BuildContext context, {RemoteProfile? profile}) {
    final stableId = profile == null
        ? 'smb:new:${DateTime.now().microsecondsSinceEpoch}'
        : 'smb:${profile.id}';
    final existing = _sessions.indexWhere((session) => session.id == stableId);
    if (existing >= 0) {
      setState(() => _activeSession = existing);
      return;
    }
    setState(() {
      _sessions.add(
        _RemoteSessionEntry(
          id: stableId,
          protocol: 'smb',
          label: profile?.name ?? context.tr('新建 SMB'),
          page: SmbBrowserPage(
            appState: appState,
            profile: profile,
            onLeave: _showRemoteHome,
          ),
        ),
      );
      _activeSession = _sessions.length - 1;
    });
  }

  Future<void> _closeSession(int index) async {
    if (index < 0 || index >= _sessions.length) return;
    final session = _sessions[index];
    final close = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('关闭远程会话？'),
        content: LocalizedText('将断开 ${session.label} 并释放该会话中的连接和输入状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: LocalizedText(context.l10n.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('断开并关闭'),
          ),
        ],
      ),
    );
    if (close != true || !mounted) return;
    setState(() {
      _sessions.removeAt(index);
      _activeSession = -1;
    });
  }

  void _showRemoteHome() {
    if (mounted) setState(() => _activeSession = -1);
  }
}

class _RemoteSessionEntry {
  const _RemoteSessionEntry({
    required this.id,
    required this.protocol,
    required this.label,
    required this.page,
  });

  final String id;
  final String protocol;
  final String label;
  final Widget page;
}
