import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/telnet_service.dart';

void main() {
  test('negotiates Telnet options without exposing IAC bytes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first;
    final connection = await TelnetConnection.connect('127.0.0.1', server.port);
    final peer = await accepted;
    addTearDown(() async {
      await connection.close();
      peer.destroy();
      await server.close();
    });

    final output = connection.output.first;
    final negotiation = peer.first.timeout(const Duration(seconds: 2));
    peer.add([255, 251, 1, ...ascii.encode('login: ')]);
    await peer.flush();

    expect(await output, 'login: ');
    expect(await negotiation, containsAllInOrder([255, 253, 1]));
  });
}
