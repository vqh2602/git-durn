enum ConflictChoice { ours, theirs, both, neither }

class ConflictBlock {
  const ConflictBlock({
    required this.startOffset,
    required this.endOffset,
    required this.ours,
    required this.theirs,
    this.base,
  });

  final int startOffset;
  final int endOffset;
  final String ours;
  final String theirs;
  final String? base;
}

class ConflictDocument {
  const ConflictDocument({
    required this.path,
    required this.base,
    required this.ours,
    required this.theirs,
    required this.result,
    required this.blocks,
    required this.isBinary,
  });

  final String path;
  final String base;
  final String ours;
  final String theirs;
  final String result;
  final List<ConflictBlock> blocks;
  final bool isBinary;

  static List<ConflictBlock> parseBlocks(String text) {
    final expression = RegExp(
      r'^<<<<<<<[^\n]*\n(.*?)(?:^\|\|\|\|\|\|\|[^\n]*\n(.*?))?^=======$\n(.*?)^>>>>>>>[^\n]*(?:\n|$)',
      multiLine: true,
      dotAll: true,
    );
    return List<ConflictBlock>.unmodifiable(
      expression
          .allMatches(text)
          .map(
            (match) => ConflictBlock(
              startOffset: match.start,
              endOffset: match.end,
              ours: match.group(1) ?? '',
              base: match.group(2),
              theirs: match.group(3) ?? '',
            ),
          ),
    );
  }

  static String resolveBlock(
    String text,
    ConflictBlock block,
    ConflictChoice choice,
  ) {
    final replacement = switch (choice) {
      ConflictChoice.ours => block.ours,
      ConflictChoice.theirs => block.theirs,
      ConflictChoice.both => '${block.ours}${block.theirs}',
      ConflictChoice.neither => '',
    };
    return text.replaceRange(block.startOffset, block.endOffset, replacement);
  }
}
