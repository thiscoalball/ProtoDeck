import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/models/build_info.dart';

void main() {
  test('formats complete release build identity', () {
    const info = BuildInfo(
      applicationName: 'ProtoDeck',
      version: '0.0.1',
      buildNumber: '42',
      channel: 'release',
      gitSha: 'a1b2c3d4e5f6',
      platform: 'Windows',
      architecture: 'x64',
    );

    expect(info.displayVersion, '0.0.1 Release');
    expect(info.displayBuild, 'Build 42 · a1b2c3d4');
    expect(info.copyText, contains('Windows x64'));
  });

  test('manual release-mode artifact is still labelled as debug channel', () {
    const info = BuildInfo(
      applicationName: 'ProtoDeck',
      version: '0.0.1',
      buildNumber: '43',
      channel: 'debug',
      gitSha: 'unknown',
      platform: 'Linux',
      architecture: 'x64',
    );

    expect(info.displayVersion, '0.0.1 Debug');
    expect(info.displayBuild, 'Build 43');
  });
}
