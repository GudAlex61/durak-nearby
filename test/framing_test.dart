import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:durak_bt/network/framing.dart';

void main() {
  test(
    'fragment UTF-8 messages into 20-byte frames and reassemble both ways',
    () async {
      late ReliableChannel a, b;
      final receivedA = <Map<String, dynamic>>[],
          receivedB = <Map<String, dynamic>>[];
      a = ReliableChannel(
        write: (f) async {
          expect(f.length, lessThanOrEqualTo(20));
          await b.receive(f);
        },
        onMessage: receivedA.add,
      );
      b = ReliableChannel(
        write: (f) async => a.receive(f),
        onMessage: receivedB.add,
      );
      final message = {'type': 'state', 'text': 'Козырь ♥. Дурак рядом! ' * 80};
      await a.send(message);
      await b.send({'type': 'command', 'card': 4});
      expect(receivedB.single, message);
      expect(receivedA.single['card'], 4);
      a.close();
      b.close();
    },
  );
  test('lost middle frame is retried without applying message twice', () async {
    late ReliableChannel a, b;
    var dropped = false;
    var delivered = 0;
    a = ReliableChannel(
      ackTimeout: const Duration(milliseconds: 10),
      write: (f) async {
        if (f[0] == 0xd0 && f[4] == 2 && !dropped) {
          dropped = true;
          return;
        }
        await b.receive(f);
      },
      onMessage: (_) {},
    );
    b = ReliableChannel(
      write: (f) => a.receive(f),
      onMessage: (_) => delivered++,
    );
    await a.send({'text': 'packet' * 30});
    expect(dropped, true);
    expect(delivered, 1);
    a.close();
    b.close();
  });
  test('lost acknowledgement is retried and deduplicated', () async {
    late ReliableChannel a, b;
    var lostAck = false;
    var delivered = 0;
    a = ReliableChannel(
      ackTimeout: const Duration(milliseconds: 10),
      write: (f) => b.receive(f),
      onMessage: (_) {},
    );
    b = ReliableChannel(
      write: (f) async {
        if (!lostAck) {
          lostAck = true;
          return;
        }
        await a.receive(f);
      },
      onMessage: (_) => delivered++,
    );
    await a.send({'text': 'hello'});
    expect(delivered, 1);
    a.close();
    b.close();
  });
  test('invalid packets are ignored and unavailable peer times out', () async {
    final a = ReliableChannel(
      ackTimeout: const Duration(milliseconds: 5),
      write: (_) async {},
      onMessage: (_) => fail('bad message'),
    );
    await a.receive(Uint8List.fromList([0xd0, 1]));
    await a.receive(Uint8List.fromList([0xd0, 0, 1, 0, 0, 255, 255, 1]));
    await expectLater(a.send({'x': 1}), throwsA(isA<TimeoutException>()));
    a.close();
  });
  test('concurrent send calls preserve order', () async {
    late ReliableChannel a, b;
    final ids = <int>[];
    a = ReliableChannel(write: (f) => b.receive(f), onMessage: (_) {});
    b = ReliableChannel(
      write: (f) => a.receive(f),
      onMessage: (m) => ids.add(m['n'] as int),
    );
    await Future.wait(List.generate(20, (n) => a.send({'n': n})));
    expect(ids, List.generate(20, (i) => i));
    a.close();
    b.close();
  });
  test(
    'simultaneous messages serialize native writes including ACKs',
    () async {
      late ReliableChannel a, b;
      var activeA = 0, activeB = 0;
      final receivedA = <int>[], receivedB = <int>[];
      a = ReliableChannel(
        write: (frame) async {
          expect(++activeA, 1);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          scheduleMicrotask(() => b.receive(frame));
          activeA--;
        },
        onMessage: (m) => receivedA.add(m['n'] as int),
      );
      b = ReliableChannel(
        write: (frame) async {
          expect(++activeB, 1);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          scheduleMicrotask(() => a.receive(frame));
          activeB--;
        },
        onMessage: (m) => receivedB.add(m['n'] as int),
      );
      await Future.wait([
        for (var i = 0; i < 12; i++) ...[
          a.send({'n': i, 'payload': 'state' * 30}),
          b.send({'n': i, 'payload': 'command' * 15}),
        ],
      ]);
      expect(receivedA, List.generate(12, (i) => i));
      expect(receivedB, List.generate(12, (i) => i));
      a.close();
      b.close();
    },
  );
}
