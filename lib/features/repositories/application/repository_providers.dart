import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/storage/database.dart';
import '../../../core/git/git_executable_locator.dart';
import '../../../core/git/git_process_runner.dart';
import '../../../core/git/git_status.dart';
import '../../branches/domain/branch_info.dart';
import '../../commits/domain/commit_node.dart';
import '../../conflicts/domain/repository_operation_state.dart';
import '../../diff/domain/git_diff.dart';
import '../../stash/domain/stash_entry.dart';
import '../data/git_repository_service.dart';
import 'repository_picker.dart';
import 'repository_tabs_controller.dart';
import 'repository_workspace_controller.dart';

class CustomGitExecutableNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setPath(String? path) {
    state = path;
  }
}

final customGitExecutableProvider =
    NotifierProvider<CustomGitExecutableNotifier, String?>(
      CustomGitExecutableNotifier.new,
    );

final gitExecutableLocatorProvider = Provider<GitExecutableLocator>((ref) {
  final customPath = ref.watch(customGitExecutableProvider);
  return GitExecutableLocator(customExecutable: customPath);
});

final gitInstallationProvider = FutureProvider<GitInstallation?>((ref) {
  return ref.watch(gitExecutableLocatorProvider).locate();
});

final gitRepositoryServiceProvider = FutureProvider<GitRepositoryService>((
  ref,
) async {
  final installation = await ref.watch(gitInstallationProvider.future);
  if (installation == null) {
    throw StateError('Git is not installed or configured.');
  }
  return GitRepositoryService(
    runner: GitProcessRunner(gitExecutable: installation.executablePath),
  );
});

final repositoryPickerProvider = Provider<RepositoryPicker>(
  (ref) => const DesktopRepositoryPicker(),
);

final repositoryTabsProvider =
    NotifierProvider<RepositoryTabsController, RepositoryTabsState>(
      RepositoryTabsController.new,
    );

final repositoryStatusProvider =
    FutureProvider.family<RepositoryStatus, String>((ref, rootPath) async {
      final service = await ref.watch(gitRepositoryServiceProvider.future);
      return service.readStatus(rootPath);
    });

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});

final recentRepositoriesProvider = FutureProvider<List<RecentRepository>>((
  ref,
) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return database.listRecentRepositories();
});

typedef RepositoryDiffRequest = ({String rootPath, String path, bool staged});

final repositoryDiffProvider =
    FutureProvider.family<GitDiff, RepositoryDiffRequest>((ref, request) async {
      final service = await ref.watch(gitRepositoryServiceProvider.future);
      return service.readDiff(
        request.rootPath,
        path: request.path,
        staged: request.staged,
      );
    });

final repositoryCommitLogProvider =
    FutureProvider.family<List<CommitNode>, String>((ref, rootPath) async {
      final service = await ref.watch(gitRepositoryServiceProvider.future);
      return service.readCommitLog(rootPath);
    });

final repositoryBranchesProvider =
    FutureProvider.family<List<BranchInfo>, String>((ref, rootPath) async {
      final service = await ref.watch(gitRepositoryServiceProvider.future);
      return service.readBranches(rootPath);
    });

final repositoryRemotesProvider =
    FutureProvider.family<List<RemoteInfo>, String>((ref, rootPath) async {
      final service = await ref.watch(gitRepositoryServiceProvider.future);
      return service.readRemotes(rootPath);
    });

final repositoryTagsProvider = FutureProvider.family<List<String>, String>((
  ref,
  rootPath,
) async {
  final service = await ref.watch(gitRepositoryServiceProvider.future);
  return service.readTags(rootPath);
});

final repositoryStashesProvider =
    FutureProvider.family<List<StashEntry>, String>((ref, rootPath) async {
      final service = await ref.watch(gitRepositoryServiceProvider.future);
      return service.readStashes(rootPath);
    });

final repositoryOperationStateProvider =
    FutureProvider.family<RepositoryOperationState, String>((
      ref,
      rootPath,
    ) async {
      final service = await ref.watch(gitRepositoryServiceProvider.future);
      return service.readOperationState(rootPath);
    });

final repositoryWorkspaceControllerProvider = ChangeNotifierProvider.autoDispose
    .family<RepositoryWorkspaceController, String>(
      RepositoryWorkspaceController.new,
    );
