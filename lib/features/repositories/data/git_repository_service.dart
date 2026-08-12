import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../../core/git/git_command.dart';
import '../../../core/git/git_error.dart';
import '../../../core/git/git_process_runner.dart';
import '../../../core/git/git_status.dart';
import '../../../core/git/git_status_parser.dart';
import '../../../core/ai/ai_models.dart';
import '../../../core/security/secret_redactor.dart';
import '../../branches/data/git_branch_parser.dart';
import '../../branches/domain/branch_info.dart';
import '../../advanced_repository/domain/repository_tools.dart';
import '../../commits/data/git_log_parser.dart';
import '../../commits/domain/commit_node.dart';
import '../../conflicts/domain/repository_operation_state.dart';
import '../../diff/domain/git_diff.dart';
import '../../conflicts/domain/conflict_document.dart';
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

  Future<CommitAiContext> readCommitAiContext(String rootPath) async {
    final status = await readStatus(rootPath);
    final namesResult = await runner.runChecked(
      GitCommand(
        arguments: const <String>['diff', '--cached', '--name-only', '-z'],
        workingDirectory: rootPath,
        description: 'git diff --cached --name-only -z',
      ),
    );
    final stagedFiles = namesResult.stdout
        .split('\x00')
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (stagedFiles.isEmpty) {
      throw const GitError(
        kind: GitErrorKind.unknown,
        message: 'Stage changes before generating a commit message.',
      );
    }
    final ignored = stagedFiles.where(
      (path) => RegExp(
        r'(?:^|/)(?:build|dist|vendor|generated)/|\.(?:lock|min\.js|min\.css)$',
        caseSensitive: false,
      ).hasMatch(path),
    );
    final included = stagedFiles.toSet()..removeAll(ignored);
    final diffResult = await runner.runChecked(
      GitCommand(
        arguments: <String>[
          'diff',
          '--cached',
          '--no-color',
          '--no-ext-diff',
          '--stat',
          '--patch',
          if (included.isNotEmpty) ...<String>['--', ...included],
        ],
        workingDirectory: rootPath,
        description: 'git diff --cached --stat --patch <AI-context>',
      ),
    );
    var diff = diffResult.stdout;
    if (diff.length > 60000) {
      diff = '${diff.substring(0, 60000)}\n<DIFF_TRUNCATED>';
    }
    final redaction = const SecretRedactor().redact(diff);
    final recent = await runner.run(
      GitCommand(
        arguments: const <String>['log', '-10', '--format=%s'],
        workingDirectory: rootPath,
        description: 'git log -10 --format=%s',
      ),
    );
    return CommitAiContext(
      branch: status.branch.displayName,
      stagedFiles: stagedFiles,
      diff: redaction.text,
      recentSubjects: recent.isSuccess
          ? recent.stdout.split('\n').where((line) => line.isNotEmpty).toList()
          : const <String>[],
      omittedFiles: ignored.length,
      redactedSecrets: redaction.redactedCount,
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

  Future<void> applyPartialPatch(
    String rootPath,
    String patch, {
    required bool staged,
    bool reverse = false,
  }) => _mutate(rootPath, () async {
    if (patch.trim().isEmpty) {
      throw const GitError(
        kind: GitErrorKind.unknown,
        message: 'Select at least one changed line or hunk.',
      );
    }
    await runner.runChecked(
      GitCommand(
        arguments: <String>[
          'apply',
          '--unidiff-zero',
          '--whitespace=nowarn',
          if (staged) '--cached',
          if (reverse) '--reverse',
          '-',
        ],
        workingDirectory: rootPath,
        description:
            'git apply${staged ? ' --cached' : ''}${reverse ? ' --reverse' : ''} <selected-patch>',
        stdin: utf8.encode(patch),
      ),
    );
  });

  Future<ConflictDocument> readConflictDocument(
    String rootPath,
    String path,
  ) async {
    Future<String> readStage(int stage) async {
      final result = await runner.run(
        GitCommand(
          arguments: <String>['show', ':$stage:$path'],
          workingDirectory: rootPath,
          description: 'git show :$stage:<conflicted-path>',
        ),
      );
      return result.isSuccess ? result.stdout : '';
    }

    final file = File(p.join(rootPath, path));
    final bytes = file.existsSync() ? await file.readAsBytes() : <int>[];
    final isBinary = bytes.take(8192).contains(0);
    final result = isBinary ? '' : utf8.decode(bytes, allowMalformed: true);
    final values = await Future.wait(<Future<String>>[
      readStage(1),
      readStage(2),
      readStage(3),
    ]);
    return ConflictDocument(
      path: path,
      base: values[0],
      ours: values[1],
      theirs: values[2],
      result: result,
      blocks: isBinary
          ? const <ConflictBlock>[]
          : ConflictDocument.parseBlocks(result),
      isBinary: isBinary,
    );
  }

  Future<void> writeConflictResult(
    String rootPath,
    String path,
    String content,
  ) => _mutate(rootPath, () async {
    final root = p.normalize(p.absolute(rootPath));
    final target = p.normalize(p.absolute(p.join(root, path)));
    if (!p.isWithin(root, target)) {
      throw const GitError(
        kind: GitErrorKind.unknown,
        message: 'Conflict path is outside the repository.',
      );
    }
    await File(target).writeAsString(content, flush: true);
  });

  Future<List<WorktreeInfo>> readWorktrees(String rootPath) async {
    final result = await runner.runChecked(
      GitCommand(
        arguments: const <String>['worktree', 'list', '--porcelain'],
        workingDirectory: rootPath,
        description: 'git worktree list --porcelain',
      ),
    );
    final output = <WorktreeInfo>[];
    for (final record in result.stdout.trim().split(RegExp(r'\n\s*\n'))) {
      if (record.trim().isEmpty) continue;
      final values = <String, String>{};
      final flags = <String>{};
      for (final line in record.split('\n')) {
        final space = line.indexOf(' ');
        if (space == -1) {
          flags.add(line.trim());
        } else {
          values[line.substring(0, space)] = line.substring(space + 1);
        }
      }
      output.add(
        WorktreeInfo(
          path: values['worktree'] ?? '',
          head: values['HEAD'] ?? '',
          branch: values['branch']?.replaceFirst('refs/heads/', ''),
          isBare: flags.contains('bare'),
          isDetached: flags.contains('detached'),
          isLocked: flags.contains('locked') || values.containsKey('locked'),
          lockReason: values['locked'],
        ),
      );
    }
    return List<WorktreeInfo>.unmodifiable(output);
  }

  Future<void> createWorktree(
    String rootPath, {
    required String path,
    required String branch,
    bool createBranch = false,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>[
          'worktree',
          'add',
          if (createBranch) ...<String>['-b', branch],
          path,
          if (!createBranch) branch,
        ],
        workingDirectory: rootPath,
        description:
            'git worktree add${createBranch ? ' -b <branch>' : ''} <path>',
      ),
    ),
  );

  Future<void> setWorktreeLock(
    String rootPath,
    String path, {
    required bool locked,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['worktree', locked ? 'lock' : 'unlock', path],
        workingDirectory: rootPath,
        description: 'git worktree ${locked ? 'lock' : 'unlock'} <path>',
      ),
    ),
  );

  Future<void> removeWorktree(String rootPath, String path) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>['worktree', 'remove', path],
        workingDirectory: rootPath,
        description: 'git worktree remove <path>',
      ),
    ),
  );

  Future<void> pruneWorktrees(String rootPath) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: const <String>['worktree', 'prune'],
        workingDirectory: rootPath,
        description: 'git worktree prune',
      ),
    ),
  );

  Future<List<SubmoduleInfo>> readSubmodules(String rootPath) async {
    final result = await runner.run(
      GitCommand(
        arguments: const <String>['submodule', 'status', '--recursive'],
        workingDirectory: rootPath,
        description: 'git submodule status --recursive',
      ),
    );
    if (!result.isSuccess) return const <SubmoduleInfo>[];
    final entries = <SubmoduleInfo>[];
    for (final line in result.stdout.split('\n')) {
      if (line.length < 42) continue;
      final stateCharacter = line[0];
      final remainder = line.substring(42);
      final descriptionStart = remainder.lastIndexOf(' (');
      final path = descriptionStart < 0
          ? remainder.trim()
          : remainder.substring(0, descriptionStart).trim();
      entries.add(
        SubmoduleInfo(
          path: path,
          commit: line.substring(1, 41),
          state: switch (stateCharacter) {
            '-' => 'not initialized',
            '+' => 'different commit',
            'U' => 'conflicted',
            _ => 'ready',
          },
          description: descriptionStart < 0
              ? null
              : remainder.substring(descriptionStart + 2).replaceFirst(')', ''),
        ),
      );
    }
    return List<SubmoduleInfo>.unmodifiable(entries);
  }

  Future<void> updateSubmodules(
    String rootPath, {
    bool initialize = true,
    bool recursive = true,
  }) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: <String>[
          'submodule',
          'update',
          if (initialize) '--init',
          if (recursive) '--recursive',
        ],
        workingDirectory: rootPath,
        description:
            'git submodule update${initialize ? ' --init' : ''}${recursive ? ' --recursive' : ''}',
      ),
    ),
  );

  Future<void> syncSubmodules(String rootPath) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: const <String>['submodule', 'sync', '--recursive'],
        workingDirectory: rootPath,
        description: 'git submodule sync --recursive',
      ),
    ),
  );

  Future<LfsStatus> readLfsStatus(String rootPath) async {
    final version = await runner.run(
      GitCommand(
        arguments: const <String>['lfs', 'version'],
        workingDirectory: rootPath,
        description: 'git lfs version',
      ),
    );
    if (!version.isSuccess) {
      return const LfsStatus(isInstalled: false, patterns: <String>[]);
    }
    final attributes = File(p.join(rootPath, '.gitattributes'));
    final patterns = <String>[];
    if (attributes.existsSync()) {
      for (final line in await attributes.readAsLines()) {
        if (line.contains('filter=lfs')) patterns.add(line.split(' ').first);
      }
    }
    return LfsStatus(
      isInstalled: true,
      patterns: List<String>.unmodifiable(patterns),
    );
  }

  Future<void> lfsAction(String rootPath, String action, {String? pattern}) =>
      _mutate(
        rootPath,
        () => runner.runChecked(
          GitCommand(
            arguments: <String>['lfs', action, ?pattern],
            workingDirectory: rootPath,
            description:
                'git lfs $action${pattern == null ? '' : ' <pattern>'}',
            timeout: const Duration(minutes: 30),
          ),
        ),
      );

  Future<List<ReflogEntry>> readReflog(
    String rootPath, {
    int limit = 200,
  }) async {
    const separator = '\x1f';
    final result = await runner.runChecked(
      GitCommand(
        arguments: <String>[
          'reflog',
          'show',
          '--date=iso-strict',
          '--max-count=$limit',
          '--format=%gD$separator%H$separator%h$separator%gs$separator%cI',
        ],
        workingDirectory: rootPath,
        description: 'git reflog show --max-count=$limit --format=<structured>',
      ),
    );
    return List<ReflogEntry>.unmodifiable(
      result.stdout.split('\n').where((line) => line.isNotEmpty).map((line) {
        final fields = line.split(separator);
        return ReflogEntry(
          selector: fields[0],
          hash: fields.length > 1 ? fields[1] : '',
          shortHash: fields.length > 2 ? fields[2] : '',
          subject: fields.length > 3 ? fields[3] : '',
          date: fields.length > 4 ? DateTime.tryParse(fields[4]) : null,
        );
      }),
    );
  }

  Future<List<BlameLine>> readBlame(
    String rootPath,
    String path, {
    bool ignoreWhitespace = false,
  }) async {
    final result = await runner.runChecked(
      GitCommand(
        arguments: <String>[
          'blame',
          '--line-porcelain',
          if (ignoreWhitespace) '-w',
          '--',
          path,
        ],
        workingDirectory: rootPath,
        description:
            'git blame --line-porcelain${ignoreWhitespace ? ' -w' : ''} -- <path>',
      ),
    );
    final authors = <String, String>{};
    final times = <String, DateTime?>{};
    final output = <BlameLine>[];
    String hash = '';
    var finalLine = 0;
    for (final line in result.stdout.split('\n')) {
      final header = RegExp(
        r'^([0-9a-f^]{40,41}) \d+ (\d+)(?: \d+)?$',
      ).firstMatch(line);
      if (header != null) {
        hash = header.group(1)!.replaceFirst('^', '');
        finalLine = int.parse(header.group(2)!);
      } else if (line.startsWith('author ')) {
        authors[hash] = line.substring(7);
      } else if (line.startsWith('author-time ')) {
        final seconds = int.tryParse(line.substring(12));
        times[hash] = seconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      } else if (line.startsWith('\t')) {
        output.add(
          BlameLine(
            lineNumber: finalLine,
            hash: hash,
            author: authors[hash] ?? 'Unknown',
            date: times[hash],
            content: line.substring(1),
          ),
        );
      }
    }
    return List<BlameLine>.unmodifiable(output);
  }

  Future<List<CommitNode>> readFileHistory(
    String rootPath,
    String path, {
    int limit = 200,
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
    final result = await runner.runChecked(
      GitCommand(
        arguments: <String>[
          'log',
          '--follow',
          '--max-count=$limit',
          '--format=$format${GitLogParser.recordSeparator}',
          '--',
          path,
        ],
        workingDirectory: rootPath,
        description: 'git log --follow -- <path>',
      ),
    );
    return logParser.parse(result.stdout);
  }

  Future<String> createPatchFromCommit(String rootPath, String commit) async {
    final result = await runner.runChecked(
      GitCommand(
        arguments: <String>['format-patch', '--stdout', '-1', commit],
        workingDirectory: rootPath,
        description: 'git format-patch --stdout -1 <commit>',
      ),
    );
    return result.stdout;
  }

  Future<String> createWorkingTreePatch(String rootPath) async {
    final result = await runner.runChecked(
      GitCommand(
        arguments: const <String>['diff', '--binary', 'HEAD'],
        workingDirectory: rootPath,
        description: 'git diff --binary HEAD',
      ),
    );
    return result.stdout;
  }

  Future<void> applyPatch(String rootPath, String patch) => _mutate(
    rootPath,
    () => runner.runChecked(
      GitCommand(
        arguments: const <String>['apply', '--3way', '-'],
        workingDirectory: rootPath,
        description: 'git apply --3way <patch>',
        stdin: utf8.encode(patch),
      ),
    ),
  );

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
