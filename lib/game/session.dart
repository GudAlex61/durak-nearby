import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../network/ble_link.dart';
import 'engine.dart';

class GameSession extends ChangeNotifier {
  GameSession({BleLink Function()? linkFactory})
    : _linkFactory = linkFactory ?? BleLink.new;
  @visibleForTesting
  factory GameSession.forGame(DurakGame game) {
    final session = GameSession();
    session.mode = 'bot';
    session.connected = true;
    session._active = false;
    session._game = game;
    session.view = game.view(0);
    return session;
  }
  final BleLink Function() _linkFactory;
  BleLink? _link;
  DurakGame? _game;
  Map<String, dynamic>? view;
  final List<NearbyTable> tables = [];
  String mode = 'home';
  String status = '';
  String? error;
  String roomCode = '';
  final String _token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String? _opponentToken;
  NearbyTable? _selected;
  bool connected = false;
  bool busy = false;
  int _commandId = 0;
  int _lastRemoteCommand = -1;
  Timer? _heartbeat;
  Timer? _botTimer;
  BotLevel botLevel = BotLevel.normal;
  int gameId = 0;
  int _deckSize = 36;
  bool _transferable = false;
  Random _botRandom = Random();
  bool _active = true;
  bool _resultRecorded = false;
  int wins = 0, losses = 0, draws = 0;
  int get played => wins + losses + draws;

  void setActive(bool value) {
    _active = value;
    if (!value) {
      _botTimer?.cancel();
    } else if (offline && view?['finished'] != true) {
      _scheduleBot();
    }
  }

  void _recordResult() {
    if (!offline || _resultRecorded || _game?.finished != true) return;
    _resultRecorded = true;
    if (_game!.loser == null) {
      draws++;
    } else if (_game!.loser == 0) {
      losses++;
    } else {
      wins++;
    }
  }

  DateTime _lastSeen = DateTime.now();
  bool _disposed = false;
  bool get isHost => mode == 'host';
  bool get offline => mode == 'bot';
  bool get canPlay => view != null && (offline || connected) && !busy;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _error(Object e) {
    error = '$e';
    busy = false;
    _changed();
  }

