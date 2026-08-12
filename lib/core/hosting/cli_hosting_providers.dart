import 'dart:convert';
import 'dart:io';

import 'git_hosting_provider.dart';
import 'hosting_models.dart';

abstract class CliHostingProvider implements GitHostingProvider {
  const CliHostingProvider(this.executable);
  final String executable;

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(
        executable,
        availabilityArguments,
        runInShell: false,
      ).timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  List<String> get availabilityArguments;

  Future<Object?> runJson(String root, List<String> arguments) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: root,
      runInShell: false,
      environment: const <String, String>{'PAGER': 'cat', 'NO_COLOR': '1'},
      includeParentEnvironment: true,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
    );
    final output = await stdout;
    final error = await stderr;
    if (exitCode != 0) {
      throw ProcessException(executable, arguments, error.trim(), exitCode);
    }
    return jsonDecode(output);
  }

  Future<void> runChecked(String root, List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: root,
      runInShell: false,
    ).timeout(const Duration(minutes: 2));
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}

class GitHubCliProvider extends CliHostingProvider {
  const GitHubCliProvider() : super('gh');
  @override
  HostingKind get kind => HostingKind.github;
  @override
  String get displayName => 'GitHub (gh CLI)';
  @override
  List<String> get availabilityArguments => const <String>['auth', 'status'];

  @override
  Future<List<HostingPullRequest>> listPullRequests(
    String repositoryRoot,
  ) async {
    final json =
        await runJson(repositoryRoot, const <String>[
              'pr',
              'list',
              '--limit',
              '50',
              '--json',
              'number,title,author,headRefName,isDraft,reviewDecision,url',
            ])
            as List<Object?>;
    return json
        .cast<Map<String, Object?>>()
        .map((item) {
          final author = item['author'] as Map<String, Object?>?;
          return HostingPullRequest(
            id: '${item['number']}',
            title: '${item['title']}',
            author: '${author?['login'] ?? ''}',
            branch: '${item['headRefName'] ?? ''}',
            url: '${item['url'] ?? ''}',
            isDraft: item['isDraft'] == true,
            state: '${item['reviewDecision'] ?? 'open'}',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<HostingIssue>> listIssues(String repositoryRoot) async {
    final json =
        await runJson(repositoryRoot, const <String>[
              'issue',
              'list',
              '--limit',
              '50',
              '--json',
              'number,title,author,labels,url',
            ])
            as List<Object?>;
    return json
        .cast<Map<String, Object?>>()
        .map((item) {
          final author = item['author'] as Map<String, Object?>?;
          final labels = item['labels'] as List<Object?>? ?? const <Object?>[];
          return HostingIssue(
            id: '${item['number']}',
            title: '${item['title']}',
            author: '${author?['login'] ?? ''}',
            url: '${item['url'] ?? ''}',
            labels: labels
                .map((label) => '${(label as Map<String, Object?>)['name']}')
                .toList(),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> checkoutPullRequest(String repositoryRoot, String id) =>
      runChecked(repositoryRoot, <String>['pr', 'checkout', id]);
}

class GitLabCliProvider extends CliHostingProvider {
  const GitLabCliProvider() : super('glab');
  @override
  HostingKind get kind => HostingKind.gitlab;
  @override
  String get displayName => 'GitLab (glab CLI)';
  @override
  List<String> get availabilityArguments => const <String>['auth', 'status'];

  @override
  Future<List<HostingPullRequest>> listPullRequests(
    String repositoryRoot,
  ) async {
    final json =
        await runJson(repositoryRoot, const <String>[
              'mr',
              'list',
              '--output',
              'json',
            ])
            as List<Object?>;
    return json
        .cast<Map<String, Object?>>()
        .map((item) {
          final author = item['author'] as Map<String, Object?>?;
          return HostingPullRequest(
            id: '${item['iid'] ?? item['id']}',
            title: '${item['title']}',
            author: '${author?['username'] ?? author?['name'] ?? ''}',
            branch: '${item['source_branch'] ?? ''}',
            url: '${item['web_url'] ?? ''}',
            isDraft: item['draft'] == true || item['work_in_progress'] == true,
            state: '${item['state'] ?? 'open'}',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<HostingIssue>> listIssues(String repositoryRoot) async {
    final json =
        await runJson(repositoryRoot, const <String>[
              'issue',
              'list',
              '--output',
              'json',
            ])
            as List<Object?>;
    return json
        .cast<Map<String, Object?>>()
        .map((item) {
          final author = item['author'] as Map<String, Object?>?;
          final labels = item['labels'] as List<Object?>? ?? const <Object?>[];
          return HostingIssue(
            id: '${item['iid'] ?? item['id']}',
            title: '${item['title']}',
            author: '${author?['username'] ?? author?['name'] ?? ''}',
            url: '${item['web_url'] ?? ''}',
            labels: labels
                .map(
                  (label) => label is String
                      ? label
                      : '${(label as Map<String, Object?>)['name']}',
                )
                .toList(),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> checkoutPullRequest(String repositoryRoot, String id) =>
      runChecked(repositoryRoot, <String>['mr', 'checkout', id]);
}

class BitbucketCliProvider extends CliHostingProvider {
  const BitbucketCliProvider() : super('bb');
  @override
  HostingKind get kind => HostingKind.bitbucket;
  @override
  String get displayName => 'Bitbucket (bb CLI)';
  @override
  List<String> get availabilityArguments => const <String>['--version'];

  @override
  Future<List<HostingPullRequest>> listPullRequests(
    String repositoryRoot,
  ) async {
    final json =
        await runJson(repositoryRoot, const <String>['pr', 'list', '--json'])
            as List<Object?>;
    return json
        .cast<Map<String, Object?>>()
        .map(
          (item) => HostingPullRequest(
            id: '${item['id']}',
            title: '${item['title']}',
            author: '${item['author'] ?? ''}',
            branch: '${item['branch'] ?? ''}',
            url: '${item['url'] ?? ''}',
            state: '${item['state'] ?? 'open'}',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<HostingIssue>> listIssues(String repositoryRoot) async {
    final json =
        await runJson(repositoryRoot, const <String>['issue', 'list', '--json'])
            as List<Object?>;
    return json
        .cast<Map<String, Object?>>()
        .map(
          (item) => HostingIssue(
            id: '${item['id']}',
            title: '${item['title']}',
            author: '${item['author'] ?? ''}',
            url: '${item['url'] ?? ''}',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> checkoutPullRequest(String repositoryRoot, String id) =>
      runChecked(repositoryRoot, <String>['pr', 'checkout', id]);
}

const hostingProviders = <GitHostingProvider>[
  GitHubCliProvider(),
  GitLabCliProvider(),
  BitbucketCliProvider(),
];
