class BranchInfo {
  const BranchInfo({
    required this.fullName,
    required this.name,
    required this.objectId,
    required this.subject,
    required this.isCurrent,
    required this.isRemote,
    this.upstream,
  });

  final String fullName;
  final String name;
  final String objectId;
  final String subject;
  final bool isCurrent;
  final bool isRemote;
  final String? upstream;
}

class RemoteInfo {
  const RemoteInfo({
    required this.name,
    required this.fetchUrl,
    required this.pushUrl,
  });

  final String name;
  final String fetchUrl;
  final String pushUrl;
}
