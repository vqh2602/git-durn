import '../domain/branch_info.dart';

class GitBranchParser {
  const GitBranchParser();

  List<BranchInfo> parse(String output) {
    final branches = <BranchInfo>[];
    for (final line in output.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\x00');
      if (fields.length < 6) {
        throw const FormatException('Malformed structured branch record.');
      }
      final fullName = fields[0];
      branches.add(
        BranchInfo(
          fullName: fullName,
          name: fields[1],
          isCurrent: fields[2] == '*',
          upstream: fields[3].isEmpty ? null : fields[3],
          objectId: fields[4],
          subject: fields[5],
          isRemote: fullName.startsWith('refs/remotes/'),
        ),
      );
    }
    return List<BranchInfo>.unmodifiable(branches);
  }
}
