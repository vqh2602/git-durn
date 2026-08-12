enum HostingKind { github, gitlab, bitbucket }

class HostingPullRequest {
  const HostingPullRequest({
    required this.id,
    required this.title,
    required this.author,
    required this.branch,
    required this.url,
    this.isDraft = false,
    this.state = 'open',
  });

  final String id;
  final String title;
  final String author;
  final String branch;
  final String url;
  final bool isDraft;
  final String state;
}

class HostingIssue {
  const HostingIssue({
    required this.id,
    required this.title,
    required this.author,
    required this.url,
    this.labels = const <String>[],
  });

  final String id;
  final String title;
  final String author;
  final String url;
  final List<String> labels;
}
