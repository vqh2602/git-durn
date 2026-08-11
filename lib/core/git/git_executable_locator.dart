import 'dart:async';
import 'dart:convert';
import 'dart:io';

class GitInstallation {
  const GitInstallation({required this.executablePath, required this.version});

  final String executablePath;
  final String version;
}

class GitExecutableLocator {
  const GitExecutableLocator({this.customExecutable});

  final String? customExecutable;

  Future<GitInstallation?> locate() async {
    for (final candidate in _candidates()) {
      final installation = await _probe(candidate);
      if (installation != null) return installation;
    }
    return null;
  }

  Iterable<String> _candidates() sync* {
    final seen = <String>{};
    void add(String? value) {
      if (value != null && value.trim().isNotEmpty) seen.add(value);
    }

    add(customExecutable);
    if (Platform.isMacOS) {
      add('/usr/bin/git');
      add('/usr/local/bin/git');
      add('/opt/homebrew/bin/git');
    } else if (Platform.isWindows) {
      final programFiles = Platform.environment['ProgramFiles'];
      final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
      final localAppData = Platform.environment['LOCALAPPDATA'];
      add(programFiles == null ? null : '$programFiles\\Git\\cmd\\git.exe');
      add(
        programFilesX86 == null ? null : '$programFilesX86\\Git\\cmd\\git.exe',
      );
      add(
        localAppData == null
            ? null
            : '$localAppData\\Programs\\Git\\cmd\\git.exe',
      );
    }
    add('git');
    yield* seen;
  }

  Future<GitInstallation?> _probe(String candidate) async {
    if (_isAbsolute(candidate) && !File(candidate).existsSync()) return null;

    try {
      final process = await Process.start(candidate, const <String>[
        '--version',
      ], runInShell: false);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5),
      );
      final output = '${await stdoutFuture}${await stderrFuture}'.trim();
      if (exitCode != 0 || !output.startsWith('git version ')) return null;
      return GitInstallation(
        executablePath: candidate,
        version: output.substring('git version '.length).trim(),
      );
    } on Object {
      return null;
    }
  }

  bool _isAbsolute(String path) {
    if (Platform.isWindows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
          path.startsWith(r'\\');
    }
    return path.startsWith('/');
  }
}
