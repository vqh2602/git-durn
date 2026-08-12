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

  test(
    'executes staging, commits, branches, merge, tags, and stash with real Git',
    () async {
      final installation = await const GitExecutableLocator().locate();
      expect(
        installation,
        isNotNull,
        reason: 'Integration test requires system Git.',
      );
      final temporary = await Directory.systemTemp.createTemp(
        'git desktop operations ',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final init = await Process.run(installation!.executablePath, <String>[
        'init',
        '-b',
        'main',
        temporary.path,
      ]);
      expect(init.exitCode, 0, reason: init.stderr.toString());
      for (final entry in <(String, String)>[
        ('user.name', 'Git Desktop Test'),
        ('user.email', 'git-desktop@example.test'),
      ]) {
        final config = await Process.run(installation.executablePath, <String>[
          '-C',
          temporary.path,
          'config',
          entry.$1,
          entry.$2,
        ]);
        expect(config.exitCode, 0, reason: config.stderr.toString());
      }

      final service = GitRepositoryService(
        runner: GitProcessRunner(gitExecutable: installation.executablePath),
      );
      final tracked = File(
        '${temporary.path}${Platform.pathSeparator}tracked.txt',
      );
      await tracked.writeAsString('first\n');
      await service.stagePath(temporary.path, 'tracked.txt');
      await service.commit(temporary.path, summary: 'Initial commit');
      expect(await service.readCommitLog(temporary.path), hasLength(1));

      await service.createBranch(temporary.path, 'feature');
      await service.checkoutBranch(temporary.path, 'feature');
      await tracked.writeAsString('first\nfeature\n');
      await service.stageAll(temporary.path);
      await service.commit(temporary.path, summary: 'Add feature');
      await service.checkoutBranch(temporary.path, 'main');
      await service.mergeBranch(temporary.path, 'feature');
      expect(
        (await service.readCommitLog(temporary.path)).first.subject,
        'Add feature',
      );

      await service.createTag(temporary.path, 'v1.0.0');
      expect(await service.readTags(temporary.path), contains('v1.0.0'));
      await tracked.writeAsString('local stash\n');
      await service.createStash(temporary.path, message: 'test stash');
      final stashes = await service.readStashes(temporary.path);
      expect(stashes, hasLength(1));
      await service.applyStash(
        temporary.path,
        stashes.single.selector,
        pop: true,
      );
      expect((await service.readStatus(temporary.path)).isClean, isFalse);
    },
  );
}
