import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/models/network_context.dart';
import 'package:nettools_mobile/services/developer_tools_service.dart';

void main() {
  test('file hashing streams all supported digest algorithms', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nettools-file-hash-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/sample.txt');
    await file.writeAsString('abc');

    final result = await DeveloperToolsService().digestFile(file);

    expect(result['MD5'], '900150983cd24fb0d6963f7d28e17f72');
    expect(result['SHA-1'], 'a9993e364706816aba3e25717850c26c9cd0d89d');
    expect(
      result['SHA-256'],
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(result['SHA-512'], hasLength(128));
  });

  test('network context keeps multiple Windows adapters and default link', () {
    final context = NetworkContext.fromMap({
      'connected': true,
      'interfaceName': 'Ethernet',
      'transports': ['ethernet'],
      'validated': true,
      'metered': false,
      'addresses': <Object?>[],
      'dnsServers': <Object?>[],
      'gateways': <Object?>[],
      'mtu': 1500,
      'adapters': <Object?>[
        <Object?, Object?>{
          'interfaceIndex': 7,
          'name': 'Ethernet',
          'description': 'Intel Ethernet Controller',
          'status': 'Up',
          'transport': 'ethernet',
          'isDefault': true,
          'linkSpeed': '1 Gbps',
          'mtu': 1500,
          'addresses': <Object?>[],
          'dnsServers': <Object?>[],
          'gateways': <Object?>['192.168.1.1'],
        },
        <Object?, Object?>{
          'interfaceIndex': 12,
          'name': 'Wi-Fi',
          'description': 'Wireless Adapter',
          'status': 'Up',
          'transport': 'wifi',
          'isDefault': false,
          'linkSpeed': '866.7 Mbps',
          'mtu': 1500,
          'addresses': <Object?>[],
          'dnsServers': <Object?>[],
          'gateways': <Object?>[],
        },
      ],
    });

    expect(context.adapters, hasLength(2));
    expect(context.defaultAdapter?.name, 'Ethernet');
    expect(context.defaultAdapter?.linkSpeed, '1 Gbps');
  });
}
