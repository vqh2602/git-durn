import 'dart:io';
import 'dart:async';

import 'package:path/path.dart' as p;

import '../../../core/git/git_command.dart';
import '../../../core/git/git_error.dart';
import '../../../core/git/git_process_runner.dart';
import '../../../core/git/git_status.dart';
import '../../../core/git/git_status_parser.dart';
import '../../branches/data/git_branch_parser.dart';
import '../../branches/domain/branch_info.dart';
import '../../commits/data/git_log_parser.dart';
import '../../commits/domain/commit_node.dart';
import '../../conflicts/domain/repository_operation_state.dart';
import '../../diff/domain/git_diff.dart';
import '../../stash/domain/stash_entry.dart';
import '../domain/repository_session.dart';

class GitRepositoryService {
  const GitRepositoryService({
    required this.runner,
    this.statusParser = const GitStatusParser(),
    this.logParser = const GitLogParser(),
    this.branchParser = const GitBranchParser(),
  });

  final GitProcessRunner runner;
  final GitStatusParser statusParser;
  final GitLogParser logParser;
  final GitBranchParser branchParser;

  static final Map<String, Future<void>> _mutationTails =
      <String, Future<void>>{};

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

  Future<RepositorySession> initializeRepository(
    String path, {
    String initialBranch = 'main',
  }) async {
    await Directory(path).create(recursive: true);
    await runner.runChecked(
      GitCommand(
        arguments: <String>['init', '-b', initialBranch],
        workingDirectory: path,
        description: 'git init -b $initialBranch',
      ),
    );
    return openRepository(path);
  }

  Future<RepositorySession> cloneRepository({
    required String url,
    required String destination,
    int? depth,
    bool singleBranch = false,
    bool recurseSubmodules = false,
  }) async {
    final parent = p.dirname(destination);
    await Directory(parent).create(recursive: true);
    final arguments = <String>['clone', '--progress'];
    if (depth != null) arguments.addAll(<String>['--depth', '$depth']);
    if (singleBranch) arguments.add('--single-branch');
    if (recurseSubmodules) arguments.add('--recurse-submodules');
    arguments.addAll(<String>[url, destination]);
    await runner.runChecked(
      GitCommand(
        arguments: arguments,
        workingDirectory: parent,
        description: 'git clone ${_sanitizeUrl(url)}',
        timeout: const Duration(minutes: 30),
      ),
    );
    return openRepository(destination);
  }

  Future<String?> readPrimaryRemoteUrl(String rootPath) async {
    final remotes = await runner.run(
      GitCommand(
        arguments: const <String>['remote'],
        workingDirectory: rootPath,
        description: 'git remote',
      ),
    );
    if (!remotes.isSuccess) return null;
    final names = remotes.stdout
        .split('\n')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    final result = await runner.run(
      GitCommand(
        arguments: <String>['remote', 'get-url', names.first],
        workingDirectory: rootPath,
        description: 'git remote get-url ${names.first}',
      ),
    );
    return result.isSuccess ? result.stdout.trim() : null;
  }

  Future<GitDiff> readDiff(
    String rootPath, {
    required String path,
    required bool staged,
  }) async {
    final arguments = <String>[
      'diff',
      '--no-color',
      '--no-ext-diff',
      '--unified=5',
      if (staged) '--cached',
      '--',
      path,
    ];
    final result = await runner.runChecked(
      GitCommand(
        arguments: arguments,
        workingDirectory: rootPath,
        description: 'git diff${staged ? ' --cached' : ''} -- <path>',
      ),
    );
    var text = result.stdout;
    if (text.isEmpty && !staged) {
      final file = File(p.join(rootPath, path));
      if (file.existsSync()) {
        try {
          text = await file.readAsString();
        } on FileSystemException {
          text = 'Binary or unreadable untracked file.';
        }
      }
    }
    return GitDiff(
      path: path,
      text: text,
      isStaged: staged,
      isBinary:
          text.contains('Binary files') ||
          text.contains('GIT binary patch') ||
          text == 'Binary or unreadable untracked file.',
    );
  }

