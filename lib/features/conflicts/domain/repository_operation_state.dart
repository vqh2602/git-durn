enum RepositoryOperationType { none, merge, rebase, cherryPick, revert }

class RepositoryOperationState {
  const RepositoryOperationState({
    required this.type,
    required this.gitDirectory,
  });

  final RepositoryOperationType type;
  final String gitDirectory;

  bool get isInProgress => type != RepositoryOperationType.none;
}
