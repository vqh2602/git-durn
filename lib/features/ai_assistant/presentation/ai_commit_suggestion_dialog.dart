import 'package:flutter/material.dart';

import '../../../core/ai/ai_models.dart';
import '../../repositories/application/repository_workspace_controller.dart';

class AiCommitSuggestionDialog extends StatefulWidget {
  const AiCommitSuggestionDialog({
    required this.controller,
    required this.conventional,
    super.key,
  });

  final RepositoryWorkspaceController controller;
  final bool conventional;

  @override
  State<AiCommitSuggestionDialog> createState() =>
      _AiCommitSuggestionDialogState();
}

class _AiCommitSuggestionDialogState extends State<AiCommitSuggestionDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.generateCommitMessage(),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Local AI commit suggestion'),
    content: SizedBox(
      width: 620,
      height: 420,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final suggestion = widget.controller.aiSuggestion;
          if (widget.controller.aiError case final error?) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Manual commit remains available. AI never commits automatically.',
                ),
              ],
            );
          }
          if (suggestion != null) {
            return _SuggestionPreview(
              suggestion: suggestion,
              conventional: widget.conventional,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              const Text('Loading the selected local model and generating…'),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    widget.controller.aiStreamText,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => TextButton(
          onPressed: widget.controller.isGeneratingCommit
              ? null
              : widget.controller.generateCommitMessage,
          child: const Text('Regenerate'),
        ),
      ),
      AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => FilledButton(
          onPressed: widget.controller.aiSuggestion == null
              ? null
              : () => Navigator.pop(context, widget.controller.aiSuggestion),
          child: const Text('Apply to editor'),
        ),
      ),
    ],
  );
}

class _SuggestionPreview extends StatelessWidget {
  const _SuggestionPreview({
    required this.suggestion,
    required this.conventional,
  });
  final GeneratedCommit suggestion;
  final bool conventional;
  @override
  Widget build(BuildContext context) => ListView(
    children: <Widget>[
      const Text('SUMMARY', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      SelectableText(suggestion.summary(conventional: conventional)),
      const SizedBox(height: 18),
      const Text('DESCRIPTION', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      SelectableText(
        suggestion.body.isEmpty ? 'No description suggested.' : suggestion.body,
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 8,
        children: <Widget>[
          Chip(label: Text(suggestion.type)),
          if (suggestion.scope.isNotEmpty) Chip(label: Text(suggestion.scope)),
          if (suggestion.breakingChange)
            const Chip(label: Text('BREAKING CHANGE')),
        ],
      ),
      const SizedBox(height: 12),
      const Text('Review, apply it to the editor, then press Commit yourself.'),
    ],
  );
}
