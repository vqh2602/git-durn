import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/features/diff/domain/git_patch.dart';

void main() {
  const source = '''diff --git a/demo.txt b/demo.txt
index 123..456 100644
--- a/demo.txt
+++ b/demo.txt
@@ -1,3 +1,4 @@
 one
-two
+TWO
+extra
 three
''';

  test('extracts a complete hunk as an applicable patch', () {
    final patch = GitPatch.parse(source);
    expect(patch.hunks, hasLength(1));
    expect(patch.patchForHunks(<int>[0]), contains('@@ -1,3 +1,4 @@'));
  });

  test('builds a partial line patch with recalculated counts', () {
    final patch = GitPatch.parse(source);
    final partial = patch.patchForLines(<int, Set<int>>{
      0: <int>{1},
    });
    expect(partial, contains('-two'));
    expect(partial, isNot(contains('+TWO')));
    expect(partial, contains('@@ -1,3 +1,2 @@'));
  });
}
