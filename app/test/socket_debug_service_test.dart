import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nettools_mobile/services/socket_debug_service.dart';

void main() {
  test(
    'TCP server can target one connected peer and tracks byte totals',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final service = SocketDebugService.instance;
      await service.stop();
      service.clearHistory();
      addTearDown(service.stop);

      await service.start(
        protocol: SocketDebugProtocol.tcp,
        role: SocketDebugRole.server,
        host: '',
        port: port,
        bindAddress: InternetAddress.loopbackIPv4.address,
      );
      final first = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final second = await Socket.connect(InternetAddress.loopbackIPv4, port);
      addTearDown(first.destroy);
      addTearDown(second.destroy);
      await _eventually(() => service.peerCount == 2);

      final firstPeer = service.peers.firstWhere(
        (peer) => peer.endsWith(':${first.port}'),
      );
      final received = first.first;
      await service.send(Uint8List.fromList([1, 2, 3]), peer: firstPeer);

      expect(await received.timeout(const Duration(seconds: 2)), [1, 2, 3]);
      expect(service.sentBytes, 3);
      expect(service.peers, hasLength(2));
    },
  );
}

Future<void> _eventually(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
