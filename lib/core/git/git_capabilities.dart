class GitCapabilities {
  const GitCapabilities({required this.version});

  final String version;

  bool get supportsRestore {
    final parts = version.split('.');
    if (parts.length < 2) return false;
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = int.tryParse(parts[1]) ?? 0;
    return major > 2 || (major == 2 && minor >= 23);
  }
}
