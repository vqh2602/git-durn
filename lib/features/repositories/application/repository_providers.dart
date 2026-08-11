import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_executable_locator.dart';
import '../../../core/git/git_process_runner.dart';
import '../../../core/git/git_status.dart';
import '../data/git_repository_service.dart';
import 'repository_picker.dart';
import 'repository_tabs_controller.dart';

final gitExecutableLocatorProvider = Provider<GitExecutableLocator>(
  (ref) => const GitExecutableLocator(),
);

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
