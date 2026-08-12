import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_error.dart';
import '../../../core/git/git_status.dart';
import '../../../core/ai/ai_model_catalog.dart';
import '../../../core/ai/ai_model_manager.dart';
import '../../../core/ai/ai_models.dart';
import '../../../core/ai/local_commit_ai_provider.dart';
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
  bool isGeneratingCommit = false;
  String aiStreamText = '';
  GeneratedCommit? aiSuggestion;
  String? aiError;

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

  Future<void> generateCommitMessage() async {
    if (isGeneratingCommit) return;
    isGeneratingCommit = true;
    aiStreamText = '';
    aiSuggestion = null;
    aiError = null;
    notifyListeners();
    try {
      final manager = await ref.read(aiModelManagerProvider.future);
      AiModelCatalogItem? model;
      for (final candidate in aiModelCatalog) {
        if (candidate.id == manager.selectedModelId) model = candidate;
      }
      if (model == null ||
          manager.stateFor(model).phase != AiModelDownloadPhase.installed) {
        throw StateError(
          'Open Settings · Local AI, download and select a model first.',
        );
      }
      final service = await ref.read(gitRepositoryServiceProvider.future);
      final context = await service.readCommitAiContext(rootPath);
      final provider = LocalCommitAiProvider(
        modelPath: manager.modelPath(model),
      );
      await for (final token in provider.generateCommitStream(context)) {
        aiStreamText += token;
        notifyListeners();
      }
      aiSuggestion = GeneratedCommit.parse(aiStreamText);
    } on Object catch (caught) {
      aiError = caught.toString();
    } finally {
      isGeneratingCommit = false;
      notifyListeners();
    }
  }

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

  Future<void> applySelectedPatch(String patch) => _run(
    selectedFileStaged ? 'Unstaging selection…' : 'Staging selection…',
    selectedFileStaged ? 'Selection unstaged' : 'Selection staged',
    (service) => service.applyPartialPatch(
      rootPath,
      patch,
      staged: true,
      reverse: selectedFileStaged,
    ),
  );

  Future<void> discardSelectedPatch(String patch) => _run(
    'Creating recovery snapshot and discarding selected hunk…',
    'Selected hunk discarded; recovery snapshot created',
    (service) async {
      final file = selectedFile;
      if (file == null) return null;
      await service.createRecoverySnapshot(rootPath, path: file.path);
      await service.applyPartialPatch(
        rootPath,
        patch,
        staged: false,
        reverse: true,
      );
      return null;
    },
  );

  Future<void> saveConflictResult(
    GitFileStatus file,
    String content, {
    bool markResolvedAfterSave = false,
  }) => _run(
    'Saving conflict result…',
    markResolvedAfterSave
        ? 'Conflict saved and marked resolved'
        : 'Conflict result saved',
    (service) async {
      await service.writeConflictResult(rootPath, file.path, content);
      if (markResolvedAfterSave) {
        await service.markResolved(rootPath, file.path);
      }
      return null;
    },
  );

  Future<void> createWorktree({
    required String path,
    required String branch,
    bool createBranch = false,
  }) => _run(
    'Creating worktree…',
    'Worktree created',
    (service) => service.createWorktree(
      rootPath,
      path: path,
      branch: branch,
      createBranch: createBranch,
    ),
  );

  Future<void> setWorktreeLock(String path, {required bool locked}) => _run(
    locked ? 'Locking worktree…' : 'Unlocking worktree…',
    locked ? 'Worktree locked' : 'Worktree unlocked',
    (service) => service.setWorktreeLock(rootPath, path, locked: locked),
  );

  Future<void> removeWorktree(String path) => _run(
    'Removing worktree…',
    'Worktree removed',
    (service) => service.removeWorktree(rootPath, path),
  );

  Future<void> pruneWorktrees() => _run(
    'Pruning worktrees…',
    'Worktrees pruned',
    (service) => service.pruneWorktrees(rootPath),
  );

  Future<void> updateSubmodules() => _run(
    'Updating submodules recursively…',
    'Submodules updated',
    (service) => service.updateSubmodules(rootPath),
  );

  Future<void> syncSubmodules() => _run(
    'Synchronizing submodules…',
    'Submodules synchronized',
    (service) => service.syncSubmodules(rootPath),
  );

  Future<void> lfsAction(String action, {String? pattern}) => _run(
    'Running Git LFS $action…',
    'Git LFS $action completed',
    (service) => service.lfsAction(rootPath, action, pattern: pattern),
  );

  Future<void> applyPatch(String patch) => _run(
    'Applying patch…',
    'Patch applied',
    (service) => service.applyPatch(rootPath, patch),
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
    ref.invalidate(repositoryWorktreesProvider(rootPath));
    ref.invalidate(repositorySubmodulesProvider(rootPath));
    ref.invalidate(repositoryLfsProvider(rootPath));
    ref.invalidate(repositoryReflogProvider(rootPath));
    if (selectedFile case final file?) {
      ref.invalidate(
        repositoryDiffProvider((
          rootPath: rootPath,
          path: file.path,
          staged: selectedFileStaged,
        )),
      );
      ref.invalidate(
        repositoryConflictDocumentProvider((
          rootPath: rootPath,
          path: file.path,
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