  Future<List<CommitNode>> readCommitLog(
    String rootPath, {
    int skip = 0,
    int limit = 200,
    String? revision,
  }) async {
    final format = <String>[
      '%H',
      '%h',
      '%P',
      '%an',
      '%ae',
      '%aI',
      '%s',
      '%b',
      '%D',
    ].join(GitLogParser.fieldSeparator);
    final result = await runner.run(
      GitCommand(
        arguments: <String>[
          'log',
          '--no-color',
          '--decorate=full',
          '--date=iso-strict',
          '--skip=$skip',
          '--max-count=$limit',
          '--format=$format${GitLogParser.recordSeparator}',
          ?revision,
        ],
        workingDirectory: rootPath,
        description: 'git log --max-count=$limit --skip=$skip',
      ),
    );
    if (!result.isSuccess) {
      final details = '${result.stderr}${result.stdout}'.toLowerCase();
      if (details.contains('does not have any commits yet') ||
          details.contains('unknown revision')) {
        return const <CommitNode>[];
      }
      throw GitError.fromResult(result);
    }
    return logParser.parse(result.stdout);
  }

  Future<List<BranchInfo>> readBranches(String rootPath) async {
    const format =
        '%(refname)%00%(refname:short)%00%(HEAD)%00'
        '%(upstream:short)%00%(objectname)%00%(subject)';
    final result = await runner.runChecked(
      GitCommand(
        arguments: const <String>[
          'for-each-ref',
          '--sort=refname',
          '--format=$format',
          'refs/heads',
          'refs/remotes',
        ],
        workingDirectory: rootPath,
        description: 'git for-each-ref branches',
      ),
    );
    return branchParser.parse(result.stdout);
  }