  Future<void> _run(Future<void> Function() task) async {
    try {
      await task();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> startBot({
    int? seed,
    BotLevel level = BotLevel.normal,
    int deckSize = 36,
    bool transferable = false,
  }) async {
    await reset();
    gameId++;
    botLevel = level;
    _botRandom = seed == null ? Random() : Random(seed);
    _resultRecorded = false;
    mode = 'bot';
    connected = true;
    _game = DurakGame(
      random: seed == null ? null : Random(seed),
      deckSize: deckSize,
      transferable: transferable,
    );
    view = _game!.view(0);
    status = 'Игра с ботом • ${botLevel.label}';
    _changed();
    _scheduleBot();
  }

  BleLink _makeLink() {
    final link = _linkFactory();
    link.onError = _error;
    link.onTablesChanged = () {
      tables
        ..clear()
        ..addAll(link.tables.values);
      _changed();
    };
    link.onConnected = (value) {
      if (!value) {
        connected = false;
        busy = false;
        status = 'Связь потеряна. Вернитесь к столу и подключитесь снова.';
      } else {
        _lastSeen = DateTime.now();
        status = 'Проверяем подключение…';
      }
      _changed();
    };
    link.onMessage = (message) => _run(() => _receive(message));
    return link;
  }

  Future<void> host({int deckSize = 36, bool transferable = false}) =>
      _run(() async {
        _deckSize = deckSize;
        _transferable = transferable;
        await reset();
        mode = 'host';
        roomCode = (100000 + Random.secure().nextInt(900000)).toString();
        status = 'Ожидаем второго игрока';
        busy = true;
        _changed();
        _link = _makeLink();
        await _link!.host(roomCode);
        busy = false;
        _startHeartbeat();
        _changed();
      });

  Future<void> scan() => _run(() async {
    await reset();
    mode = 'join';
    status = 'Ищем столы рядом…';
    busy = true;
    _changed();
    _link = _makeLink();
    await _link!.scan();
    busy = false;
    _changed();
  });

  Future<void> join(NearbyTable table, String code) => _run(() async {
    if (code.length != 6 || int.tryParse(code) == null) {
      throw RuleError('Введите 6 цифр с телефона ведущего');
    }
    _selected = table;
    busy = true;
    roomCode = code;
    status = 'Подключаемся…';
    _changed();
    await _link!.join(table);
    await _link!.send({
      'type': 'hello',
      'version': 2,
      'code': code,
      'token': _token,
    });
    busy = false;
    _startHeartbeat();
    _changed();
  });

  Future<void> reconnect() async {
    final table = _selected;
    if (table != null && mode == 'join') await join(table, roomCode);
  }

  Future<void> _receive(Map<String, dynamic> m) async {
    _lastSeen = DateTime.now();
    switch (m['type']) {
      case 'hello':
        if (!isHost) return;
        if (m['version'] != 2 ||
            m['code'] != roomCode ||
            m['token'] is! String ||
            (m['token'] as String).length != 48 ||
            (_opponentToken != null && _opponentToken != m['token'])) {
          await _link!.send({
            'type': 'error',
            'message': 'Неверный код или стол занят',
          });
          return;
        }
        _opponentToken = m['token'] as String;
        _game ??= DurakGame(deckSize: _deckSize, transferable: _transferable);
        connected = true;
        status = 'Bluetooth • стол $roomCode';
        await _publish();
        break;
      case 'state':
        if (isHost || mode != 'join') return;
        final next = Map<String, dynamic>.from(m['view'] as Map);
        if (view == null ||
            (next['revision'] as int) >= (view!['revision'] as int)) {
          view = next;
        }
        connected = true;
        status = 'Bluetooth • стол $roomCode';
        busy = false;
        break;
      case 'command':
        if (!isHost || !connected || m['token'] != _opponentToken) return;
        final id = m['id'];
        if (id is! int) return;
        if (id <= _lastRemoteCommand) {
          await _publish();
          return;
        }
        _lastRemoteCommand = id;
        try {
          if (m['revision'] != _game!.revision) {
            throw RuleError('Стол обновился, повторите ход');
          }
          _game!.apply(
            1,
            m['action'] as String,
            card: m['card'] as int?,
            target: m['target'] as int?,
          );
        } on RuleError catch (e) {
          await _link!.send({'type': 'error', 'message': e.message});
        }
        await _publish();
        break;
      case 'error':
        error = m['message'] as String? ?? 'Ошибка соединения';
        busy = false;
        break;
      case 'ping':
        await _link!.send({'type': 'pong'});
        break;
      case 'pong':
        if (_game != null && _opponentToken != null && isHost && !connected) {
          // A transport reconnect must still pass hello; do not unlock on ping.
          return;
        }
        break;
    }
    _changed();
  }

  Future<void> _publish() async {
    view = _game!.view(0);
    _changed();
    if (connected) await _link!.send({'type': 'state', 'view': _game!.view(1)});
  }

  Future<void> action(String action, {int? card, int? target}) =>
      _run(() async {
        if (!canPlay) return;
        error = null;
        if (offline || isHost) {
          _game!.apply(0, action, card: card, target: target);
          if (offline) {
            view = _game!.view(0);
            _recordResult();
            _changed();
            _scheduleBot();
          } else {
            busy = true;
            _changed();
            await _publish();
            busy = false;
            _changed();
          }
        } else {
          busy = true;
          _changed();
          await _link!.send({
            'type': 'command',
            'token': _token,
            'id': ++_commandId,
            'revision': view!['revision'],
            'action': action,
            'card': card,
            'target': target,
          });
          // Only an authoritative state or error unlocks the next command.
        }
      });

  void _scheduleBot() {
    _botTimer?.cancel();
    if (!_active || _game?.finished == true) return;
    _botTimer = Timer(const Duration(milliseconds: 780), () {
      if (!offline || _game == null || _disposed) return;
      final move = botMove(_game!, 1, level: botLevel, random: _botRandom);
      if (move == null) return;
      try {
        _game!.apply(
          1,
          move['action'] as String,
          card: move['card'] as int?,
          target: move['target'] as int?,
        );
        view = _game!.view(0);
        _recordResult();
        _changed();
        _scheduleBot();
      } catch (e) {
        _error(e);
      }
    });
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_disposed || !connected || busy) return;
      if (DateTime.now().difference(_lastSeen).inSeconds > 20) {
        connected = false;
        status = 'Нет ответа. Подключитесь к столу снова.';
        _changed();
        return;
      }
      _link?.send({'type': 'ping'}).catchError((Object e) {
        connected = false;
        _error(e);
      });
    });
  }

  void dismissError() {
    error = null;
    _changed();
  }

  Future<void> reset() async {
    _heartbeat?.cancel();
    _botTimer?.cancel();
    final old = _link;
    _link = null;
    if (old != null) await old.close();
    mode = 'home';
    _game = null;
    view = null;
    connected = false;
    busy = false;
    error = null;
    tables.clear();
    _opponentToken = null;
    _lastRemoteCommand = -1;
    _commandId = 0;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _botTimer?.cancel();
    _link?.close();
    super.dispose();
  }
}
