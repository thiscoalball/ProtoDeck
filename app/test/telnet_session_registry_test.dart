import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/telnet_service.dart';

void main() {
  final session = TelnetSessionRegistry.instance;

  tearDown(() => session.disconnect(clearTranscript: true));

  test('session remains connected when UI output listener detaches', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first.then((socket) {
      socket.write('router-ready\r\n');
      socket.listen((bytes) => socket.add(bytes));
      return socket;
    });

    await session.connect(InternetAddress.loopbackIPv4.address, server.port);
    final firstListener = session.output.listen((_) {});
    await firstListener.cancel();
    expect(session.connected, isTrue);

    final echoed = session.output.firstWhere((value) => value.contains('ping'));
    session.sendText('ping\n');
    expect(await echoed.timeout(const Duration(seconds: 2)), contains('ping'));
    expect(session.transcript, contains('router-ready'));

    await session.disconnect();
    expect(session.connected, isFalse);
    (await accepted).destroy();
    await server.close();
  });
}
