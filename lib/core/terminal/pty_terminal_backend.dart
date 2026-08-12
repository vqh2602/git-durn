import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';

import 'terminal_backend.dart';

class PtyTerminalBackend implements TerminalBackend {
  final _outputController = StreamController<List<int>>.broadcast();
  final _exitCodeCompleter = Completer<int>();
  Pty? _pty;
  StreamSubscription<Uint8List>? _subscription;

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  void start(TerminalLaunchConfiguration configuration) {
    if (_pty != null) throw StateError('Terminal backend is already running.');
    final pty = Pty.start(
      configuration.executable,
      arguments: configuration.arguments,
      workingDirectory: configuration.workingDirectory,
      environment: configuration.environment,
      rows: configuration.rows,
      columns: configuration.columns,
    );
    _pty = pty;
    _subscription = pty.output.listen(
      _outputController.add,
      onError: _outputController.addError,
      onDone: _outputController.close,
    );
    pty.exitCode.then((value) {
      if (!_exitCodeCompleter.isCompleted) _exitCodeCompleter.complete(value);
    });
  }

  @override
  void write(List<int> data) => _pty?.write(Uint8List.fromList(data));

  @override
  void resize({required int rows, required int columns}) {
    _pty?.resize(rows, columns);
  }

  @override
  void kill() {
    _pty?.kill();
    _subscription?.cancel();
  }
}
