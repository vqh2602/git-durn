import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/core/ai/ai_models.dart';
import 'package:git_desktop_client/core/security/secret_redactor.dart';

void main() {
  test('parses prefixed AI JSON safely', () {
    final commit = GeneratedCommit.parse('''Result:
{"type":"fix","scope":"git","subject":"resume model download","body":"Keep partial bytes.","breaking_change":false}
''');
    expect(
      commit.summary(conventional: true),
      'fix(git): resume model download',
    );
    expect(commit.body, 'Keep partial bytes.');
  });

  test('rejects an AI response without a JSON object', () {
    expect(() => GeneratedCommit.parse('not json'), throwsFormatException);
  });

  test('redacts common tokens and flags private keys', () {
    const input = '''Authorization: Bearer abcdefghijklmnopqrstuvwxyz
token=ghp_abcdefghijklmnopqrstuvwxyz123456
-----BEGIN PRIVATE KEY-----
secret
-----END PRIVATE KEY-----''';
    final result = const SecretRedactor().redact(input);
    expect(result.containsPrivateKey, isTrue);
    expect(result.redactedCount, greaterThanOrEqualTo(3));
    expect(result.text, isNot(contains('ghp_')));
    expect(result.text, contains('<REDACTED_PRIVATE_KEY>'));
  });
}
