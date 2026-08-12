import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/features/conflicts/domain/conflict_document.dart';

void main() {
  test('parses and resolves conflict blocks without touching other text', () {
    const text = '''before
<<<<<<< HEAD
ours
||||||| base
base
=======
theirs
>>>>>>> feature
after
''';
    final blocks = ConflictDocument.parseBlocks(text);
    expect(blocks, hasLength(1));
    expect(blocks.single.base, 'base\n');
    expect(
      ConflictDocument.resolveBlock(text, blocks.single, ConflictChoice.both),
      'before\nours\ntheirs\nafter\n',
    );
  });
}
