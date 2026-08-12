abstract interface class TerminalBackend {
  Stream<List<int>> get output;
  Future<int> get exitCode;

  void start(TerminalLaunchConfiguration configuration);
  void write(List<int> data);
  void resize({required int rows, required int columns});
  void kill();
}

class TerminalLaunchConfiguration {
  const TerminalLaunchConfiguration({
    required this.executable,
    required this.workingDirectory,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.rows = 24,
    this.columns = 80,
  });

  final String executable;
  final String workingDirectory;
  final List<String> arguments;
  final Map<String, String> environment;
  final int rows;
  final int columns;
}
