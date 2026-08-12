import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import 'ai_models.dart';
import 'ai_provider.dart';

class LocalCommitAiProvider extends AiProvider {
  const LocalCommitAiProvider({required this.modelPath});

  final String modelPath;

  @override
  Stream<String> generateCommitStream(CommitAiContext context) async* {
    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        modelPath,
        modelParams: const ModelParams(contextSize: 4096, gpuLayers: 99),
      );
      final prompt =
          '''You are a Git commit message assistant. Think briefly, then return exactly one JSON object and no markdown.
Schema: {"type":"feat|fix|refactor|docs|test|chore","scope":"","subject":"imperative summary","body":"details","breaking_change":false}
Branch: ${context.branch}
Staged files: ${jsonEncode(context.stagedFiles)}
Recent commit convention: ${jsonEncode(context.recentSubjects)}
Omitted generated/noise files: ${context.omittedFiles}
Redacted secrets: ${context.redactedSecrets}
Staged diff:
${context.diff}
''';
      await for (final chunk in engine.create(
        <LlamaChatMessage>[
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
        ],
        params: const GenerationParams(
          maxTokens: 512,
          temp: 0.2,
          topP: 0.9,
          thinkingBudget: ThinkingBudget(maxTokens: 128),
        ),
      )) {
        final content = chunk.choices.first.delta.content;
        if (content != null && content.isNotEmpty) yield content;
      }
    } finally {
      await engine.dispose();
    }
  }
}
