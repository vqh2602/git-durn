import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../../core/terminal/pty_terminal_backend.dart';
import '../../../core/terminal/terminal_backend.dart';

class TerminalSession {
  TerminalSession({
    required this.id,
    required this.title,
    required this.terminal,
    required this.backend,
    required this.outputSubscription,
  });

  final String id;
  String title;
  final Terminal terminal;
  final TerminalBackend backend;
  final StreamSubscription<String> outputSubscription;

  void dispose() {
    outputSubscription.cancel();
    backend.kill();
  }
}

class TerminalManager extends ChangeNotifier {
  TerminalManager({required this.repositoryRoot}) {
    createSession();
  }

  final String repositoryRoot;
  final List<TerminalSession> _sessions = <TerminalSession>[];
  String? _selectedId;
  String? error;

  List<TerminalSession> get sessions =>
      List<TerminalSession>.unmodifiable(_sessions);

  TerminalSession? get selected {
    for (final session in _sessions) {
      if (session.id == _selectedId) return session;
    }
    return null;
  }

  void createSession() {
    try {
      final backend = PtyTerminalBackend();
      final terminal = Terminal(maxLines: 10000);
      final configuration = _configuration();
      backend.start(configuration);
      final subscription = backend.output
          .transform(utf8.decoder)
          .listen(
            terminal.write,
            onError: (Object caught) {
              terminal.write('\r\nTerminal error: $caught\r\n');
            },
          );
      terminal.onOutput = (data) => backend.write(utf8.encode(data));
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        backend.resize(rows: height, columns: width);
      };
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      _sessions.add(
        TerminalSession(
          id: id,
          title: Platform.isWindows
              ? 'PowerShell'
              : _shellName(configuration.executable),
          terminal: terminal,
          backend: backend,
          outputSubscription: subscription,
        ),
      );
      _selectedId = id;
      error = null;
      notifyListeners();
    } on Object catch (caught) {
      error = caught.toString();
      notifyListeners();
    }
  }

  void select(String id) {
    if (_sessions.any((session) => session.id == id)) {
      _selectedId = id;
      notifyListeners();
    }
  }

  void close(String id) {
    final index = _sessions.indexWhere((session) => session.id == id);
    if (index < 0) return;
    _sessions[index].dispose();
    _sessions.removeAt(index);
    if (_selectedId == id) {
      _selectedId = _sessions.isEmpty
          ? null
          : _sessions[index.clamp(0, _sessions.length - 1)].id;
    }
    notifyListeners();
  }

  void rename(String id, String title) {
    final session = _sessions.where((item) => item.id == id).firstOrNull;
    if (session == null || title.trim().isEmpty) return;
    session.title = title.trim();
    notifyListeners();
  }

  TerminalLaunchConfiguration _configuration() {
    if (Platform.isWindows) {
      final shell = Platform.environment['COMSPEC'] ?? 'powershell.exe';
      return TerminalLaunchConfiguration(
        executable: shell,
        arguments: shell.toLowerCase().contains('powershell')
            ? const <String>['-NoLogo']
            : const <String>[],
        workingDirectory: repositoryRoot,
      );
    }
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    return TerminalLaunchConfiguration(
      executable: shell,
      arguments: const <String>['-l'],
      workingDirectory: repositoryRoot,
    );
  }

  String _shellName(String executable) {
    final normalized = executable.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }
}
