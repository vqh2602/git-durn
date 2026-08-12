class RedactionResult {
  const RedactionResult({
    required this.text,
    required this.redactedCount,
    required this.containsPrivateKey,
  });

  final String text;
  final int redactedCount;
  final bool containsPrivateKey;
}

class SecretRedactor {
  const SecretRedactor();

  RedactionResult redact(String input) {
    var output = input;
    var count = 0;
    final hasPrivateKey = RegExp(
      r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
      caseSensitive: false,
    ).hasMatch(input);
    final patterns = <RegExp>[
      RegExp(r'gh[pousr]_[A-Za-z0-9_]{20,}'),
      RegExp(r'AKIA[0-9A-Z]{16}'),
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]{12,}', caseSensitive: false),
      RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      RegExp(
        r'''(?:(?:api[_-]?key|token|password|passwd|secret)\s*[:=]\s*)["']?[^\s"']{8,}''',
        caseSensitive: false,
      ),
      RegExp(r'''(?:postgres|mysql|mongodb(?:\+srv)?):\/\/[^\s"']+'''),
    ];
    for (final pattern in patterns) {
      output = output.replaceAllMapped(pattern, (match) {
        count++;
        return '<REDACTED_SECRET>';
      });
    }
    if (hasPrivateKey) {
      output = output.replaceAll(
        RegExp(
          r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
          caseSensitive: false,
          dotAll: true,
        ),
        '<REDACTED_PRIVATE_KEY>',
      );
      count++;
    }
    return RedactionResult(
      text: output,
      redactedCount: count,
      containsPrivateKey: hasPrivateKey,
    );
  }
}
