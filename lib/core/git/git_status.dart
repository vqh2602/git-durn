enum GitFileRecordType {
  ordinary,
  renamedOrCopied,
  unmerged,
  untracked,
  ignored,
}

enum GitChangeKind {
  modified,
  added,
  deleted,
  renamed,
  copied,
  typeChanged,
  untracked,
  ignored,
  conflicted,
  unknown,
}

class GitBranchStatus {
  const GitBranchStatus({
    this.oid,
    this.head,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
  });

  final String? oid;
  final String? head;
  final String? upstream;
  final int ahead;
  final int behind;

  bool get isDetached => head == '(detached)';
  bool get isInitial => oid == '(initial)';
  String get displayName {
    if (isDetached) return 'Detached HEAD';
    if (head == null || head!.isEmpty) return 'Unknown branch';
    return head!;
  }
}

class GitFileStatus {
  const GitFileStatus({
    required this.recordType,
    required this.path,
    required this.indexStatus,
    required this.workTreeStatus,
    required this.kind,
    this.originalPath,
  });

  final GitFileRecordType recordType;
  final String path;
  final String? originalPath;
  final String indexStatus;
  final String workTreeStatus;
  final GitChangeKind kind;

  bool get isStaged => indexStatus != '.' && indexStatus != '?';
  bool get isConflicted => kind == GitChangeKind.conflicted;
  bool get isUntracked => recordType == GitFileRecordType.untracked;
  bool get isIgnored => recordType == GitFileRecordType.ignored;
}

class RepositoryStatus {
  const RepositoryStatus({required this.branch, required this.files});

  final GitBranchStatus branch;
  final List<GitFileStatus> files;

  bool get isClean => files.where((file) => !file.isIgnored).isEmpty;
  int get stagedCount => files.where((file) => file.isStaged).length;
  int get conflictedCount => files.where((file) => file.isConflicted).length;
  int get untrackedCount => files.where((file) => file.isUntracked).length;
}
