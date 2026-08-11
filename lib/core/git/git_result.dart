class GitResult {
  const GitResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
    required this.sanitizedCommandDescription,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;
  final String sanitizedCommandDescription;

  bool get isSuccess => exitCode == 0;
}
