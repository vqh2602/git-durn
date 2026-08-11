import 'git_status.dart';

class GitStatusParser {
  const GitStatusParser();

  RepositoryStatus parse(String output) {
    String? oid;
    String? head;
    String? upstream;
    var ahead = 0;
    var behind = 0;
    var cursor = 0;

    while (cursor < output.length && output.startsWith('# ', cursor)) {
      final newlineEnd = output.indexOf('\n', cursor);
      final nulEnd = output.indexOf('\x00', cursor);
      final terminators = <int>[
        if (newlineEnd >= 0) newlineEnd,
        if (nulEnd >= 0) nulEnd,
      ]..sort();
      if (terminators.isEmpty) break;
      final headerEnd = terminators.first;
      final line = output.substring(cursor + 2, headerEnd);
      cursor = headerEnd + 1;

      if (line.startsWith('branch.oid ')) {
        oid = line.substring('branch.oid '.length);
      } else if (line.startsWith('branch.head ')) {
        head = line.substring('branch.head '.length);
      } else if (line.startsWith('branch.upstream ')) {
        upstream = line.substring('branch.upstream '.length);
      } else if (line.startsWith('branch.ab ')) {
        final match = RegExp(
          r'^\+(\d+) -(\d+)$',
        ).firstMatch(line.substring('branch.ab '.length));
        ahead = int.tryParse(match?.group(1) ?? '') ?? 0;
        behind = int.tryParse(match?.group(2) ?? '') ?? 0;
      }
    }

    final records = output.substring(cursor).split('\x00');
    final files = <GitFileStatus>[];

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      if (record.isEmpty) continue;

      switch (record[0]) {
        case '1':
          final fields = _splitWithRemainder(record, 8);
          final xy = fields[1];
          files.add(
            GitFileStatus(
              recordType: GitFileRecordType.ordinary,
              path: fields[8],
              indexStatus: xy[0],
              workTreeStatus: xy[1],
              kind: _kindFor(xy),
            ),
          );
        case '2':
          final fields = _splitWithRemainder(record, 9);
          final xy = fields[1];
          final originalPath = index + 1 < records.length
              ? records[++index]
              : null;
          files.add(
            GitFileStatus(
              recordType: GitFileRecordType.renamedOrCopied,
              path: fields[9],
              originalPath: originalPath,
              indexStatus: xy[0],
              workTreeStatus: xy[1],
              kind: fields[8].startsWith('C')
                  ? GitChangeKind.copied
                  : GitChangeKind.renamed,
            ),
          );
        case 'u':
          final fields = _splitWithRemainder(record, 10);
          final xy = fields[1];
          files.add(
            GitFileStatus(
              recordType: GitFileRecordType.unmerged,
              path: fields[10],
              indexStatus: xy[0],
              workTreeStatus: xy[1],
              kind: GitChangeKind.conflicted,
            ),
          );
        case '?':
          files.add(
            GitFileStatus(
              recordType: GitFileRecordType.untracked,
              path: record.substring(2),
              indexStatus: '?',
              workTreeStatus: '?',
              kind: GitChangeKind.untracked,
            ),
          );
        case '!':
          files.add(
            GitFileStatus(
              recordType: GitFileRecordType.ignored,
              path: record.substring(2),
              indexStatus: '!',
              workTreeStatus: '!',
              kind: GitChangeKind.ignored,
            ),
          );
        default:
          throw const FormatException('Unknown porcelain v2 record type.');
      }
    }

    return RepositoryStatus(
      branch: GitBranchStatus(
        oid: oid,
        head: head,
        upstream: upstream,
        ahead: ahead,
        behind: behind,
      ),
      files: List<GitFileStatus>.unmodifiable(files),
    );
  }

  List<String> _splitWithRemainder(String value, int separatorCount) {
    final fields = <String>[];
    var start = 0;
    for (var count = 0; count < separatorCount; count++) {
      final separator = value.indexOf(' ', start);
      if (separator < 0) {
        throw const FormatException('Malformed porcelain v2 record.');
      }
      fields.add(value.substring(start, separator));
      start = separator + 1;
    }
    fields.add(value.substring(start));
    return fields;
  }

  GitChangeKind _kindFor(String xy) {
    if (xy.contains('U') || const <String>{'DD', 'AA'}.contains(xy)) {
      return GitChangeKind.conflicted;
    }
    final code = xy[0] == '.' ? xy[1] : xy[0];
    return switch (code) {
      'M' => GitChangeKind.modified,
      'A' => GitChangeKind.added,
      'D' => GitChangeKind.deleted,
      'R' => GitChangeKind.renamed,
      'C' => GitChangeKind.copied,
      'T' => GitChangeKind.typeChanged,
      _ => GitChangeKind.unknown,
    };
  }
}
