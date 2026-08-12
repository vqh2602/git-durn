import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/features/commits/data/git_log_parser.dart';

void main() {
  test('parses structured log records including merges and decorations', () {
    const separator = GitLogParser.fieldSeparator;
    const record = GitLogParser.recordSeparator;
    final output = <String>[
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'aaaaaaa',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb cccccccccccccccccccccccccccccccccccccccc',
      'Author Name',
      'author@example.com',
      '2026-08-11T12:00:00+07:00',
      'Merge feature',
      'Detailed body\n',
      'HEAD -> main, tag: v1.0.0',
    ].join(separator);

    final commits = const GitLogParser().parse('$output$record');

    expect(commits, hasLength(1));
    expect(commits.single.parents, hasLength(2));
    expect(commits.single.subject, 'Merge feature');
    expect(commits.single.decorations, contains('HEAD → main'));
    expect(commits.single.decorations, contains('tag: v1.0.0'));
  });
}
