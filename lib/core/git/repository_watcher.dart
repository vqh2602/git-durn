import 'dart:async';
import 'dart:io';

class RepositoryWatcher {
  RepositoryWatcher({
    required this.rootPath,
    required this.onRepositoryChanged,
    this.debounce = const Duration(milliseconds: 450),
    this.fallbackInterval = const Duration(seconds: 8),
  });

  final String rootPath;
  final void Function() onRepositoryChanged;
  final Duration debounce;
  final Duration fallbackInterval;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounceTimer;
  Timer? _fallbackTimer;

  void start() {
    _subscription = Directory(rootPath)
        .watch(recursive: true)
        .listen(
          (event) {
            final normalized = event.path.replaceAll('\\', '/');
            if (_isNoise(normalized)) return;
            _debounceTimer?.cancel();
            _debounceTimer = Timer(debounce, onRepositoryChanged);
          },
          onError: (Object _) {
            // The lightweight fallback still keeps repository state synchronized.
          },
        );
    _fallbackTimer = Timer.periodic(fallbackInterval, (_) {
      onRepositoryChanged();
    });
  }

  bool _isNoise(String path) {
    return path.contains('/.git/objects/') ||
        path.contains('/node_modules/') ||
        path.contains('/build/') ||
        path.contains('/.dart_tool/');
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _fallbackTimer?.cancel();
    await _subscription?.cancel();
  }
}
