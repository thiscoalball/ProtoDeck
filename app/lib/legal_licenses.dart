import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds licenses for native and bundled assets that are not registered by a
/// Dart package. Flutter packages continue to contribute their own entries.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'iPerf 3',
    ], await rootBundle.loadString('android/app/src/main/cpp/iperf/LICENSE'));
    yield LicenseEntryWithLineBreaks(
      const ['Droid Sans Fallback'],
      await rootBundle.loadString(
        'assets/fonts/DroidSansFallbackFull-LICENSE.txt',
      ),
    );
    yield LicenseEntryWithLineBreaks(const [
      'Cygwin runtime (Windows iPerf bundle)',
    ], await rootBundle.loadString('third_party/iperf3-windows-NOTICE.txt'));
    yield const LicenseEntryWithLineBreaks(
      ['IEEE Registration Authority public listings'],
      'ProtoDeck includes an offline database derived from the public IEEE '
      'MA-L, MA-M and MA-S assignment listings. IEEE and related marks '
      'belong to their respective owners. ProtoDeck is not affiliated with '
      'or endorsed by IEEE. Source URLs and generation metadata are stored '
      'with the database.',
    );
  });
}
