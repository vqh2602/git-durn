class GitCommand {
  const GitCommand({
    required this.arguments,
    required this.workingDirectory,
    required this.description,
    this.environment = const <String, String>{},
    this.timeout = const Duration(seconds: 30),
    this.stdin,
  });

  final List<String> arguments;
  final String workingDirectory;
  final String description;
  final Map<String, String> environment;
  final Duration timeout;
  final List<int>? stdin;
}
