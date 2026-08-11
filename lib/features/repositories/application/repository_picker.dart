import 'package:file_selector/file_selector.dart';

abstract interface class RepositoryPicker {
  Future<String?> pickRepository();
}

class DesktopRepositoryPicker implements RepositoryPicker {
  const DesktopRepositoryPicker();

  @override
  Future<String?> pickRepository() {
    return getDirectoryPath(confirmButtonText: 'Open Repository');
  }
}
