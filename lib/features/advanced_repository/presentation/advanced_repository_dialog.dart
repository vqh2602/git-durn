import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/application/repository_providers.dart';
import '../../repositories/application/repository_workspace_controller.dart';

class AdvancedRepositoryDialog extends ConsumerWidget {
  const AdvancedRepositoryDialog({
    required this.rootPath,
    required this.controller,
    super.key,
  });

  final String rootPath;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog.fullscreen(
      child: DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Advanced Repository Tools'),
            bottom: const TabBar(
              isScrollable: true,
              tabs: <Widget>[
                Tab(text: 'Worktrees'),
                Tab(text: 'Submodules'),
                Tab(text: 'Git LFS'),
                Tab(text: 'Reflog'),
                Tab(text: 'File History & Blame'),
                Tab(text: 'Patch'),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
          body: TabBarView(
            children: <Widget>[
              _WorktreesTab(rootPath: rootPath, controller: controller),
              _SubmodulesTab(rootPath: rootPath, controller: controller),
              _LfsTab(rootPath: rootPath, controller: controller),
              _ReflogTab(rootPath: rootPath, controller: controller),
              _FileToolsTab(rootPath: rootPath),
              _PatchTab(rootPath: rootPath, controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorktreesTab extends ConsumerWidget {
  const _WorktreesTab({required this.rootPath, required this.controller});
  final String rootPath;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worktrees = ref.watch(repositoryWorktreesProvider(rootPath));
    return Column(
      children: <Widget>[
        _Actions(
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              label: const Text('Create worktree'),
            ),
            OutlinedButton(
              onPressed: controller.pruneWorktrees,
              child: const Text('Prune'),
            ),
          ],
        ),
        Expanded(
          child: worktrees.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(error.toString())),
            data: (items) => ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Icon(
                    item.isLocked ? Icons.lock : Icons.folder_copy_outlined,
                  ),
                  title: Text(
                    item.branch ??
                        (item.isDetached
                            ? 'Detached HEAD'
                            : item.head.substring(
                                0,
                                item.head.length.clamp(0, 8),
                              )),
                  ),
                  subtitle: Text(item.path),
                  trailing: Wrap(
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Open as repository tab',
                        onPressed: () => ref
                            .read(repositoryTabsProvider.notifier)
                            .openPath(item.path),
                        icon: const Icon(Icons.open_in_new),
                      ),
                      IconButton(
                        tooltip: item.isLocked ? 'Unlock' : 'Lock',
                        onPressed: () => controller.setWorktreeLock(
                          item.path,
                          locked: !item.isLocked,
                        ),
                        icon: Icon(
                          item.isLocked ? Icons.lock_open : Icons.lock_outline,
                        ),
                      ),
                      if (item.path != rootPath)
                        IconButton(
                          tooltip: 'Remove worktree',
                          onPressed: () => _remove(context, item.path),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final path = await getDirectoryPath(confirmButtonText: 'Use folder');
    if (path == null || !context.mounted) return;
    final branchController = TextEditingController();
    var createBranch = false;
    final value = await showDialog<({String branch, bool create})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create worktree'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(path),
              TextField(
                controller: branchController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Existing or new branch',
                ),
              ),
              CheckboxListTile(
                value: createBranch,
                onChanged: (value) =>
                    setState(() => createBranch = value ?? false),
                title: const Text('Create this branch'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                branch: branchController.text.trim(),
                create: createBranch,
              )),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    branchController.dispose();
    if (value != null && value.branch.isNotEmpty) {
      await controller.createWorktree(
        path: path,
        branch: value.branch,
        createBranch: value.create,
      );
    }
  }

  Future<void> _remove(BuildContext context, String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove worktree?'),
        content: Text(path),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.removeWorktree(path);
  }
}

class _SubmodulesTab extends ConsumerWidget {
  const _SubmodulesTab({required this.rootPath, required this.controller});
  final String rootPath;
  final RepositoryWorkspaceController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(repositorySubmodulesProvider(rootPath));
    return Column(
      children: <Widget>[
        _Actions(
          children: <Widget>[
            FilledButton.tonal(
              onPressed: controller.updateSubmodules,
              child: const Text('Initialize & Update Recursive'),
            ),
            OutlinedButton(
              onPressed: controller.syncSubmodules,
              child: const Text('Sync URLs'),
            ),
          ],
        ),
        Expanded(
          child: modules.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(error.toString())),
            data: (items) => items.isEmpty
                ? const Center(child: Text('No submodules configured.'))
                : ListView(
                    children: <Widget>[
                      for (final item in items)
                        ListTile(
                          leading: const Icon(Icons.folder_special_outlined),
                          title: Text(item.path),
                          subtitle: Text(
                            '${item.commit.substring(0, 8)} · ${item.state}${item.description == null ? '' : ' · ${item.description}'}',
                          ),
                          trailing: IconButton(
                            onPressed: () => ref
                                .read(repositoryTabsProvider.notifier)
                                .openPath('$rootPath/${item.path}'),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _LfsTab extends ConsumerStatefulWidget {
  const _LfsTab({required this.rootPath, required this.controller});
  final String rootPath;
  final RepositoryWorkspaceController controller;
  @override
  ConsumerState<_LfsTab> createState() => _LfsTabState();
}

class _LfsTabState extends ConsumerState<_LfsTab> {
  final pattern = TextEditingController();
  @override
  void dispose() {
    pattern.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lfs = ref.watch(repositoryLfsProvider(widget.rootPath));
    return lfs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (status) => status.isInstalled
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: () => widget.controller.lfsAction('install'),
                        child: const Text('Initialize'),
                      ),
                      OutlinedButton(
                        onPressed: () => widget.controller.lfsAction('fetch'),
                        child: const Text('Fetch'),
                      ),
                      OutlinedButton(
                        onPressed: () => widget.controller.lfsAction('pull'),
                        child: const Text('Pull'),
                      ),
                      OutlinedButton(
                        onPressed: () => widget.controller.lfsAction('prune'),
                        child: const Text('Prune'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: pattern,
                          decoration: const InputDecoration(
                            labelText: 'Track pattern',
                            hintText: '*.psd',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => widget.controller.lfsAction(
                          'track',
                          pattern: pattern.text.trim(),
                        ),
                        child: const Text('Track'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Tracked patterns (${status.patterns.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final value in status.patterns)
                    ListTile(
                      title: Text(value),
                      trailing: IconButton(
                        onPressed: () => widget.controller.lfsAction(
                          'untrack',
                          pattern: value,
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ),
                ],
              ),
            )
          : const Center(
              child: Text(
                'Git LFS is not installed. Install Git LFS for this section.',
              ),
            ),
    );
  }
}

class _ReflogTab extends ConsumerWidget {
  const _ReflogTab({required this.rootPath, required this.controller});
  final String rootPath;
  final RepositoryWorkspaceController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reflog = ref.watch(repositoryReflogProvider(rootPath));
    return reflog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (items) => ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: Text(item.selector),
            title: Text(item.subject),
            subtitle: Text('${item.shortHash} · ${item.date?.toLocal() ?? ''}'),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'branch') _branch(context, item.hash);
                if (action == 'reset') {
                  controller.resetTo(item.hash, mode: 'mixed');
                }
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem(
                  value: 'branch',
                  child: Text('Create branch here…'),
                ),
                PopupMenuItem(value: 'reset', child: Text('Mixed reset here')),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _branch(BuildContext context, String hash) async {
    final input = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create recovery branch'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Branch name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null && name.isNotEmpty) {
      await controller.createBranch(name, startPoint: hash);
    }
  }
}

class _FileToolsTab extends ConsumerStatefulWidget {
  const _FileToolsTab({required this.rootPath});
  final String rootPath;
  @override
  ConsumerState<_FileToolsTab> createState() => _FileToolsTabState();
}

class _FileToolsTabState extends ConsumerState<_FileToolsTab> {
  final path = TextEditingController();
  bool ignoreWhitespace = false;
  bool loaded = false;
  @override
  void dispose() {
    path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = loaded
        ? ref.watch(
            repositoryFileHistoryProvider((
              rootPath: widget.rootPath,
              path: path.text.trim(),
            )),
          )
        : null;
    final blame = loaded
        ? ref.watch(
            repositoryBlameProvider((
              rootPath: widget.rootPath,
              path: path.text.trim(),
              ignoreWhitespace: ignoreWhitespace,
            )),
          )
        : null;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: path,
                  decoration: const InputDecoration(
                    labelText: 'Repository-relative file path',
                  ),
                ),
              ),
              Checkbox(
                value: ignoreWhitespace,
                onChanged: (value) =>
                    setState(() => ignoreWhitespace = value ?? false),
              ),
              const Text('Ignore whitespace'),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    setState(() => loaded = path.text.trim().isNotEmpty),
                child: const Text('Load'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: <Widget>[
              Expanded(
                child: _AsyncList(
                  title: 'FILE HISTORY',
                  value: history,
                  row: (item) => ListTile(
                    title: Text(item.subject),
                    subtitle: Text('${item.shortHash} · ${item.authorName}'),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _AsyncList(
                  title: 'BLAME',
                  value: blame,
                  row: (item) => ListTile(
                    dense: true,
                    leading: Text('${item.lineNumber}'),
                    title: Text(
                      item.content,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    subtitle: Text(
                      '${item.hash.substring(0, item.hash.length.clamp(0, 8))} · ${item.author}',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PatchTab extends ConsumerStatefulWidget {
  const _PatchTab({required this.rootPath, required this.controller});
  final String rootPath;
  final RepositoryWorkspaceController controller;
  @override
  ConsumerState<_PatchTab> createState() => _PatchTabState();
}

class _PatchTabState extends ConsumerState<_PatchTab> {
  final patch = TextEditingController();
  @override
  void dispose() {
    patch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final working = ref.watch(repositoryWorkingPatchProvider(widget.rootPath));
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              FilledButton.tonal(
                onPressed: working.value == null
                    ? null
                    : () {
                        patch.text = working.value!;
                        setState(() {});
                      },
                child: const Text('Preview working changes'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _load,
                child: const Text('Load patch file'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: patch.text.trim().isEmpty
                    ? null
                    : () => widget.controller.applyPatch(patch.text),
                child: const Text('Apply with 3-way fallback'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: patch,
              onChanged: (_) => setState(() {}),
              expands: true,
              minLines: null,
              maxLines: null,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste or load a patch to preview it here.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Patch', extensions: <String>['patch', 'diff']),
      ],
    );
    if (file == null) return;
    patch.text = await File(file.path).readAsString();
    setState(() {});
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(children: children),
  );
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.title,
    required this.value,
    required this.row,
  });
  final String title;
  final AsyncValue<List<T>>? value;
  final Widget Function(T item) row;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Padding(padding: const EdgeInsets.all(10), child: Text(title)),
      Expanded(
        child: value == null
            ? const Center(child: Text('Enter a path to load data.'))
            : value!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text(error.toString())),
                data: (items) => ListView(
                  children: <Widget>[for (final item in items) row(item)],
                ),
              ),
      ),
    ],
  );
}
