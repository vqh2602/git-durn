import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_status.dart';
import '../../repositories/application/repository_providers.dart';
import '../../repositories/application/repository_workspace_controller.dart';
import '../domain/conflict_document.dart';

class ConflictEditorDialog extends ConsumerStatefulWidget {
  const ConflictEditorDialog({
    required this.rootPath,
    required this.file,
    required this.controller,
    super.key,
  });

  final String rootPath;
  final GitFileStatus file;
  final RepositoryWorkspaceController controller;

  @override
  ConsumerState<ConflictEditorDialog> createState() =>
      _ConflictEditorDialogState();
}

class _ConflictEditorDialogState extends ConsumerState<ConflictEditorDialog> {
  TextEditingController? _resultController;
  String? _initializedFrom;

  @override
  void dispose() {
    _resultController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(
      repositoryConflictDocumentProvider((
        rootPath: widget.rootPath,
        path: widget.file.path,
      )),
    );
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Resolve conflict · ${widget.file.path}'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
        body: document.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(error.toString())),
          data: _buildEditor,
        ),
      ),
    );
  }

  Widget _buildEditor(ConflictDocument document) {
    if (document.isBinary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, size: 46),
            const SizedBox(height: 12),
            const Text('Binary file conflict. Text merging is disabled.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: () => widget.controller.resolveConflict(
                    widget.file,
                    ours: true,
                  ),
                  child: const Text('Use ours'),
                ),
                FilledButton.tonal(
                  onPressed: () => widget.controller.resolveConflict(
                    widget.file,
                    ours: false,
                  ),
                  child: const Text('Use theirs'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (_initializedFrom != document.result) {
      _resultController?.dispose();
      _resultController = TextEditingController(text: document.result);
      _initializedFrom = document.result;
    }
    final result = _resultController!.text;
    final blocks = ConflictDocument.parseBlocks(result);
    return Column(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: Row(
            children: <Widget>[
              Expanded(
                child: _ReadOnlyPane(title: 'BASE', text: document.base),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _ReadOnlyPane(title: 'OURS', text: document.ours),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _ReadOnlyPane(title: 'THEIRS', text: document.theirs),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (blocks.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: blocks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SegmentedButton<ConflictChoice>(
                emptySelectionAllowed: true,
                segments: const <ButtonSegment<ConflictChoice>>[
                  ButtonSegment(
                    value: ConflictChoice.ours,
                    label: Text('Ours'),
                  ),
                  ButtonSegment(
                    value: ConflictChoice.theirs,
                    label: Text('Theirs'),
                  ),
                  ButtonSegment(
                    value: ConflictChoice.both,
                    label: Text('Both'),
                  ),
                  ButtonSegment(
                    value: ConflictChoice.neither,
                    label: Text('Neither'),
                  ),
                ],
                selected: const <ConflictChoice>{},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  _resolveBlock(blocks[index], selection.first);
                },
              ),
            ),
          ),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  children: <Widget>[
                    Text('RESULT · ${blocks.length} unresolved block(s)'),
                    const Spacer(),
                    TextButton(
                      onPressed: _save,
                      child: const Text('Save result'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: blocks.isEmpty ? _saveAndResolve : null,
                      child: const Text('Save & Mark Resolved'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _resultController,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _resolveBlock(ConflictBlock block, ConflictChoice choice) {
    final next = ConflictDocument.resolveBlock(
      _resultController!.text,
      block,
      choice,
    );
    _resultController!.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: block.startOffset),
    );
    setState(() {});
  }

  Future<void> _save() => widget.controller.saveConflictResult(
    widget.file,
    _resultController!.text,
  );

  Future<void> _saveAndResolve() async {
    await widget.controller.saveConflictResult(
      widget.file,
      _resultController!.text,
      markResolvedAfterSave: true,
    );
    if (mounted && widget.controller.error == null) Navigator.pop(context);
  }
}

class _ReadOnlyPane extends StatelessWidget {
  const _ReadOnlyPane({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(padding: const EdgeInsets.all(8), child: Text(title)),
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Text(
                text.isEmpty ? 'Not available for this conflict type.' : text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
