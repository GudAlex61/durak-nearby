import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'framing.dart';

class NearbyTable {
  final Peripheral peripheral;
  final String name;
  NearbyTable(this.peripheral, this.name);
}

/// Only BLE is used: no network sockets, Wi-Fi, server, or internet access.
class BleLink {
  static final serviceId = UUID.fromString(
    'a8c90001-9f35-4d78-bbe8-060cd39d54d0',
  );
  static final rxId = UUID.fromString('a8c90002-9f35-4d78-bbe8-060cd39d54d0');
  static final txId = UUID.fromString('a8c90003-9f35-4d78-bbe8-060cd39d54d0');
  CentralManager? _central;
  PeripheralManager? _peripheral;
  Peripheral? _remote;
  Central? _guest;
  GATTCharacteristic? _rx, _tx;
  ReliableChannel? _channel;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final Map<String, NearbyTable> tables = {};
  void Function()? onTablesChanged;
  void Function(Map<String, dynamic>)? onMessage;
  void Function(bool)? onConnected;
  void Function(String)? onError;
  bool _closed = false;

  void _fail(Object error) {
    if (!_closed) onError?.call('$error');
  }

  void _receive(Uint8List value) {
    _channel?.receive(value).catchError((Object e) => _fail(e));
  }

  Future<void> _ready(BluetoothLowEnergyManager manager) async {
    if (Platform.isAndroid) await manager.authorize();
    if (manager.state == BluetoothLowEnergyState.poweredOn) return;
    final event = await manager.stateChanged
        .firstWhere(
          (event) =>
              event.state == BluetoothLowEnergyState.poweredOn ||
              event.state == BluetoothLowEnergyState.unsupported,
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw StateError(
            'Включите Bluetooth и разрешите доступ в настройках приложения',
          ),
        );
    if (event.state != BluetoothLowEnergyState.poweredOn) {
      throw StateError('BLE не поддерживается этим устройством');
    }
  }

  Future<void> host(String code) async {
    final manager = _peripheral = PeripheralManager();
    await _ready(manager);
    if (_closed) {
      throw StateError('Операция отменена');
    }
    if (Platform.isAndroid) {
      _subscriptions.add(
        manager.connectionStateChanged.listen((event) {
          if (event.state == ConnectionState.disconnected &&
              event.central.uuid == _guest?.uuid) {
            _guest = null;
            _channel?.close();
            _channel = null;
            onConnected?.call(false);
          }
        }),
      );
    }
    _rx = GATTCharacteristic.mutable(
      uuid: rxId,
      properties: [GATTCharacteristicProperty.write],
      permissions: [GATTCharacteristicPermission.write],
      descriptors: [],
    );
    _tx = GATTCharacteristic.mutable(
      uuid: txId,
      properties: [GATTCharacteristicProperty.notify],
      permissions: [],
      descriptors: [],
    );
    _subscriptions.add(
      manager.characteristicWriteRequested.listen((e) async {
        try {
          await manager.respondWriteRequest(e.request);
          if (e.characteristic.uuid == rxId && e.central.uuid == _guest?.uuid) {
            _receive(e.request.value);
          }
        } catch (error) {
          _fail(error);
        }
      }),
    );
    _subscriptions.add(
      manager.characteristicNotifyStateChanged.listen((e) {
        if (e.characteristic.uuid != txId) return;
        if (e.state) {
          // Never let a second subscriber replace the current opponent.
          if (_guest != null && _guest!.uuid != e.central.uuid) return;
          _guest = e.central;
          _channel?.close();
          _channel = ReliableChannel(
            write: (data) async {
              await manager.notifyCharacteristic(e.central, _tx!, value: data);
              await Future<void>.delayed(const Duration(milliseconds: 12));
            },
            onMessage: (m) => onMessage?.call(m),
          );
          onConnected?.call(true);
        } else if (_guest?.uuid == e.central.uuid) {
          _guest = null;
          _channel?.close();
          _channel = null;
          onConnected?.call(false);
        }
      }),
    );
    await manager.removeAllServices();
    await manager.addService(
      GATTService(
        uuid: serviceId,
        isPrimary: true,
        includedServices: [],
        characteristics: [_rx!, _tx!],
      ),
    );
    await manager.startAdvertising(
      Advertisement(
        name: Platform.isAndroid ? null : 'Durak ${code.substring(4)}',
        serviceUUIDs: [serviceId],
      ),
    );
  }

  Future<void> scan() async {
    final manager = _central = CentralManager();
    await _ready(manager);
    if (_closed) {
      throw StateError('Операция отменена');
    }
    _subscriptions.add(
      manager.discovered.listen((e) {
        tables['${e.peripheral.uuid}'] = NearbyTable(
          e.peripheral,
          e.advertisement.name ?? 'Стол Дурак',
        );
        onTablesChanged?.call();
      }),
    );
    _subscriptions.add(
      manager.connectionStateChanged.listen((e) {
        if (e.peripheral.uuid == _remote?.uuid &&
            e.state == ConnectionState.disconnected) {
          _channel?.close();
          _channel = null;
          onConnected?.call(false);
        }
      }),
    );
    _subscriptions.add(
      manager.characteristicNotified.listen((e) {
        if (e.peripheral.uuid == _remote?.uuid &&
            e.characteristic.uuid == txId) {
          _receive(e.value);
        }
      }),
    );
    await manager.startDiscovery(serviceUUIDs: [serviceId]);
  }

  Future<void> join(NearbyTable table) async {
    final manager = _central!;
    _channel?.close();
    await manager.stopDiscovery();
    if (_remote != null) {
      try {
        await manager.disconnect(_remote!);
      } catch (_) {
        /* Already disconnected. */
      }
    }
    _remote = table.peripheral;
    await manager.connect(_remote!).timeout(const Duration(seconds: 15));
    final services = await manager
        .discoverGATT(_remote!)
        .timeout(const Duration(seconds: 15));
    final service = services.firstWhere((s) => s.uuid == serviceId);
    _rx = service.characteristics.firstWhere((c) => c.uuid == rxId);
    _tx = service.characteristics.firstWhere((c) => c.uuid == txId);
    _channel = ReliableChannel(
      write: (data) => manager.writeCharacteristic(
        _remote!,
        _rx!,
        value: data,
        type: GATTCharacteristicWriteType.withResponse,
      ),
      onMessage: (m) => onMessage?.call(m),
    );
    await manager.setCharacteristicNotifyState(_remote!, _tx!, state: true);
    onConnected?.call(true);
  }

  Future<void> send(Map<String, dynamic> message) async {
    final channel = _channel;
    if (channel == null) throw StateError('Нет соединения со вторым игроком');
    await channel.send(message);
  }

  Future<void> close() async {
    _closed = true;
    _channel?.close();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    try {
      await _central?.stopDiscovery();
    } catch (_) {
      /* Already stopped. */
    }
    try {
      if (_remote != null) await _central?.disconnect(_remote!);
    } catch (_) {
      /* Lost link. */
    }
    try {
      await _peripheral?.stopAdvertising();
    } catch (_) {
      /* Already stopped. */
    }
    try {
      await _peripheral?.removeAllServices();
    } catch (_) {
      /* Manager closed. */
    }
  }
}
