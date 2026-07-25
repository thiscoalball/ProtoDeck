import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class SmbEntry {
  const SmbEntry({
    required this.name,
    required this.directory,
    required this.size,
    required this.modifiedMillis,
    required this.attributes,
  });

  final String name;
  final bool directory;
  final int size;
  final int modifiedMillis;
  final int attributes;

  factory SmbEntry.fromMap(Map<Object?, Object?> map) => SmbEntry(
    name: map['name'] as String? ?? '',
    directory: map['directory'] as bool? ?? false,
    size: (map['size'] as num?)?.toInt() ?? 0,
    modifiedMillis: (map['modifiedMillis'] as num?)?.toInt() ?? 0,
    attributes: (map['attributes'] as num?)?.toInt() ?? 0,
  );
}

class SmbConnectionInfo {
  const SmbConnectionInfo({
    required this.sessionId,
    required this.host,
    required this.share,
    required this.dialect,
    required this.guest,
    required this.anonymous,
  });

  final String sessionId;
  final String host;
  final String share;
  final String dialect;
  final bool guest;
  final bool anonymous;
}

class SmbService {
  static const _channel = MethodChannel('nettools/native');
  static final Map<String, String> _windowsSessions = {};

  Future<SmbConnectionInfo> connect({
    required String host,
    int port = 445,
    required String share,
    required String username,
    required String password,
    String domain = '',
  }) async {
    if (Platform.isLinux) {
      throw UnsupportedError(
        'Linux SMB 独立会话尚未接入 libsmbclient。请先通过桌面文件管理器挂载共享；应用不会把密码传给 shell 或命令行工具。',
      );
    }
    if (Platform.isWindows) {
      final root = p.windows.normalize(r'\\' + host + r'\' + share);
      final directory = Directory(root);
      try {
        if (!await directory.exists()) {
          throw FileSystemException('共享不存在或当前 Windows 凭据无权访问', root);
        }
      } on FileSystemException catch (error) {
        throw StateError(
          '无法访问 $root。Windows 版使用系统凭据管理器中的 SMB 凭据：${error.message}',
        );
      }
      final sessionId =
          'windows-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
      _windowsSessions[sessionId] = root;
      return SmbConnectionInfo(
        sessionId: sessionId,
        host: host,
        share: share,
        dialect: 'Windows UNC · 系统凭据',
        guest: username.isEmpty,
        anonymous: false,
      );
    }
    final map = await _channel.invokeMapMethod<Object?, Object?>('smbConnect', {
      'host': host,
      'port': port,
      'share': share,
      'username': username,
      'password': password,
      'domain': domain,
    });
    if (map == null) throw StateError('当前平台未返回 SMB 会话');
    return SmbConnectionInfo(
      sessionId: map['sessionId'] as String? ?? '',
      host: map['host'] as String? ?? host,
      share: map['share'] as String? ?? share,
      dialect: map['dialect'] as String? ?? 'SMB2/3',
      guest: map['guest'] as bool? ?? false,
      anonymous: map['anonymous'] as bool? ?? false,
    );
  }

  Future<List<SmbEntry>> list(String sessionId, String path) async {
    if (Platform.isWindows) {
      final directory = Directory(_windowsPath(sessionId, path));
      final rows = <SmbEntry>[];
      await for (final entity in directory.list(followLinks: false)) {
        final stat = await entity.stat();
        rows.add(
          SmbEntry(
            name: p.windows.basename(entity.path),
            directory: stat.type == FileSystemEntityType.directory,
            size: stat.type == FileSystemEntityType.file ? stat.size : 0,
            modifiedMillis: stat.modified.millisecondsSinceEpoch,
            attributes: 0,
          ),
        );
      }
      return rows;
    }
    final rows = await _channel.invokeListMethod<Object?>('smbList', {
      'sessionId': sessionId,
      'path': path,
    });
    return (rows ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(SmbEntry.fromMap)
        .toList(growable: false);
  }

  Future<void> mkdir(String sessionId, String path) => Platform.isWindows
      ? Directory(_windowsPath(sessionId, path)).create(recursive: false)
      : _channel.invokeMethod<void>('smbMkdir', {
          'sessionId': sessionId,
          'path': path,
        });

  Future<void> delete(
    String sessionId,
    String path, {
    required bool directory,
  }) => Platform.isWindows
      ? directory
            ? Directory(_windowsPath(sessionId, path)).delete(recursive: false)
            : File(_windowsPath(sessionId, path)).delete()
      : _channel.invokeMethod<void>('smbDelete', {
          'sessionId': sessionId,
          'path': path,
          'directory': directory,
        });

  Future<void> rename(String sessionId, String oldPath, String newPath) async {
    if (Platform.isWindows) {
      final oldValue = _windowsPath(sessionId, oldPath);
      final target = _windowsPath(sessionId, newPath);
      final type = await FileSystemEntity.type(oldValue, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(oldValue).rename(target);
      } else {
        await File(oldValue).rename(target);
      }
      return;
    }
    await _channel.invokeMethod<void>('smbRename', {
      'sessionId': sessionId,
      'oldPath': oldPath,
      'newPath': newPath,
    });
  }

  Future<int> upload(
    String sessionId,
    String localPath,
    String remotePath,
  ) async {
    if (Platform.isWindows) {
      final source = File(localPath);
      final target = await source.copy(_windowsPath(sessionId, remotePath));
      return target.length();
    }
    return (await _channel.invokeMethod<num>('smbUpload', {
          'sessionId': sessionId,
          'localPath': localPath,
          'remotePath': remotePath,
        }))?.toInt() ??
        0;
  }

  Future<int> download(
    String sessionId,
    String remotePath,
    String localPath,
  ) async {
    if (Platform.isWindows) {
      final target = await File(
        _windowsPath(sessionId, remotePath),
      ).copy(localPath);
      return target.length();
    }
    return (await _channel.invokeMethod<num>('smbDownload', {
          'sessionId': sessionId,
          'remotePath': remotePath,
          'localPath': localPath,
        }))?.toInt() ??
        0;
  }

  Future<void> disconnect(String sessionId) {
    if (Platform.isWindows) {
      _windowsSessions.remove(sessionId);
      return Future<void>.value();
    }
    return _channel.invokeMethod<void>('smbDisconnect', {
      'sessionId': sessionId,
    });
  }

  static String _windowsPath(String sessionId, String remotePath) {
    final root = _windowsSessions[sessionId];
    if (root == null) throw StateError('SMB 会话已结束，请重新连接');
    final relative = remotePath
        .replaceAll('/', r'\')
        .replaceFirst(RegExp(r'^\\+'), '');
    final value = p.windows.normalize(p.windows.join(root, relative));
    if (value != root && !p.windows.isWithin(root, value)) {
      throw const FormatException('远程路径不能离开共享根目录');
    }
    return value;
  }
}
