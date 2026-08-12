class GitPatch {
  const GitPatch({required this.header, required this.hunks});

  final List<String> header;
  final List<GitPatchHunk> hunks;

  static GitPatch parse(String text) {
    final lines = text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final header = <String>[];
    final hunks = <GitPatchHunk>[];
    GitPatchHunkBuilder? current;
    for (final line in lines) {
      if (line.startsWith('@@ ')) {
        if (current != null) hunks.add(current.build());
        current = GitPatchHunkBuilder.fromHeader(line);
      } else if (current == null) {
        header.add(line);
      } else {
        current.lines.add(line);
      }
    }
    if (current != null) hunks.add(current.build());
    return GitPatch(header: header, hunks: hunks);
  }

  String patchForHunks(Iterable<int> indexes) {
    final selected = indexes.toSet();
    return _serialize(<GitPatchHunk>[
      for (var index = 0; index < hunks.length; index++)
        if (selected.contains(index)) hunks[index],
    ]);
  }

  String patchForLines(Map<int, Set<int>> selectedLines) {
    final selectedHunks = <GitPatchHunk>[];
    for (final entry in selectedLines.entries) {
      if (entry.key < 0 || entry.key >= hunks.length || entry.value.isEmpty) {
        continue;
      }
      final partial = hunks[entry.key].selectLines(entry.value);
      if (partial.hasChanges) selectedHunks.add(partial);
    }
    return _serialize(selectedHunks);
  }

  String _serialize(List<GitPatchHunk> selectedHunks) {
    if (selectedHunks.isEmpty) return '';
    final output = <String>[...header];
    while (output.isNotEmpty && output.last.isEmpty) {
      output.removeLast();
    }
    for (final hunk in selectedHunks) {
      output
        ..add(hunk.header)
        ..addAll(hunk.lines);
    }
    return '${output.join('\n')}\n';
  }
}

class GitPatchHunk {
  const GitPatchHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.suffix,
    required this.lines,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String suffix;
  final List<String> lines;

  String get header =>
      '@@ -$oldStart${_count(oldCount)} +$newStart${_count(newCount)} @@$suffix';

  bool get hasChanges => lines.any(
    (line) =>
        (line.startsWith('+') && !line.startsWith('+++')) ||
        (line.startsWith('-') && !line.startsWith('---')),
  );

  GitPatchHunk selectLines(Set<int> selected) {
    final result = <String>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.startsWith('-') && !selected.contains(index)) {
        result.add(' ${line.substring(1)}');
      } else if (line.startsWith('+') && !selected.contains(index)) {
        continue;
      } else {
        result.add(line);
      }
    }
    var oldLines = 0;
    var newLines = 0;
    for (final line in result) {
      if (line == r'\ No newline at end of file') continue;
      if (!line.startsWith('+')) oldLines++;
      if (!line.startsWith('-')) newLines++;
    }
    return GitPatchHunk(
      oldStart: oldStart,
      oldCount: oldLines,
      newStart: newStart,
      newCount: newLines,
      suffix: suffix,
      lines: List<String>.unmodifiable(result),
    );
  }

  static String _count(int count) => count == 1 ? '' : ',$count';
}

class GitPatchHunkBuilder {
  GitPatchHunkBuilder({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.suffix,
  });

  factory GitPatchHunkBuilder.fromHeader(String header) {
    final match = RegExp(
      r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$',
    ).firstMatch(header);
    if (match == null) throw FormatException('Invalid patch hunk: $header');
    return GitPatchHunkBuilder(
      oldStart: int.parse(match.group(1)!),
      oldCount: int.tryParse(match.group(2) ?? '') ?? 1,
      newStart: int.parse(match.group(3)!),
      newCount: int.tryParse(match.group(4) ?? '') ?? 1,
      suffix: match.group(5) ?? '',
    );
  }

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String suffix;
  final List<String> lines = <String>[];

  GitPatchHunk build() => GitPatchHunk(
    oldStart: oldStart,
    oldCount: oldCount,
    newStart: newStart,
    newCount: newCount,
    suffix: suffix,
    lines: List<String>.unmodifiable(lines),
  );
}
