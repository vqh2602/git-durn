import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/core/git/git_executable_locator.dart';

void main() {
  test('GitExecutableLocator locates system git executable', () async {
    const locator = GitExecutableLocator();
    final installation = await locator.locate();
    expect(installation, isNotNull);
    expect(installation!.executablePath, isNotEmpty);
    expect(installation.version, isNotEmpty);
  });
}
