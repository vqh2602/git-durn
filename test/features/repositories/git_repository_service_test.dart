import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/core/git/git_executable_locator.dart';
import 'package:git_desktop_client/core/git/git_process_runner.dart';
import 'package:git_desktop_client/features/repositories/data/git_repository_service.dart';
import 'package:git_desktop_client/features/diff/domain/git_patch.dart';
import 'package:git_desktop_client/features/conflicts/domain/conflict_document.dart';

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

      final diff = await service.readDiff(
        temporary.path,
        path: 'tracked.txt',
        staged: false,
      );
      final patch = GitPatch.parse(diff.text);
      await service.applyPartialPatch(
        temporary.path,
        patch.patchForHunks(<int>[0]),
        staged: true,
      );
      expect((await service.readStatus(temporary.path)).stagedCount, 1);
      await service.commit(temporary.path, summary: 'Apply local change');

      await tracked.writeAsString('one\ntwo\nthree\n');
      await service.stageAll(temporary.path);
      await service.commit(temporary.path, summary: 'Prepare line staging');
      await tracked.writeAsString('one\nTWO\nthree\nextra\n');
      final linePatch = GitPatch.parse(
        (await service.readDiff(
          temporary.path,
          path: 'tracked.txt',
          staged: false,
        )).text,
      );
      final selectedIndexes = <int>{};
      for (var index = 0; index < linePatch.hunks.single.lines.length; index++) {
        final line = linePatch.hunks.single.lines[index];
        if (line == '-two' || line == '+TWO') selectedIndexes.add(index);
      }
      await service.applyPartialPatch(
        temporary.path,
        linePatch.patchForLines(<int, Set<int>>{0: selectedIndexes}),
        staged: true,
      );
      final stagedLineDiff = await service.readDiff(
        temporary.path,
        path: 'tracked.txt',
        staged: true,
      );
      final unstagedLineDiff = await service.readDiff(
        temporary.path,
        path: 'tracked.txt',
        staged: false,
      );
      expect(stagedLineDiff.text, contains('+TWO'));
      expect(stagedLineDiff.text, isNot(contains('+extra')));
      expect(unstagedLineDiff.text, contains('+extra'));
      await service.stageAll(temporary.path);
      await service.commit(temporary.path, summary: 'Finish line staging');

      expect(await service.readReflog(temporary.path), isNotEmpty);
      expect(
        await service.readBlame(temporary.path, 'tracked.txt'),
        isNotEmpty,
      );
      expect(
        await service.readFileHistory(temporary.path, 'tracked.txt'),
        isNotEmpty,
      );

      final worktreePath =
          '${temporary.parent.path}${Platform.pathSeparator}worktree-${temporary.path.hashCode}';
      addTearDown(() async {
        final directory = Directory(worktreePath);
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      await service.createWorktree(
        temporary.path,
        path: worktreePath,
        branch: 'feature',
      );
      expect(
        (await service.readWorktrees(temporary.path)).any(
          (item) => item.path.endsWith('worktree-${temporary.path.hashCode}'),
        ),
        isTrue,
      );
      await service.removeWorktree(temporary.path, worktreePath);
      expect(await service.readSubmodules(temporary.path), isEmpty);
    },
  );

  test('loads and resolves a real three-way merge conflict', () async {
    final installation = await const GitExecutableLocator().locate();
    expect(installation, isNotNull);
    final temporary = await Directory.systemTemp.createTemp(
      'git desktop conflict ',
    );
    addTearDown(() => temporary.delete(recursive: true));
    Future<void> git(List<String> arguments) async {
      final result = await Process.run(installation!.executablePath, <String>[
        '-C',
        temporary.path,
        ...arguments,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }

    await git(<String>['init', '-b', 'main']);
    await git(<String>['config', 'user.name', 'Conflict Test']);
    await git(<String>['config', 'user.email', 'conflict@example.test']);
    final file = File('${temporary.path}${Platform.pathSeparator}conflict.txt');
    await file.writeAsString('before\nbase\nafter\n');
    await git(<String>['add', 'conflict.txt']);
    await git(<String>['commit', '-m', 'base']);
    await git(<String>['checkout', '-b', 'feature']);
    await file.writeAsString('before\nfeature\nafter\n');
    await git(<String>['commit', '-am', 'feature']);
    await git(<String>['checkout', 'main']);
    await file.writeAsString('before\nmain\nafter\n');
    await git(<String>['commit', '-am', 'main']);

    final service = GitRepositoryService(
      runner: GitProcessRunner(gitExecutable: installation!.executablePath),
    );
    await expectLater(
      service.mergeBranch(temporary.path, 'feature'),
      throwsA(isNotNull),
    );
    final status = await service.readStatus(temporary.path);
    expect(status.files.single.isConflicted, isTrue);
    final document = await service.readConflictDocument(
      temporary.path,
      'conflict.txt',
    );
    expect(document.base, contains('base'));
    expect(document.ours, contains('main'));
    expect(document.theirs, contains('feature'));
    expect(document.blocks, hasLength(1));

    final resolved = ConflictDocument.resolveBlock(
      document.result,
      document.blocks.single,
      ConflictChoice.both,
    );
    await service.writeConflictResult(temporary.path, 'conflict.txt', resolved);
    await service.markResolved(temporary.path, 'conflict.txt');
    await service.continueOperation(temporary.path);
    expect((await service.readStatus(temporary.path)).isClean, isTrue);
  });
}
