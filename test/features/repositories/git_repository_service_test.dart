import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/core/git/git_executable_locator.dart';
import 'package:git_desktop_client/core/git/git_process_runner.dart';
import 'package:git_desktop_client/features/repositories/data/git_repository_service.dart';

void main() {
  test('opens a real repository and reads machine-readable status', () async {
    final installation = await const GitExecutableLocator().locate();
    expect(
      installation,
      isNotNull,
      reason: 'Integration test requires system Git.',
    );

    final temporary = await Directory.systemTemp.createTemp(
      'git desktop ü space ',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final repository = Directory(
      '${temporary.path}${Platform.pathSeparator}repo space',
    );
    await repository.create();
    final init = await Process.run(installation!.executablePath, <String>[
      'init',
      '-b',
      'main',
      repository.path,
    ]);
    expect(init.exitCode, 0, reason: init.stderr.toString());
    await File(
      '${repository.path}${Platform.pathSeparator}hello world.txt',
    ).writeAsString('hello\n');

    final service = GitRepositoryService(
      runner: GitProcessRunner(gitExecutable: installation.executablePath),
    );
    final session = await service.openRepository(repository.path);
    final status = await service.readStatus(session.rootPath);

    expect(session.name, 'repo space');
    expect(session.rootPath, await repository.resolveSymbolicLinks());
    expect(status.branch.head, 'main');
    expect(status.files.single.path, 'hello world.txt');
    expect(status.files.single.isUntracked, isTrue);
  });
}
