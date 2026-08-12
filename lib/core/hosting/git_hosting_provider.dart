import 'hosting_models.dart';

abstract interface class GitHostingProvider {
  HostingKind get kind;
  String get displayName;
  Future<bool> isAvailable();
  Future<List<HostingPullRequest>> listPullRequests(String repositoryRoot);
  Future<List<HostingIssue>> listIssues(String repositoryRoot);
  Future<void> checkoutPullRequest(String repositoryRoot, String id);
}
