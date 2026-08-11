import 'dart:io';

import '../../../core/git/git_command.dart';
import '../../../core/git/git_process_runner.dart';
import '../../../core/git/git_status.dart';
import '../../../core/git/git_status_parser.dart';
import '../domain/repository_session.dart';

class GitRepositoryService {
  const GitRepositoryService({
    required this.runner,
    this.statusParser = const GitStatusParser(),
  });

  final GitProcessRunner runner;
  final GitStatusParser statusParser;

  Future<RepositorySession> openRepository(String selectedPath) async {
    final rootResult = await runner.runChecked(
      GitCommand(
        arguments: const <String>['rev-parse', '--show-toplevel'],
        workingDirectory: selectedPath,
        description: 'git rev-parse --show-toplevel',
      ),
    );
    final rootPath = rootResult.stdout.trim();

    final gitDirectoryResult = await runner.runChecked(
      GitCommand(
        arguments: const <String>['rev-parse', '--absolute-git-dir'],
        workingDirectory: rootPath,
        description: 'git rev-parse --absolute-git-dir',
      ),
    );

    await readStatus(rootPath);
    return RepositorySession(
      id: _stableId(rootPath),
      name: _basename(rootPath),
      rootPath: rootPath,
      gitDirectory: gitDirectoryResult.stdout.trim(),
      openedAt: DateTime.now(),
    );
  }

  Future<RepositoryStatus> readStatus(String rootPath) async {
    final result = await runner.runChecked(
      GitCommand(
        arguments: const <String>['status', '--porcelain=v2', '-z', '--branch'],
        workingDirectory: rootPath,
        description: 'git status --porcelain=v2 -z --branch',
      ),
    );
    return statusParser.parse(result.stdout);
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    return segments.isEmpty ? path : segments.last;
  }

  String _stableId(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  static bool directoryExists(String path) => Directory(path).existsSync();
}
