import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_error.dart';
import '../../../core/storage/database.dart';
import '../data/git_repository_service.dart';
import '../domain/repository_session.dart';
import 'repository_providers.dart';

class RepositoryTabsState {
  const RepositoryTabsState({
    this.sessions = const <RepositorySession>[],
    this.selectedId,
    this.isOpening = false,
    this.error,
  });

  final List<RepositorySession> sessions;
  final String? selectedId;
  final bool isOpening;
  final GitError? error;

  RepositorySession? get selected {
    for (final session in sessions) {
      if (session.id == selectedId) return session;
    }
    return null;
  }

  RepositoryTabsState copyWith({
    List<RepositorySession>? sessions,
    String? selectedId,
    bool clearSelection = false,
    bool? isOpening,
    GitError? error,
    bool clearError = false,
  }) {
    return RepositoryTabsState(
      sessions: sessions ?? this.sessions,
      selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
      isOpening: isOpening ?? this.isOpening,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class RepositoryTabsController extends Notifier<RepositoryTabsState> {
  @override
  RepositoryTabsState build() => const RepositoryTabsState();

  Future<void> openRepository() async {
    final path = await ref.read(repositoryPickerProvider).pickRepository();
    if (path == null) return;
    await openPath(path);
  }

  Future<void> openPath(String path) async {
    state = state.copyWith(isOpening: true, clearError: true);
    try {
      final service = await ref.read(gitRepositoryServiceProvider.future);
      final session = await service.openRepository(path);
      await _registerSession(session, service: service);
    } on GitError catch (error) {
      state = state.copyWith(isOpening: false, error: error);
    } on Object catch (error) {
      state = state.copyWith(
        isOpening: false,
        error: GitError(
          kind: GitErrorKind.unknown,
          message: 'The repository could not be opened.',
          technicalDetails: error.toString(),
        ),
      );
    }
  }

  Future<void> initializeRepository() async {
    final path = await ref.read(repositoryPickerProvider).pickRepository();
    if (path == null) return;
    state = state.copyWith(isOpening: true, clearError: true);
    try {
      final service = await ref.read(gitRepositoryServiceProvider.future);
      final session = await service.initializeRepository(path);
      await _registerSession(session, service: service);
    } on GitError catch (error) {
      state = state.copyWith(isOpening: false, error: error);
    } on Object catch (error) {
      state = state.copyWith(
        isOpening: false,
        error: GitError(
          kind: GitErrorKind.unknown,
          message: 'The repository could not be initialized.',
          technicalDetails: error.toString(),
        ),
      );
    }
  }

  Future<void> cloneRepository({
    required String url,
    required String destination,
    int? depth,
    bool singleBranch = false,
    bool recurseSubmodules = false,
  }) async {
    state = state.copyWith(isOpening: true, clearError: true);
    try {
      final service = await ref.read(gitRepositoryServiceProvider.future);
      final session = await service.cloneRepository(
        url: url,
        destination: destination,
        depth: depth,
        singleBranch: singleBranch,
        recurseSubmodules: recurseSubmodules,
      );
      await _registerSession(session, service: service);
    } on GitError catch (error) {
      state = state.copyWith(isOpening: false, error: error);
    } on Object catch (error) {
      state = state.copyWith(
        isOpening: false,
        error: GitError(
          kind: GitErrorKind.unknown,
          message: 'The repository could not be cloned.',
          technicalDetails: error.toString(),
        ),
      );
    }
  }

  Future<void> removeRecent(String path) async {
    final database = await ref.read(appDatabaseProvider.future);
    database.removeRepository(path);
    ref.invalidate(recentRepositoriesProvider);
  }

  Future<void> setFavorite(String path, {required bool isFavorite}) async {
    final database = await ref.read(appDatabaseProvider.future);
    database.setFavorite(path, isFavorite: isFavorite);
    ref.invalidate(recentRepositoriesProvider);
  }

  Future<void> _registerSession(
    RepositorySession session, {
    required GitRepositoryService service,
  }) async {
    final existing = state.sessions.indexWhere((item) => item.id == session.id);
    final sessions = List<RepositorySession>.of(state.sessions);
    if (existing == -1) {
      sessions.add(session);
    } else {
      sessions[existing] = session;
    }
    final status = await service.readStatus(session.rootPath);
    final remoteUrl = await service.readPrimaryRemoteUrl(session.rootPath);
    final database = await ref.read(appDatabaseProvider.future);
    database.upsertRepository(
      RecentRepository(
        path: session.rootPath,
        name: session.name,
        remoteUrl: remoteUrl,
        currentBranch: status.branch.head,
        lastOpenedAt: DateTime.now(),
      ),
    );
    state = state.copyWith(
      sessions: List<RepositorySession>.unmodifiable(sessions),
      selectedId: session.id,
      isOpening: false,
      clearError: true,
    );
    ref.invalidate(repositoryStatusProvider(session.rootPath));
    ref.invalidate(recentRepositoriesProvider);
  }

  void select(String id) {
    if (state.sessions.any((session) => session.id == id)) {
      state = state.copyWith(selectedId: id, clearError: true);
    }
  }

  void close(String id) {
    final index = state.sessions.indexWhere((session) => session.id == id);
    if (index == -1) return;
    final sessions = List<RepositorySession>.of(state.sessions)
      ..removeAt(index);
    var selectedId = state.selectedId;
    if (selectedId == id) {
      if (sessions.isEmpty) {
        selectedId = null;
      } else {
        selectedId = sessions[index.clamp(0, sessions.length - 1)].id;
      }
    }
    state = RepositoryTabsState(
      sessions: List<RepositorySession>.unmodifiable(sessions),
      selectedId: selectedId,
    );
  }

  void clearError() => state = state.copyWith(clearError: true);
}
