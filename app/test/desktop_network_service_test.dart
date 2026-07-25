import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/linux_network_service.dart';
import 'package:nettools_mobile/services/windows_network_service.dart';

void main() {
  group('Windows network parsers', () {
    test('parses current Wi-Fi without inventing unavailable values', () {
      final wifi = WindowsNetworkBridge.parseCurrentWifi('''
    SSID                   : Lab WiFi
    BSSID                  : AA:BB:CC:DD:EE:FF
    Radio type             : 802.11ax
    Channel                : 36
    Receive rate (Mbps)    : 1201.0
    Transmit rate (Mbps)   : 866.7
    Signal                 : 86%
''');
      expect(wifi?['ssid'], 'Lab WiFi');
      expect(wifi?['channel'], 36);
      expect(wifi?['frequency'], 5180);
      expect(wifi?['rssi'], -57);
      expect(wifi?['txLinkSpeedMbps'], 867);
    });

    test('parses cached Windows BSSID scan', () {
      final rows = WindowsNetworkBridge.parseWifiScan('''
SSID 1 : Example
    Authentication         : WPA2-Personal
    BSSID 1                : 11:22:33:44:55:66
         Signal            : 72%
         Channel           : 44
''');
      expect(rows, hasLength(1));
      expect(rows.single['ssid'], 'Example');
      expect(rows.single['channel'], 44);
      expect(rows.single['frequency'], 5220);
      expect(rows.single['security'], 'WPA2-Personal');
    });

    test('normalizes localized Windows ping for shared statistics', () {
      final output = WindowsNetworkBridge.normalizeWindowsPing(
        '来自 192.0.2.1 的回复: 字节=32 时间<1ms TTL=64',
        expectedCount: 1,
      );
      expect(output, contains('From 192.0.2.1: icmp_seq=1 ttl=64 time=1 ms'));
    });

    test('parses Windows tracert hops in numeric order', () {
      final rows = WindowsNetworkBridge.parseTraceroute('''
  1    <1 ms    <1 ms     1 ms  192.0.2.1
  2     8 ms     9 ms     8 ms  edge.example [198.51.100.2]
''');
      expect(rows.map((row) => row['hop']), [1, 2]);
      expect(rows.last['hostname'], 'edge.example');
      expect(rows.last['address'], '198.51.100.2');
    });
  });

  group('Linux network parsers', () {
    test('parses NetworkManager Wi-Fi rows', () {
      final rows = LinuxNetworkBridge.parseNmcliWifi(
        '*|Lab WiFi|AA:BB:CC:DD:EE:FF|80|5180|36|866 Mbit/s|WPA2',
      );
      expect(rows, hasLength(1));
      expect(rows.single['active'], isTrue);
      expect(rows.single['rssi'], -60);
      expect(rows.single['channel'], 36);
      expect(rows.single['linkSpeedMbps'], 866);
    });

    test('sums Linux interface counters and excludes loopback', () {
      final counters = LinuxNetworkBridge.parseProcNetDev('''
Inter-| Receive                                                | Transmit
 face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed
    lo: 100 1 0 0 0 0 0 0 100 1 0 0 0 0 0 0
  eth0: 1024 1 0 0 0 0 0 0 2048 2 0 0 0 0 0 0
 wlan0: 4096 4 0 0 0 0 0 0 8192 8 0 0 0 0 0 0
''');
      expect(counters.$1, 5120);
      expect(counters.$2, 10240);
    });

    test('decodes Linux proc TCP endpoints', () {
      final rows = LinuxNetworkBridge.parseProcConnections(
        '''
 sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt uid
  0: 0100007F:1F90 0100007F:C350 01 00000000:00000000 00:00000000 00000000 1000
''',
        protocol: 'TCP',
        ipVersion: 4,
      );
      expect(rows.single['localAddress'], '127.0.0.1');
      expect(rows.single['localPort'], 8080);
      expect(rows.single['remotePort'], 50000);
      expect(rows.single['state'], 'Established');
    });

    test('parses Linux traceroute samples', () {
      final rows = LinuxNetworkBridge.parseTraceroute(
        '1  gateway.example (192.0.2.1)  1.01 ms  1.20 ms  1.10 ms',
        probes: 3,
      );
      expect(rows.single['hop'], 1);
      expect(rows.single['hostname'], 'gateway.example');
      expect(rows.single['address'], '192.0.2.1');
      expect(rows.single['samplesMs'], [1.01, 1.20, 1.10]);
    });
  });
}
