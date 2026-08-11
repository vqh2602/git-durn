import 'git_result.dart';

enum GitErrorKind {
  authentication,
  network,
  conflict,
  dirtyWorkingTree,
  nonFastForward,
  repositoryNotFound,
  permission,
  lock,
  hook,
  timeout,
  executableNotFound,
  unknown,
}

class GitError implements Exception {
  const GitError({
    required this.kind,
    required this.message,
    this.technicalDetails,
    this.result,
  });

  final GitErrorKind kind;
  final String message;
  final String? technicalDetails;
  final GitResult? result;

  factory GitError.fromResult(GitResult result) {
    final details = '${result.stderr}\n${result.stdout}'.trim();
    final normalized = details.toLowerCase();

    GitErrorKind kind = GitErrorKind.unknown;
    String message = 'Git could not complete the operation.';

    if (normalized.contains('authentication failed') ||
        normalized.contains('permission denied (publickey)')) {
      kind = GitErrorKind.authentication;
      message = 'Authentication is required for this Git operation.';
    } else if (normalized.contains('not a git repository')) {
      kind = GitErrorKind.repositoryNotFound;
      message = 'The selected folder is not inside a Git repository.';
    } else if (normalized.contains('index.lock') ||
        normalized.contains('another git process')) {
      kind = GitErrorKind.lock;
      message = 'A Git lock was detected. Another Git process may be active.';
    } else if (normalized.contains('non-fast-forward') ||
        normalized.contains('fetch first')) {
      kind = GitErrorKind.nonFastForward;
      message = 'The operation was rejected because the branch has diverged.';
    } else if (normalized.contains('would be overwritten') ||
        normalized.contains('local changes')) {
      kind = GitErrorKind.dirtyWorkingTree;
      message = 'Local changes must be handled before this operation.';
    } else if (normalized.contains('conflict')) {
      kind = GitErrorKind.conflict;
      message = 'Git reported a conflict that requires resolution.';
    } else if (normalized.contains('could not resolve host') ||
        normalized.contains('failed to connect') ||
        normalized.contains('network is unreachable')) {
      kind = GitErrorKind.network;
      message = 'Git could not reach the remote host.';
    } else if (normalized.contains('permission denied')) {
      kind = GitErrorKind.permission;
      message = 'Git does not have permission to access the requested path.';
    } else if (normalized.contains('hook') && result.exitCode != 0) {
      kind = GitErrorKind.hook;
      message = 'A Git hook rejected the operation.';
    }

    return GitError(
      kind: kind,
      message: message,
      technicalDetails: details.isEmpty ? null : details,
      result: result,
    );
  }

  @override
  String toString() => message;
}
