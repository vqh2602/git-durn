import 'dart:convert';

class GeneratedCommit {
  const GeneratedCommit({
    required this.type,
    required this.scope,
    required this.subject,
    required this.body,
    required this.breakingChange,
  });

  final String type;
  final String scope;
  final String subject;
  final String body;
  final bool breakingChange;

  factory GeneratedCommit.fromJson(Map<String, Object?> json) {
    final subject = (json['subject'] as String? ?? '').trim();
    if (subject.isEmpty) {
      throw const FormatException('AI response has no subject.');
    }
    return GeneratedCommit(
      type: (json['type'] as String? ?? 'chore').trim(),
      scope: (json['scope'] as String? ?? '').trim(),
      subject: subject,
      body: (json['body'] as String? ?? '').trim(),
      breakingChange: json['breaking_change'] == true,
    );
  }

  factory GeneratedCommit.parse(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('AI did not return a JSON object.');
    }
    return GeneratedCommit.fromJson(
      jsonDecode(response.substring(start, end + 1)) as Map<String, Object?>,
    );
  }

  String summary({required bool conventional}) {
    if (!conventional) return subject;
    final prefix = scope.isEmpty ? type : '$type($scope)';
    return '$prefix${breakingChange ? '!' : ''}: $subject';
  }
}

class CommitAiContext {
  const CommitAiContext({
    required this.branch,
    required this.stagedFiles,
    required this.diff,
    required this.recentSubjects,
    required this.omittedFiles,
    required this.redactedSecrets,
  });

  final String branch;
  final List<String> stagedFiles;
  final String diff;
  final List<String> recentSubjects;
  final int omittedFiles;
  final int redactedSecrets;
}
