class GitDiff {
  const GitDiff({
    required this.path,
    required this.text,
    required this.isStaged,
    required this.isBinary,
  });

  final String path;
  final String text;
  final bool isStaged;
  final bool isBinary;
}
