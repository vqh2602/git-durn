class RepositorySession {
  const RepositorySession({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.gitDirectory,
    required this.openedAt,
  });

  final String id;
  final String name;
  final String rootPath;
  final String gitDirectory;
  final DateTime openedAt;
}
