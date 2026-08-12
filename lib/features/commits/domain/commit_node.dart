class CommitNode {
  const CommitNode({
    required this.hash,
    required this.shortHash,
    required this.parents,
    required this.authorName,
    required this.authorEmail,
    required this.authorDate,
    required this.subject,
    required this.body,
    required this.decorations,
  });

  final String hash;
  final String shortHash;
  final List<String> parents;
  final String authorName;
  final String authorEmail;
  final DateTime? authorDate;
  final String subject;
  final String body;
  final List<String> decorations;
}