  Future<List<RemoteInfo>> readRemotes(String rootPath) async {
    final namesResult = await runner.runChecked(
      GitCommand(
        arguments: const <String>['remote'],
        workingDirectory: rootPath,
        description: 'git remote',
      ),
    );
    final remotes = <RemoteInfo>[];
    for (final name
        in namesResult.stdout
            .split('\n')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)) {
      final fetch = await runner.runChecked(
        GitCommand(
          arguments: <String>['remote', 'get-url', name],
          workingDirectory: rootPath,
          description: 'git remote get-url $name',
        ),
      );
      final push = await runner.runChecked(
        GitCommand(
          arguments: <String>['remote', 'get-url', '--push', name],
          workingDirectory: rootPath,
          description: 'git remote get-url --push $name',
        ),
      );
      remotes.add(
        RemoteInfo(
          name: name,
          fetchUrl: fetch.stdout.trim(),
          pushUrl: push.stdout.trim(),
        ),
      );
    }
    return List<RemoteInfo>.unmodifiable(remotes);
  }

  Future<List<String>> readTags(String rootPath) async {
    final result = await runner.runChecked(
      GitCommand(
        arguments: const <String>[
          'for-each-ref',
          '--sort=-creatordate',
          '--format=%(refname:short)',
          'refs/tags',
        ],
        workingDirectory: rootPath,
        description: 'git for-each-ref tags',
      ),
    );
    return List<String>.unmodifiable(
      result.stdout
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    );
  }

  Future<List<StashEntry>> readStashes(String rootPath) async {
    final result = await runner.runChecked(
      GitCommand(
        arguments: const <String>['stash', 'list', '--format=%gd%x00%H%x00%gs'],
        workingDirectory: rootPath,
        description: 'git stash list --format=<structured>',
      ),
    );
    final entries = <StashEntry>[];
    for (final line in result.stdout.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\x00');
      if (fields.length < 3) continue;
      entries.add(
        StashEntry(
          selector: fields[0],
          objectId: fields[1],
          message: fields.sublist(2).join('\x00'),
        ),
      );
    }
    return List<StashEntry>.unmodifiable(entries);
  }

  Future<RepositoryOperationState> readOperationState(String rootPath) async {
    final gitDirectoryResult = await runner.runChecked(
      GitCommand(
        arguments: const <String>['rev-parse', '--absolute-git-dir'],
        workingDirectory: rootPath,
        description: 'git rev-parse --absolute-git-dir',
      ),
    );
    final gitDirectory = gitDirectoryResult.stdout.trim();
    RepositoryOperationType type = RepositoryOperationType.none;
    if (Directory(p.join(gitDirectory, 'rebase-merge')).existsSync() ||
        Directory(p.join(gitDirectory, 'rebase-apply')).existsSync() ||
        File(p.join(gitDirectory, 'REBASE_HEAD')).existsSync()) {
      type = RepositoryOperationType.rebase;
    } else if (File(p.join(gitDirectory, 'MERGE_HEAD')).existsSync()) {
      type = RepositoryOperationType.merge;
    } else if (File(p.join(gitDirectory, 'CHERRY_PICK_HEAD')).existsSync()) {
      type = RepositoryOperationType.cherryPick;
    } else if (File(p.join(gitDirectory, 'REVERT_HEAD')).existsSync()) {
      type = RepositoryOperationType.revert;
    }
    return RepositoryOperationState(type: type, gitDirectory: gitDirectory);
  }

  Future<void> stagePath(String rootPath, String path) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['add', '--', path],
        workingDirectory: rootPath,
        description: 'git add -- <path>',
      ),
    ),
  );

  Future<void> stageAll(String rootPath) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: const <String>['add', '--all'],
        workingDirectory: rootPath,
        description: 'git add --all',
      ),
    ),
  );

  Future<void> unstagePath(String rootPath, String path) =>
      _mutate(rootPath, () async {
        final result = await runner.run(
          GitCommand(
            arguments: <String>['restore', '--staged', '--', path],
            workingDirectory: rootPath,
            description: 'git restore --staged -- <path>',
          ),
        );
        if (result.isSuccess) return;
        await runner.runChecked(
          GitCommand(
            arguments: <String>['rm', '--cached', '--', path],
            workingDirectory: rootPath,
            description: 'git rm --cached -- <path>',
          ),
        );
      });

  Future<void> unstageAll(String rootPath) => _mutate(rootPath, () async {
    final result = await runner.run(
      GitCommand(
        arguments: const <String>['restore', '--staged', '.'],
        workingDirectory: rootPath,
        description: 'git restore --staged .',
      ),
    );
    if (result.isSuccess) return;
    await runner.runChecked(
      GitCommand(
        arguments: const <String>['rm', '--cached', '-r', '.'],
        workingDirectory: rootPath,
        description: 'git rm --cached -r .',
      ),
    );
  });

  Future<String> createRecoverySnapshot(
    String rootPath, {
    required String path,
  }) async {
    final recoveryRoot = Directory(
      p.join(
        Directory.systemTemp.path,
        'git-desktop-recovery',
        _stableId(rootPath),
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await recoveryRoot.create(recursive: true);
    for (final staged in <bool>[false, true]) {
      final result = await runner.run(
        GitCommand(
          arguments: <String>[
            'diff',
            '--binary',
            if (staged) '--cached',
            '--',
            path,
          ],
          workingDirectory: rootPath,
          description:
              'git diff --binary${staged ? ' --cached' : ''} -- <path>',
        ),
      );
      await File(
        p.join(recoveryRoot.path, staged ? 'staged.patch' : 'unstaged.patch'),
      ).writeAsString(result.stdout);
    }
    final source = File(p.join(rootPath, path));
    if (source.existsSync() && await source.length() <= 10 * 1024 * 1024) {
      final backup = File(p.join(recoveryRoot.path, 'untracked-backup'));
      await source.copy(backup.path);
    }
    return recoveryRoot.path;
  }

  Future<String> discardPath(String rootPath, String path) async {
    final recoveryPath = await createRecoverySnapshot(rootPath, path: path);
    await _mutate(rootPath, () async {
      final tracked = await runner.run(
        GitCommand(
          arguments: <String>['ls-files', '--error-unmatch', '--', path],
          workingDirectory: rootPath,
          description: 'git ls-files --error-unmatch -- <path>',
        ),
      );
      if (tracked.isSuccess) {
        await runner.runChecked(
          GitCommand(
            arguments: <String>['restore', '--worktree', '--', path],
            workingDirectory: rootPath,
            description: 'git restore --worktree -- <path>',
          ),
        );
      } else {
        final file = File(p.join(rootPath, path));
        if (file.existsSync()) await file.delete();
      }
    });
    return recoveryPath;
  }

  Future<void> commit(
    String rootPath, {
    required String summary,
    String description = '',
    bool amend = false,
  }) async {
    if (summary.trim().isEmpty) {
      throw const GitError(
        kind: GitErrorKind.unknown,
        message: 'Commit summary cannot be empty.',
      );
    }
    final messageFile = File(
      p.join(
        Directory.systemTemp.path,
        'git-desktop-message-${DateTime.now().microsecondsSinceEpoch}.txt',
      ),
    );
    await messageFile.writeAsString(
      description.trim().isEmpty
          ? '${summary.trim()}\n'
          : '${summary.trim()}\n\n${description.trim()}\n',
      flush: true,
    );
    try {
      await _mutate(
        rootPath,
        () => runner.runChecked(
          GitCommand(
            arguments: <String>[
              'commit',
              if (amend) '--amend',
              '--file',
              messageFile.path,
            ],
            workingDirectory: rootPath,
            description:
                'git commit${amend ? ' --amend' : ''} --file <temporary>',
            timeout: const Duration(minutes: 5),
          ),
        ),
      );
    } finally {
      if (messageFile.existsSync()) await messageFile.delete();
    }
  }

  Future<void> fetch(String rootPath, {bool all = false, bool prune = false}) =>
      _mutate(
        rootPath,
        () => runner.runChecked(
          GitCommand(
            arguments: <String>[
              'fetch',
              if (all) '--all',
              if (prune) '--prune',
            ],
            workingDirectory: rootPath,
            description:
                'git fetch${all ? ' --all' : ''}${prune ? ' --prune' : ''}',
            timeout: const Duration(minutes: 10),
          ),
        ),
      );

  Future<void> pull(String rootPath, {String mode = 'merge'}) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>[
          'pull',
          if (mode == 'rebase') '--rebase',
          if (mode == 'ff-only') '--ff-only',
        ],
        workingDirectory: rootPath,
        description: 'git pull${mode == 'merge' ? '' : ' --$mode'}',
        timeout: const Duration(minutes: 10),
      ),
    ),
  );

  Future<void> push(
    String rootPath, {
    bool setUpstream = false,
    bool tags = false,
    bool forceWithLease = false,
  }) => _mutate(rootPath, () async {
    final arguments = <String>['push'];
    if (tags) arguments.add('--tags');
    if (forceWithLease) arguments.add('--force-with-lease');
    if (setUpstream) {
      final status = await readStatus(rootPath);
      arguments.addAll(<String>[
        '--set-upstream',
        'origin',
        status.branch.displayName,
      ]);
    }
    await runner.runChecked(
      GitCommand(
        arguments: arguments,
        workingDirectory: rootPath,
        description:
            'git push${tags ? ' --tags' : ''}'
            '${forceWithLease ? ' --force-with-lease' : ''}',
        timeout: const Duration(minutes: 10),
      ),
    );
  });

  Future<void> createBranch(
    String rootPath,
    String name, {
    String? startPoint,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['branch', name, ?startPoint],
        workingDirectory: rootPath,
        description:
            'git branch $name${startPoint == null ? '' : ' <start-point>'}',
      ),
    ),
  );

  Future<void> checkoutBranch(String rootPath, String name) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['checkout', name],
        workingDirectory: rootPath,
        description: 'git checkout $name',
      ),
    ),
  );

  Future<void> deleteBranch(
    String rootPath,
    String name, {
    bool force = false,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['branch', force ? '-D' : '-d', name],
        workingDirectory: rootPath,
        description: 'git branch ${force ? '-D' : '-d'} $name',
      ),
    ),
  );

  Future<void> mergeBranch(String rootPath, String name) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['merge', name],
        workingDirectory: rootPath,
        description: 'git merge $name',
        timeout: const Duration(minutes: 10),
      ),
    ),
  );

  Future<void> createTag(
    String rootPath,
    String name, {
    String? target,
    String? message,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>[
          'tag',
          if (message != null) ...<String>['-a', '-m', message],
          name,
          ?target,
        ],
        workingDirectory: rootPath,
        description: 'git tag${message == null ? '' : ' -a'} $name',
      ),
    ),
  );

  Future<void> createStash(
    String rootPath, {
    String? message,
    bool includeUntracked = false,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>[
          'stash',
          'push',
          if (includeUntracked) '--include-untracked',
          if (message != null && message.isNotEmpty) ...<String>[
            '--message',
            message,
          ],
        ],
        workingDirectory: rootPath,
        description:
            'git stash push${includeUntracked ? ' --include-untracked' : ''}',
      ),
    ),
  );

  Future<void> applyStash(
    String rootPath,
    String selector, {
    bool pop = false,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['stash', pop ? 'pop' : 'apply', selector],
        workingDirectory: rootPath,
        description: 'git stash ${pop ? 'pop' : 'apply'} $selector',
      ),
    ),
  );

  Future<void> dropStash(String rootPath, String selector) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['stash', 'drop', selector],
        workingDirectory: rootPath,
        description: 'git stash drop $selector',
      ),
    ),
  );

  Future<void> cherryPick(String rootPath, String commit) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['cherry-pick', commit],
        workingDirectory: rootPath,
        description: 'git cherry-pick <commit>',
      ),
    ),
  );

  Future<void> revertCommit(String rootPath, String commit) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['revert', '--no-edit', commit],
        workingDirectory: rootPath,
        description: 'git revert --no-edit <commit>',
      ),
    ),
  );

  Future<void> resetTo(
    String rootPath,
    String commit, {
    String mode = 'mixed',
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['reset', '--$mode', commit],
        workingDirectory: rootPath,
        description: 'git reset --$mode <commit>',
      ),
    ),
  );

  Future<void> rebaseOnto(String rootPath, String branch) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['rebase', branch],
        workingDirectory: rootPath,
        description: 'git rebase $branch',
        timeout: const Duration(minutes: 10),
      ),
    ),
  );

  Future<void> resolveConflictWithSide(
    String rootPath,
    String path, {
    required bool ours,
  }) => _mutate(rootPath, () async {
    await runner.runChecked(
      GitCommand(
        arguments: <String>[
          'checkout',
          ours ? '--ours' : '--theirs',
          '--',
          path,
        ],
        workingDirectory: rootPath,
        description: 'git checkout ${ours ? '--ours' : '--theirs'} -- <path>',
      ),
    );
    await runner.runChecked(
      GitCommand(
        arguments: <String>['add', '--', path],
        workingDirectory: rootPath,
        description: 'git add -- <resolved-path>',
      ),
    );
  });

  Future<void> markResolved(String rootPath, String path) =>
      stagePath(rootPath, path);

  Future<void> continueOperation(
    String rootPath,
  ) => _mutate(rootPath, () async {
    final state = await readOperationState(rootPath);
    final arguments = switch (state.type) {
      RepositoryOperationType.merge => const <String>['commit', '--no-edit'],
      RepositoryOperationType.rebase => const <String>['rebase', '--continue'],
      RepositoryOperationType.cherryPick => const <String>[
        'cherry-pick',
        '--continue',
      ],
      RepositoryOperationType.revert => const <String>['revert', '--continue'],
      RepositoryOperationType.none => throw const GitError(
        kind: GitErrorKind.unknown,
        message: 'No Git operation is currently in progress.',
      ),
    };
    await runner.runChecked(
      GitCommand(
        arguments: arguments,
        workingDirectory: rootPath,
        description: 'git ${arguments.join(' ')}',
      ),
    );
  });

  Future<void> abortOperation(String rootPath) => _mutate(rootPath, () async {
    final state = await readOperationState(rootPath);
    final arguments = switch (state.type) {
      RepositoryOperationType.merge => const <String>['merge', '--abort'],
      RepositoryOperationType.rebase => const <String>['rebase', '--abort'],
      RepositoryOperationType.cherryPick => const <String>[
        'cherry-pick',
        '--abort',
      ],
      RepositoryOperationType.revert => const <String>['revert', '--abort'],
      RepositoryOperationType.none => throw const GitError(
        kind: GitErrorKind.unknown,
        message: 'No Git operation is currently in progress.',
      ),
    };
    await runner.runChecked(
      GitCommand(
        arguments: arguments,
        workingDirectory: rootPath,
        description: 'git ${arguments.join(' ')}',
      ),
    );
  });

  Future<T> _mutate<T>(String rootPath, Future<T> Function() operation) async {
    final previous = _mutationTails[rootPath] ?? Future<void>.value();
    final completer = Completer<void>();
    _mutationTails[rootPath] = completer.future;
    await previous.catchError((Object _) {});
    try {
      return await operation();
    } finally {
      completer.complete();
      if (identical(_mutationTails[rootPath], completer.future)) {
        _mutationTails.remove(rootPath);
      }
    }
  }

  String _sanitizeUrl(String url) {
    return url.replaceFirstMapped(
      RegExp(r'^(https?://[^:/@]+):[^@]+@', caseSensitive: false),
      (match) => '${match.group(1)}:***@',
    );
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
