import '../domain/commit_node.dart';

class GitLogParser {
  const GitLogParser();

  static const fieldSeparator = '\x1f';
  static const recordSeparator = '\x1e';

  List<CommitNode> parse(String output) {
    final commits = <CommitNode>[];
    for (final rawRecord in output.split(recordSeparator)) {
      final record = rawRecord.trimLeft();
      if (record.trim().isEmpty) continue;
      final fields = record.split(fieldSeparator);
      if (fields.length < 9) {
        throw const FormatException('Malformed structured Git log record.');
      }
      commits.add(
        CommitNode(
          hash: fields[0],
          shortHash: fields[1],
          parents: fields[2].isEmpty
              ? const <String>[]
              : List<String>.unmodifiable(fields[2].split(' ')),
          authorName: fields[3],
          authorEmail: fields[4],
          authorDate: DateTime.tryParse(fields[5]),
          subject: fields[6],
          body: fields[7].trim(),
          decorations: _parseDecorations(fields[8]),
        ),
      );
    }
    return List<CommitNode>.unmodifiable(commits);
  }

  List<String> _parseDecorations(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const <String>[];
    final withoutParens = trimmed.startsWith('(') && trimmed.endsWith(')')
        ? trimmed.substring(1, trimmed.length - 1)
        : trimmed;
    return List<String>.unmodifiable(
      withoutParens
          .split(', ')
          .map((item) => item.replaceFirst('HEAD -> ', 'HEAD → '))
          .where((item) => item.isNotEmpty),
    );
  }
}
