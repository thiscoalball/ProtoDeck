import 'dart:ffi';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/build_info.dart';

class BuildInfoService {
  const BuildInfoService();

  static const _channel = String.fromEnvironment(
    'BUILD_CHANNEL',
    defaultValue: 'debug',
  );
  static const _gitSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'unknown',
  );

  Future<BuildInfo> load() async {
    final package = await PackageInfo.fromPlatform();
    return BuildInfo(
      applicationName: 'ProtoDeck',
      version: package.version,
      buildNumber: package.buildNumber,
      channel: _channel,
      gitSha: _gitSha,
      platform: _platformLabel,
      architecture: _architectureLabel,
    );
  }

  String get _platformLabel {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    return Platform.operatingSystem;
  }

  String get _architectureLabel => switch (Abi.current()) {
    Abi.androidArm => 'armeabi-v7a',
    Abi.androidArm64 => 'arm64-v8a',
    Abi.androidX64 => 'x86_64',
    Abi.windowsX64 => 'x64',
    Abi.windowsArm64 => 'arm64',
    Abi.linuxX64 => 'x64',
    Abi.linuxArm64 => 'arm64',
    Abi.macosX64 => 'x64',
    Abi.macosArm64 => 'arm64',
    Abi.iosArm64 => 'arm64',
    _ => Abi.current().toString().split('.').last,
  };
}
