import 'package:flutter/material.dart';

import '../domain/git_diff.dart';
import '../domain/git_patch.dart';

class HunkDiffView extends StatefulWidget {
  const HunkDiffView({
    required this.diff,
    required this.onApplyPatch,
    required this.onDiscardPatch,
    super.key,
  });

  final GitDiff diff;
  final ValueChanged<String> onApplyPatch;
  final ValueChanged<String>? onDiscardPatch;

  @override
  State<HunkDiffView> createState() => _HunkDiffViewState();
}

class _HunkDiffViewState extends State<HunkDiffView> {
  final Map<int, Set<int>> _selectedLines = <int, Set<int>>{};

  @override
  void didUpdateWidget(covariant HunkDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diff.text != widget.diff.text) _selectedLines.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.diff.isBinary) {
      return Center(child: Text('Binary file: ${widget.diff.path}'));
    }
    if (widget.diff.text.isEmpty) {
      return const Center(child: Text('No textual diff for this selection.'));
    }
    final patch = GitPatch.parse(widget.diff.text);
    if (patch.hunks.isEmpty) {
      return SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.diff.text,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        if (_selectedLines.values.any((lines) => lines.isNotEmpty))
          Material(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.08),
            child: ListTile(
              dense: true,
              title: Text(
                '${_selectedLines.values.fold<int>(0, (sum, value) => sum + value.length)} changed lines selected',
              ),
              trailing: FilledButton.tonal(
                onPressed: () =>
                    widget.onApplyPatch(patch.patchForLines(_selectedLines)),
                child: Text(
                  widget.diff.isStaged ? 'Unstage lines' : 'Stage lines',
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: patch.hunks.length,
            itemBuilder: (context, hunkIndex) {
              final hunk = patch.hunks[hunkIndex];
              return _HunkCard(
                hunk: hunk,
                staged: widget.diff.isStaged,
                selected: _selectedLines[hunkIndex] ?? const <int>{},
                onLineChanged: (lineIndex, value) {
                  setState(() {
                    final lines = _selectedLines.putIfAbsent(
                      hunkIndex,
                      () => <int>{},
                    );
                    value ? lines.add(lineIndex) : lines.remove(lineIndex);
                  });
                },
                onApply: () =>
                    widget.onApplyPatch(patch.patchForHunks(<int>[hunkIndex])),
                onDiscard: widget.onDiscardPatch == null
                    ? null
                    : () => widget.onDiscardPatch!(
                        patch.patchForHunks(<int>[hunkIndex]),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HunkCard extends StatelessWidget {
  const _HunkCard({
    required this.hunk,
    required this.staged,
    required this.selected,
    required this.onLineChanged,
    required this.onApply,
    required this.onDiscard,
  });

  final GitPatchHunk hunk;
  final bool staged;
  final Set<int> selected;
  final void Function(int lineIndex, bool value) onLineChanged;
  final VoidCallback onApply;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Container(
            color: colors.primary.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    hunk.header,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onApply,
                  child: Text(staged ? 'Unstage hunk' : 'Stage hunk'),
                ),
                if (onDiscard != null)
                  TextButton(
                    onPressed: onDiscard,
                    child: const Text('Discard hunk'),
                  ),
              ],
            ),
          ),
          for (var index = 0; index < hunk.lines.length; index++)
            _PatchLine(
              text: hunk.lines[index],
              selected: selected.contains(index),
              onChanged: _isChange(hunk.lines[index])
                  ? (value) => onLineChanged(index, value)
                  : null,
            ),
        ],
      ),
    );
  }

  static bool _isChange(String line) =>
      (line.startsWith('+') && !line.startsWith('+++')) ||
      (line.startsWith('-') && !line.startsWith('---'));
}

class _PatchLine extends StatelessWidget {
  const _PatchLine({
    required this.text,
    required this.selected,
    required this.onChanged,
  });
  final String text;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final added = text.startsWith('+');
    final removed = text.startsWith('-');
    return ColoredBox(
      color: added
          ? Colors.green.withValues(alpha: 0.10)
          : removed
          ? colors.error.withValues(alpha: 0.10)
          : Colors.transparent,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            height: 24,
            child: onChanged == null
                ? null
                : Checkbox(
                    value: selected,
                    onChanged: (value) => onChanged!(value ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
          ),
          Expanded(
            child: SelectionArea(
              child: Text(
                text.isEmpty ? ' ' : text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
