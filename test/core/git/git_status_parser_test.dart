import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/core/git/git_status.dart';
import 'package:git_desktop_client/core/git/git_status_parser.dart';

void main() {
  const parser = GitStatusParser();

  test('parses branch metadata and all porcelain v2 record families', () {
    const hash = '0123456789012345678901234567890123456789';
    final output = <String>[
      '# branch.oid $hash\n',
      '# branch.head feature/phase-0\n',
      '# branch.upstream origin/feature/phase-0\n',
      '# branch.ab +3 -1\n',
      '1 .M N... 100644 100644 100644 $hash $hash lib/with space.dart\x00',
      '1 A. N... 000000 100644 100644 $hash $hash staged.dart\x00',
      '2 R. N... 100644 100644 100644 $hash $hash R100 lib/new.dart\x00',
      'lib/old.dart\x00',
      'u UU N... 100644 100644 100644 100644 $hash $hash $hash conflict.dart\x00',
      '? untracked file.txt\x00',
      '! ignored.log\x00',
    ].join();

    final status = parser.parse(output);

    expect(status.branch.head, 'feature/phase-0');
    expect(status.branch.upstream, 'origin/feature/phase-0');
    expect(status.branch.ahead, 3);
    expect(status.branch.behind, 1);
    expect(status.files, hasLength(6));
    expect(status.files[0].path, 'lib/with space.dart');
    expect(status.files[0].kind, GitChangeKind.modified);
    expect(status.files[1].isStaged, isTrue);
    expect(status.files[2].kind, GitChangeKind.renamed);
    expect(status.files[2].originalPath, 'lib/old.dart');
    expect(status.files[3].isConflicted, isTrue);
    expect(status.files[4].isUntracked, isTrue);
    expect(status.files[5].isIgnored, isTrue);
  });

  test('preserves Unicode and newlines in NUL-delimited paths', () {
    const hash = '0123456789012345678901234567890123456789';
    final output =
        '# branch.oid (initial)\n'
        '# branch.head main\n'
        '1 .M N... 100644 100644 100644 $hash $hash lib/tiếng\nViệt.dart\x00';

    final status = parser.parse(output);

    expect(status.branch.isInitial, isTrue);
    expect(status.files.single.path, 'lib/tiếng\nViệt.dart');
  });

  test('parses detached HEAD', () {
    const output = '# branch.oid abc123\n# branch.head (detached)\n';

    final status = parser.parse(output);

    expect(status.branch.isDetached, isTrue);
    expect(status.branch.displayName, 'Detached HEAD');
    expect(status.isClean, isTrue);
  });
}
