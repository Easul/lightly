import 'dart:async';
import 'dart:typed_data';

class BufferedStreamReader {
  BufferedStreamReader(this._stream) {
    _controller = StreamController<Uint8List>(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final Stream<Uint8List> _stream;
  StreamSubscription<Uint8List>? _subscription;
  late final StreamController<Uint8List> _controller;
  final List<int> _buffer = [];
  final _pendingCompleterQueue = <Completer<void>>[];
  bool _isDone = false;
  Object? _error;
  bool _isClosed = false;
  bool _forwardingStarted = false;

  Stream<Uint8List> get stream => _controller.stream;

  void _onListen() {
    if (!_forwardingStarted) {
      _forwardingStarted = true;
      _startForwarding();
    }
  }

  void _onCancel() {
    unawaited(close());
  }

  void _startForwarding() {
    if (_buffer.isNotEmpty) {
      _controller.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }

    if (_isDone) {
      _controller.close();
      return;
    }

    if (_error != null) {
      _controller.addError(_error!);
      _controller.close();
      return;
    }

    if (_subscription != null) {
      _subscription!
        ..onData((data) {
          _controller.add(data);
        })
        ..onError((e, st) {
          _controller.addError(e, st);
        })
        ..onDone(() {
          _controller.close();
        });
    }
  }

  void start() {
    _subscription = _stream.listen(
      (data) {
        if (_forwardingStarted) {
          _controller.add(data);
        } else {
          _buffer.addAll(data);
        }
        _flushPendingCompleters();
      },
      onError: (e, st) {
        _error = e;
        if (_forwardingStarted) {
          _controller.addError(e, st);
        }
        _flushPendingCompleters();
      },
      onDone: () {
        _isDone = true;
        if (_forwardingStarted) {
          _controller.close();
        }
        _flushPendingCompleters();
      },
      cancelOnError: true,
    );
  }

  void _flushPendingCompleters() {
    while (_pendingCompleterQueue.isNotEmpty) {
      final completer = _pendingCompleterQueue.removeAt(0);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> _waitForData(int requiredBytes) async {
    while (_buffer.length < requiredBytes && !_isDone && _error == null) {
      final completer = Completer<void>();
      _pendingCompleterQueue.add(completer);
      await completer.future;
    }
  }

  Future<int> readByte() async {
    await _waitForData(1);
    if (_buffer.isEmpty) {
      throw Exception('Unexpected end of stream while reading byte');
    }
    return _buffer.removeAt(0);
  }

  void pushBack(int byte) {
    _buffer.insert(0, byte);
  }

  Future<Uint8List> readBytes(int count) async {
    await _waitForData(count);
    if (_buffer.length < count) {
      throw Exception('Unexpected end of stream while reading $count bytes');
    }
    final result = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }

  Uint8List takeBuffered() {
    final result = Uint8List.fromList(_buffer);
    _buffer.clear();
    return result;
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _subscription?.cancel();
    _subscription = null;
  }
}
