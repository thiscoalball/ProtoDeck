import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/models/network_context.dart';

void main() {
  test('parses detailed LTE cellular measurements', () {
    final context = NetworkContext.fromMap({
      'connected': true,
      'interfaceName': 'rmnet_data0',
      'transports': <Object?>['cellular'],
      'validated': true,
      'metered': true,
      'addresses': <Object?>[],
      'dnsServers': <Object?>[],
      'gateways': <Object?>[],
      'mtu': 1500,
      'cellular': <Object?, Object?>{
        'operatorName': '中国移动',
        'radioTechnology': 'LTE',
        'dbm': -91,
        'level': 3,
        'registered': true,
        'neighborCellCount': 4,
        'metrics': <Object?, Object?>{'RSRP': -91, 'RSRQ': -11, 'RSSNR': 18},
        'identity': <Object?, Object?>{'PCI': 123, 'EARFCN': 38950},
      },
    });

    expect(context.cellular?.radioTechnology, 'LTE');
    expect(context.cellular?.level, 3);
    expect(context.cellular?.metrics['RSRP'], -91);
    expect(context.cellular?.metrics['RSRQ'], -11);
    expect(context.cellular?.metrics['RSSNR'], 18);
    expect(context.cellular?.identity['EARFCN'], '38950');
  });

  test('parses 5G NR SS and CSI measurements', () {
    final cell = CellularConnectionInfo.fromMap(<Object?, Object?>{
      'radioTechnology': '5G NR',
      'metrics': <Object?, Object?>{
        'SS-RSRP': -87,
        'SS-RSRQ': -10,
        'SS-SINR': 24,
        'CSI-RSRP': -89,
      },
      'identity': <Object?, Object?>{'NRARFCN': 636666, 'Bands': '78'},
    });

    expect(cell.metrics['SS-SINR'], 24);
    expect(cell.metrics['CSI-RSRP'], -89);
    expect(cell.identity['Bands'], '78');
  });

  test('parses Wi-Fi scan freshness metadata', () {
    final snapshot = WifiScanSnapshot.fromMap(<Object?, Object?>{
      'fresh': false,
      'requested': false,
      'status': 'throttled_or_cached',
      'collectedAtMillis': 10000,
      'newestResultAgeMillis': 2500,
      'accessPoints': <Object?>[
        <Object?, Object?>{
          'ssid': 'Lab',
          'bssid': '00:11:22:33:44:55',
          'rssi': -52,
          'signalLevel': 4,
          'frequency': 5180,
          'channel': 36,
          'channelWidth': '80 MHz',
          'security': '[WPA2-PSK-CCMP][ESS]',
          'timestampMicros': 123,
        },
      ],
    });

    expect(snapshot.fresh, isFalse);
    expect(snapshot.status, 'throttled_or_cached');
    expect(snapshot.newestResultAge, const Duration(milliseconds: 2500));
    expect(snapshot.accessPoints.single.channel, 36);
    expect(snapshot.accessPoints.single.signalLevel, 4);
  });
}
