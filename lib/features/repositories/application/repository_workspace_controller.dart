import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_error.dart';
import '../../../core/git/git_status.dart';
import '../../../core/git/repository_watcher.dart';
import '../../commits/domain/commit_node.dart';
import '../data/git_repository_service.dart';
import 'repository_providers.dart';

class RepositoryWorkspaceController extends ChangeNotifier {
  RepositoryWorkspaceController(this.ref, this.rootPath) {
    _watcher = RepositoryWatcher(
      rootPath: rootPath,
      onRepositoryChanged: _invalidateRepositoryData,
    )..start();
  }

  final Ref ref;
  final String rootPath;
  late final RepositoryWatcher _watcher;

  GitFileStatus? selectedFile;
  bool selectedFileStaged = false;
  CommitNode? selectedCommit;
  bool isBusy = false;
  String? operationLabel;
  String? lastSuccess;
  GitError? error;

  void selectFile(GitFileStatus file, {required bool staged}) {
    selectedFile = file;
    selectedFileStaged = staged;
    selectedCommit = null;
    notifyListeners();
  }

  void selectCommit(CommitNode commit) {
    selectedCommit = commit;
    selectedFile = null;
    notifyListeners();
  }

  void clearSelection() {
    selectedFile = null;
    selectedCommit = null;
    notifyListeners();
  }

  Future<void> stage(GitFileStatus file) => _run(
    'Staging ${file.path}…',
    'Staged ${file.path}',
    (service) => service.stagePath(rootPath, file.path),
  );

  Future<void> unstage(GitFileStatus file) => _run(
    'Unstaging ${file.path}…',
    'Unstaged ${file.path}',
    (service) => service.unstagePath(rootPath, file.path),
  );

  Future<void> stageAll() => _run(
    'Staging all changes…',
    'All changes staged',
    (service) => service.stageAll(rootPath),
  );

  Future<void> unstageAll() => _run(
    'Unstaging all changes…',
    'All changes unstaged',
    (service) => service.unstageAll(rootPath),
  );

  Future<void> discard(GitFileStatus file) => _run(
    'Creating recovery snapshot and discarding ${file.path}…',
    'Discarded ${file.path}; recovery snapshot created',
    (service) => service.discardPath(rootPath, file.path),
  );

  Future<void> commit({
    required String summary,
    required String description,
    required bool amend,
  }) => _run(
    amend ? 'Amending commit…' : 'Creating commit…',
    amend ? 'Commit amended' : 'Commit created',
    (service) => service.commit(
      rootPath,
      summary: summary,
      description: description,
      amend: amend,
    ),
  );

  Future<void> fetch({bool all = false, bool prune = false}) => _run(
    'Fetching…',
    'Fetch completed',
    (service) => service.fetch(rootPath, all: all, prune: prune),
  );

  Future<void> pull({String mode = 'merge'}) => _run(
    'Pulling…',
    'Pull completed',
    (service) => service.pull(rootPath, mode: mode),
  );

  Future<void> push({
    bool setUpstream = false,
    bool tags = false,
    bool forceWithLease = false,
  }) => _run(
    'Pushing…',
    'Push completed',
    (service) => service.push(
      rootPath,
      setUpstream: setUpstream,
      tags: tags,
      forceWithLease: forceWithLease,
    ),
  );

  Future<void> createBranch(String name, {String? startPoint}) => _run(
    'Creating branch $name…',
    'Created branch $name',
    (service) => service.createBranch(rootPath, name, startPoint: startPoint),
  );

  Future<void> checkoutBranch(String name) => _run(
    'Checking out $name…',
    'Checked out $name',
    (service) => service.checkoutBranch(rootPath, name),
  );

  Future<void> deleteBranch(String name, {bool force = false}) => _run(
    'Deleting branch $name…',
    'Deleted branch $name',
    (service) => service.deleteBranch(rootPath, name, force: force),
  );

  Future<void> mergeBranch(String name) => _run(
    'Merging $name…',
    'Merged $name',
    (service) => service.mergeBranch(rootPath, name),
  );

