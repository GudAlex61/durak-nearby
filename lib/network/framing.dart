import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Conservative ATT payload: 20 bytes works without negotiating a larger MTU.
/// Data [D0,id:2,index:2,total:2,payload<=13]; ack [A0,id:2].
/// One ordered message at a time in each direction. Duplicate delivery is ignored.
class ReliableChannel {
  final Future<void> Function(Uint8List) _writeRaw;
  Future<void> _frameWrites = Future.value();
  final void Function(Map<String, dynamic>) onMessage;
  final Duration ackTimeout;
  Future<void> _queue = Future.value();
  Completer<void>? _ack;
  int _nextId = 1;
  int? _waitingId;
  int? _incomingId;
  int _expected = 0;
  int _total = 0;
  final List<int> _buffer = [];
  final Set<int> _delivered = {};
  bool _closed = false;

  ReliableChannel({
    required Future<void> Function(Uint8List) write,
    required this.onMessage,
    this.ackTimeout = const Duration(seconds: 5),
  }) : _writeRaw = write;

  // ATT operations, including ACK frames, must never overlap on one GATT link.
  Future<void> write(Uint8List value) {
    final job = _frameWrites.then((_) {
      if (_closed) {
        throw StateError('Соединение закрыто');
      }
      return _writeRaw(value).timeout(const Duration(seconds: 5));
    });
    _frameWrites = job.catchError((Object _) {});
    return job;
  }

  Future<void> send(Map<String, dynamic> message) {
    final job = _queue.then((_) => _send(message));
    _queue = job.catchError((Object _) {});
    return job;
  }

  Future<void> _send(Map<String, dynamic> message) async {
    if (_closed) throw StateError('Соединение закрыто');
    final bytes = utf8.encode(jsonEncode(message));
    if (bytes.length > 16384) throw ArgumentError('Сообщение слишком большое');
    final id = _nextId++;
    // Reset channel before reusing IDs; a game cannot realistically reach 65k messages.
    if (id > 65535) throw StateError('Переподключитесь к столу');
    final count = (bytes.length / 13).ceil();
    _waitingId = id;
    _ack = Completer<void>();
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        for (var index = 0; index < count; index++) {
          if (_closed) throw StateError('Соединение закрыто');
          final end = (index + 1) * 13;
          await write(
            Uint8List.fromList([
              0xd0,
              id >> 8,
              id & 255,
              index >> 8,
              index & 255,
              count >> 8,
              count & 255,
              ...bytes.sublist(
                index * 13,
                end > bytes.length ? bytes.length : end,
              ),
            ]),
          );
        }
        try {
          await _ack!.future.timeout(ackTimeout);
          if (_closed) throw StateError('Соединение закрыто');
          return;
        } on TimeoutException {
          if (attempt == 2) rethrow;
        }
      }
    } finally {
      _waitingId = null;
      _ack = null;
    }
  }

  Future<void> receive(Uint8List frame) async {
    if (_closed || frame.length < 3 || frame.length > 20) return;
    final id = (frame[1] << 8) | frame[2];
    if (frame[0] == 0xa0 && frame.length == 3) {
      if (id == _waitingId && _ack != null && !_ack!.isCompleted) {
        _ack!.complete();
      }
      return;
    }
    if (frame[0] != 0xd0 || frame.length < 8) return;
    final index = (frame[3] << 8) | frame[4];
    final total = (frame[5] << 8) | frame[6];
    if (total < 1 || total > 1261 || index >= total) return;
    if (_delivered.contains(id)) {
      if (index == total - 1) await _sendAck(id);
      return;
    }
    if (index == 0) {
      _incomingId = id;
      _expected = 0;
      _total = total;
      _buffer.clear();
    }
    if (_incomingId != id || index != _expected || _total != total) return;
    _buffer.addAll(frame.sublist(7));
    _expected++;
    if (_buffer.length > 16384) {
      _buffer.clear();
      _incomingId = null;
      return;
    }
    if (_expected == total) {
      Map<String, dynamic> decoded;
      try {
        decoded = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(_buffer)) as Map,
        );
      } catch (_) {
        _incomingId = null;
        _buffer.clear();
        return;
      }
      _delivered.add(id);
      if (_delivered.length > 128) _delivered.remove(_delivered.first);
      _incomingId = null;
      _buffer.clear();
      await _sendAck(id);
      onMessage(decoded);
    }
  }

  Future<void> _sendAck(int id) =>
      write(Uint8List.fromList([0xa0, id >> 8, id & 255]));
  void close() {
    _closed = true;
    // Complete an outstanding wait promptly; the caller also checks _closed.
    if (_ack != null && !_ack!.isCompleted) _ack!.complete();
  }
}
