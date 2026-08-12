import 'ai_models.dart';

abstract class AiProvider {
  const AiProvider();
  Stream<String> generateCommitStream(CommitAiContext context);

  Future<GeneratedCommit> generateCommit(CommitAiContext context) async {
    final output = await generateCommitStream(context).join();
    return GeneratedCommit.parse(output);
  }
}