  Future<void> createTag(String name, {String? target, String? message}) =>
      _run(
        'Creating tag $name…',
        'Created tag $name',
        (service) =>
            service.createTag(rootPath, name, target: target, message: message),
      );

  Future<void> createStash({String? message, bool includeUntracked = false}) =>
      _run(
        'Creating stash…',
        'Stash created',
        (service) => service.createStash(
          rootPath,
          message: message,
          includeUntracked: includeUntracked,
        ),
      );

  Future<void> applyStash(String selector, {bool pop = false}) => _run(
    pop ? 'Popping $selector…' : 'Applying $selector…',
    pop ? 'Stash popped' : 'Stash applied',
    (service) => service.applyStash(rootPath, selector, pop: pop),
  );

  Future<void> dropStash(String selector) => _run(
    'Dropping $selector…',
    'Stash dropped',
    (service) => service.dropStash(rootPath, selector),
  );

  Future<void> cherryPick(String commit) => _run(
    'Cherry-picking commit…',
    'Commit cherry-picked',
    (service) => service.cherryPick(rootPath, commit),
  );

  Future<void> revertCommit(String commit) => _run(
    'Reverting commit…',
    'Commit reverted',
    (service) => service.revertCommit(rootPath, commit),
  );

  Future<void> resetTo(String commit, {required String mode}) => _run(
    'Resetting branch ($mode)…',
    'Branch reset completed',
    (service) => service.resetTo(rootPath, commit, mode: mode),
  );

  Future<void> rebaseOnto(String branch) => _run(
    'Rebasing onto $branch…',
    'Rebase completed',
    (service) => service.rebaseOnto(rootPath, branch),
  );

  Future<void> resolveConflict(GitFileStatus file, {required bool ours}) =>
      _run(
        'Resolving ${file.path}…',
        'Resolved ${file.path} using ${ours ? 'ours' : 'theirs'}',
        (service) =>
            service.resolveConflictWithSide(rootPath, file.path, ours: ours),
      );

  Future<void> markResolved(GitFileStatus file) => _run(
    'Marking ${file.path} resolved…',
    'Marked ${file.path} resolved',
    (service) => service.markResolved(rootPath, file.path),
  );

  Future<void> continueOperation() => _run(
    'Continuing Git operation…',
    'Git operation continued',
    (service) => service.continueOperation(rootPath),
  );

  Future<void> abortOperation() => _run(
    'Aborting Git operation…',
    'Git operation aborted',
    (service) => service.abortOperation(rootPath),
  );

  void clearMessage() {
    error = null;
    lastSuccess = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    _invalidateRepositoryData();
  }

  Future<void> _run(
    String label,
    String success,
    Future<Object?> Function(GitRepositoryService service) operation,
  ) async {
    if (isBusy) return;
    isBusy = true;
    operationLabel = label;
    lastSuccess = null;
    error = null;
    notifyListeners();
    try {
      final service = await ref.read(gitRepositoryServiceProvider.future);
      await operation(service);
      lastSuccess = success;
    } on GitError catch (caught) {
      error = caught;
    } on Object catch (caught) {
      error = GitError(
        kind: GitErrorKind.unknown,
        message: 'The Git operation failed.',
        technicalDetails: caught.toString(),
      );
    } finally {
      isBusy = false;
      operationLabel = null;
      _invalidateRepositoryData();
      notifyListeners();
    }
  }

  void _invalidateRepositoryData() {
    ref.invalidate(repositoryStatusProvider(rootPath));
    ref.invalidate(repositoryCommitLogProvider(rootPath));
    ref.invalidate(repositoryBranchesProvider(rootPath));
    ref.invalidate(repositoryRemotesProvider(rootPath));
    ref.invalidate(repositoryTagsProvider(rootPath));
    ref.invalidate(repositoryStashesProvider(rootPath));
    ref.invalidate(repositoryOperationStateProvider(rootPath));
    if (selectedFile case final file?) {
      ref.invalidate(
        repositoryDiffProvider((
          rootPath: rootPath,
          path: file.path,
          staged: selectedFileStaged,
        )),
      );
    }
  }

  @override
  void dispose() {
    _watcher.dispose();
    super.dispose();
  }
}
