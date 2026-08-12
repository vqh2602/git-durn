import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_model_catalog.dart';
import '../../../core/ai/ai_model_manager.dart';
import '../../repositories/application/repository_providers.dart';

class AiSettingsDialog extends ConsumerWidget {
  const AiSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(aiModelManagerProvider);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings · Local AI'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
        body: manager.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
          data: (value) => AnimatedBuilder(
            animation: value,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                Text(
                  'AI chạy hoàn toàn trên máy',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Chọn một model GGUF nhẹ. File tải dở được giữ với đuôi .part và lần tải sau tiếp tục bằng HTTP Range. Model chỉ được cài sau khi đúng kích thước và SHA-256.',
                ),
                const SizedBox(height: 22),
                for (final model in aiModelCatalog)
                  _ModelCard(model: model, manager: value),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.model, required this.manager});
  final AiModelCatalogItem model;
  final AiModelManager manager;

  @override
  Widget build(BuildContext context) {
    final state = manager.stateFor(model);
    final selected = manager.selectedModelId == model.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: selected ? 'Selected model' : 'Select model',
                  onPressed: state.phase == AiModelDownloadPhase.installed
                      ? () => manager.select(model)
                      : null,
                  icon: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        model.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${model.sizeLabel} · ${model.description}'),
                    ],
                  ),
                ),
                if (selected)
                  const Chip(
                    avatar: Icon(Icons.check, size: 16),
                    label: Text('Selected'),
                  ),
                const SizedBox(width: 8),
                _action(state),
              ],
            ),
            if (state.phase == AiModelDownloadPhase.downloading ||
                state.phase == AiModelDownloadPhase.paused ||
                state.phase == AiModelDownloadPhase.verifying) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: state.phase == AiModelDownloadPhase.verifying
                    ? null
                    : state.progress,
              ),
              const SizedBox(height: 5),
              Text(
                state.phase == AiModelDownloadPhase.verifying
                    ? 'Verifying SHA-256…'
                    : '${_bytes(state.receivedBytes)} / ${_bytes(state.totalBytes)}${state.phase == AiModelDownloadPhase.paused ? ' · Paused, ready to resume' : ''}',
              ),
            ],
            if (state.error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(AiModelDownloadState state) => switch (state.phase) {
    AiModelDownloadPhase.downloading => OutlinedButton(
      onPressed: manager.pause,
      child: const Text('Pause'),
    ),
    AiModelDownloadPhase.verifying => const SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    AiModelDownloadPhase.installed => OutlinedButton(
      onPressed: () => manager.delete(model),
      child: const Text('Delete'),
    ),
    AiModelDownloadPhase.paused => FilledButton.tonal(
      onPressed: () => manager.download(model),
      child: const Text('Resume'),
    ),
    AiModelDownloadPhase.failed => FilledButton.tonal(
      onPressed: () => manager.download(model),
      child: const Text('Retry / Resume'),
    ),
    AiModelDownloadPhase.idle => FilledButton(
      onPressed: () => manager.download(model),
      child: const Text('Download'),
    ),
  };

  static String _bytes(int value) =>
      '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
}
