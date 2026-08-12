class WorktreeInfo {
  const WorktreeInfo({
    required this.path,
    required this.head,
    this.branch,
    this.isBare = false,
    this.isDetached = false,
    this.isLocked = false,
    this.lockReason,
  });

  final String path;
  final String head;
  final String? branch;
  final bool isBare;
  final bool isDetached;
  final bool isLocked;
  final String? lockReason;
}

class SubmoduleInfo {
  const SubmoduleInfo({
    required this.path,
    required this.commit,
    required this.state,
    this.description,
  });

  final String path;
  final String commit;
  final String state;
  final String? description;
}

class ReflogEntry {
  const ReflogEntry({
    required this.selector,
    required this.hash,
    required this.shortHash,
    required this.subject,
    required this.date,
  });

  final String selector;
  final String hash;
  final String shortHash;
  final String subject;
  final DateTime? date;
}

class BlameLine {
  const BlameLine({
    required this.lineNumber,
    required this.hash,
    required this.author,
    required this.content,
    this.date,
  });

  final int lineNumber;
  final String hash;
  final String author;
  final DateTime? date;
  final String content;
}

class LfsStatus {
  const LfsStatus({required this.isInstalled, required this.patterns});

  final bool isInstalled;
  final List<String> patterns;
}
