import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/download_destination_service.dart';

void main() {
  group('DownloadDestinationService.safeFileName', () {
    test('keeps only the final path component', () {
      expect(
        DownloadDestinationService.safeFileName('../../router/config.txt'),
        'config.txt',
      );
    });

    test('replaces characters rejected by desktop save dialogs', () {
      expect(
        DownloadDestinationService.safeFileName('capture:wan?.pcap'),
        'capture_wan_.pcap',
      );
    });

    test('protects Windows reserved device names', () {
      expect(DownloadDestinationService.safeFileName('CON.txt'), '_CON.txt');
    });

    test('provides a safe fallback for an empty name', () {
      expect(DownloadDestinationService.safeFileName(''), 'download.bin');
    });
  });
}
