import 'package:flutter_test/flutter_test.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:durak_bt/game/session.dart';
import 'package:durak_bt/network/ble_link.dart';

class TestPeripheral implements Peripheral {
  @override
  UUID get uuid => UUID.fromString('a8c90010-9f35-4d78-bbe8-060cd39d54d0');
}

class MemoryLink extends BleLink {
  MemoryLink? peer;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> host(String code) async {}
  @override
  Future<void> scan() async {}
  @override
  Future<void> join(NearbyTable table) async {
    onConnected?.call(true);
    peer!.onConnected?.call(true);
  }

  @override
  Future<void> send(Map<String, dynamic> m) async {
    sent.add(m);
    peer!.onMessage?.call(m);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> close() async {}
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'two sessions agree; hidden hand stays private; duplicate command is ignored',
    () async {
      final a = MemoryLink(), b = MemoryLink();
      a.peer = b;
      b.peer = a;
      final host = GameSession(linkFactory: () => a),
          guest = GameSession(linkFactory: () => b);
      await host.host();
      await guest.scan();
      await guest.join(NearbyTable(TestPeripheral(), 'table'), host.roomCode);
      await settle();
      expect(host.connected && guest.connected, true);
      expect(host.view!['revision'], guest.view!['revision']);
      expect(host.view!['you'], 0);
      expect(guest.view!['you'], 1);
      final attacking = host.view!['attacker'] == 0 ? host : guest;
      await attacking.action(
        'attack',
        card: (attacking.view!['hand'] as List).first as int,
      );
      await settle();
      expect(host.view!['revision'], 1);
      expect(guest.view!['revision'], 1);
      final defending = attacking == host ? guest : host;
      await defending.action('take');
      await settle();
      expect(host.view!['taking'], true);
      expect(guest.view!['taking'], true);
      await attacking.action('finish');
      await settle();
      expect(host.view!['revision'], 3);
      expect(guest.view!['revision'], 3);
      final command = b.sent.firstWhere((m) => m['type'] == 'command');
      await b.send(command);
      await settle();
      expect(host.view!['revision'], 3);
      final snapshot =
          a.sent.firstWhere((m) => m['type'] == 'state')['view'] as Map;
      expect(snapshot.keys, isNot(contains('deck')));
      expect(snapshot.keys, isNot(contains('hands')));
      a.onConnected?.call(false);
      b.onConnected?.call(false);
      expect(host.connected || guest.connected, false);
      await guest.reconnect();
      await settle();
      expect(host.connected && guest.connected, true);
      expect(host.view!['revision'], 3);
      expect(guest.view!['revision'], 3);
      host.dispose();
      guest.dispose();
    },
  );
  test('incorrect room code cannot start a game', () async {
    final a = MemoryLink(), b = MemoryLink();
    a.peer = b;
    b.peer = a;
    final host = GameSession(linkFactory: () => a),
        guest = GameSession(linkFactory: () => b);
    await host.host();
    await guest.scan();
    await guest.join(NearbyTable(TestPeripheral(), 'table'), '000000');
    await settle();
    expect(host.view, null);
    expect(guest.view, null);
    expect(host.connected, false);
    expect(guest.error, contains('Неверный код'));
    host.dispose();
    guest.dispose();
  });
}
