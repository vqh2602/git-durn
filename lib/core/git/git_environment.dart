class GitEnvironment {
  const GitEnvironment({this.values = const <String, String>{}});

  final Map<String, String> values;

  GitEnvironment merge(Map<String, String> additions) {
    return GitEnvironment(values: <String, String>{...values, ...additions});
  }
}
