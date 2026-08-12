import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/git/git_executable_locator.dart';
import '../../../../core/git/git_status.dart';
import '../../../branches/domain/branch_info.dart';
import '../../../commits/domain/commit_node.dart';
import '../../../conflicts/domain/repository_operation_state.dart';
import '../../../diff/domain/git_diff.dart';
import '../../../stash/domain/stash_entry.dart';
import '../../../terminal/presentation/repository_terminal_panel.dart';
import '../../application/repository_providers.dart';
import '../../application/repository_workspace_controller.dart';
import '../../domain/repository_session.dart';

class RepositoryWorkspace extends ConsumerStatefulWidget {
  const RepositoryWorkspace({
    required this.session,
    required this.git,
    super.key,
  });

  final RepositorySession session;
  final GitInstallation git;

  @override
  ConsumerState<RepositoryWorkspace> createState() =>
      _RepositoryWorkspaceState();
}

class _RepositoryWorkspaceState extends ConsumerState<RepositoryWorkspace> {
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _amend = false;
  bool _terminalVisible = false;

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rootPath = widget.session.rootPath;
    final controller = ref.watch(
      repositoryWorkspaceControllerProvider(rootPath),
    );
    final status = ref.watch(repositoryStatusProvider(rootPath));
    final branches = ref.watch(repositoryBranchesProvider(rootPath));
    final remotes = ref.watch(repositoryRemotesProvider(rootPath));
    final commits = ref.watch(repositoryCommitLogProvider(rootPath));
    final tags = ref.watch(repositoryTagsProvider(rootPath));
    final stashes = ref.watch(repositoryStashesProvider(rootPath));
    final operation = ref.watch(repositoryOperationStateProvider(rootPath));
    final tokens = context.gitTheme;

    return Column(
      children: <Widget>[
        _Toolbar(
          status: status,
          branches: branches,
          controller: controller,
          stashes: stashes,
          onCreateBranch: () => _showCreateBranch(context, controller),
          onCreateTag: () => _showCreateTag(context, controller),
          onToggleTerminal: () =>
              setState(() => _terminalVisible = !_terminalVisible),
          terminalVisible: _terminalVisible,
        ),
        if (operation.value case final operationState?)
          if (operationState.isInProgress)
            _InProgressOperationBanner(
              state: operationState,
              status: status,
              controller: controller,
            ),
        if (controller.error != null || controller.lastSuccess != null)
          _OperationMessage(controller: controller),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showCommitPanel = constraints.maxWidth >= 1000;
              final leftWidth = constraints.maxWidth >= 1180 ? 275.0 : 235.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: leftWidth,
                    child: _NavigationPanel(
                      status: status,
                      branches: branches,
                      remotes: remotes,
                      tags: tags,
                      stashes: stashes,
                      controller: controller,
                    ),
                  ),
                  VerticalDivider(width: 1, color: tokens.border),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          flex: 5,
                          child: _CommitGraphPanel(
                            commits: commits,
                            status: status,
                            controller: controller,
                          ),
                        ),
                        Divider(height: 1, color: tokens.border),
                        Expanded(
                          flex: 6,
                          child: _DiffPanel(
                            rootPath: rootPath,
                            controller: controller,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showCommitPanel) ...<Widget>[
                    VerticalDivider(width: 1, color: tokens.border),
                    SizedBox(
                      width: 330,
                      child: switch (controller.selectedCommit) {
                        final commit? => _CommitDetailsPanel(
                          commit: commit,
                          onClose: controller.clearSelection,
                        ),
                        null => _CommitEditorPanel(
                          status: status,
                          summaryController: _summaryController,
                          descriptionController: _descriptionController,
                          amend: _amend,
                          busy: controller.isBusy,
                          onAmendChanged: (value) =>
                              setState(() => _amend = value),
                          onCommit: () => _commit(controller),
                        ),
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        if (_terminalVisible)
          RepositoryTerminalPanel(repositoryRoot: widget.session.rootPath),
        _ActivityBar(
          controller: controller,
          session: widget.session,
          git: widget.git,
        ),
      ],
    );
  }

  Future<void> _commit(RepositoryWorkspaceController controller) async {
    await controller.commit(
      summary: _summaryController.text,
      description: _descriptionController.text,
      amend: _amend,
    );
    if (controller.error == null) {
      _summaryController.clear();
      _descriptionController.clear();
      setState(() => _amend = false);
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.status,
    required this.branches,
    required this.controller,
    required this.stashes,
    required this.onCreateBranch,
    required this.onCreateTag,
    required this.onToggleTerminal,
    required this.terminalVisible,
  });

  final AsyncValue<RepositoryStatus> status;
  final AsyncValue<List<BranchInfo>> branches;
  final RepositoryWorkspaceController controller;
  final AsyncValue<List<StashEntry>> stashes;
  final VoidCallback onCreateBranch;
  final VoidCallback onCreateTag;
  final VoidCallback onToggleTerminal;
  final bool terminalVisible;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'Checkout branch',
            enabled: !controller.isBusy,
            onSelected: controller.checkoutBranch,
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              for (final branch in branches.value ?? const <BranchInfo>[])
                if (!branch.isRemote)
                  PopupMenuItem<String>(
                    value: branch.name,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          branch.isCurrent ? Icons.check : Icons.call_split,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(branch.name),
                      ],
                    ),
                  ),
            ],
            child: Container(
              constraints: const BoxConstraints(minWidth: 150, maxWidth: 230),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: tokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.call_split,
                    size: 16,
                    color: tokens.graphLaneColors.first,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      status.value?.branch.displayName ?? 'Loading…',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.arrow_drop_down, size: 17),
                ],
              ),
            ),
          ),
          _ToolbarButton(
            icon: terminalVisible ? Icons.terminal : Icons.terminal_outlined,
            label: 'Terminal',
            onPressed: onToggleTerminal,
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            icon: Icons.sync,
            label: 'Fetch',
            onPressed: controller.isBusy ? null : controller.fetch,
          ),
          PopupMenuButton<String>(
            tooltip: 'Stash actions',
            enabled: !controller.isBusy,
            onSelected: (value) {
              if (value == 'create') _showCreateStash(context, controller);
              if (value == 'pop' && (stashes.value?.isNotEmpty ?? false)) {
                controller.applyStash(stashes.value!.first.selector, pop: true);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem(
                value: 'create',
                child: Text('Create stash…'),
              ),
              PopupMenuItem(
                value: 'pop',
                enabled: stashes.value?.isNotEmpty ?? false,
                child: const Text('Pop latest stash'),
              ),
            ],
            child: const _ToolbarLabel(
              icon: Icons.inventory_2_outlined,
              label: 'Stash',
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Pull options',
            enabled: !controller.isBusy,
            onSelected: (mode) => controller.pull(mode: mode),
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'merge', child: Text('Pull')),
              PopupMenuItem(value: 'rebase', child: Text('Pull --rebase')),
              PopupMenuItem(value: 'ff-only', child: Text('Pull --ff-only')),
            ],
            child: const _ToolbarLabel(icon: Icons.download, label: 'Pull'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Push options',
            enabled: !controller.isBusy,
            onSelected: (value) {
              if (value == 'normal') controller.push();
              if (value == 'upstream') controller.push(setUpstream: true);
              if (value == 'tags') controller.push(tags: true);
              if (value == 'lease') controller.push(forceWithLease: true);
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'normal', child: Text('Push')),
              PopupMenuItem(
                value: 'upstream',
                child: Text('Push and set upstream'),
              ),
              PopupMenuItem(value: 'tags', child: Text('Push tags')),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'lease',
                child: Text('Force push with lease'),
              ),
            ],
            child: const _ToolbarLabel(icon: Icons.upload, label: 'Push'),
          ),
          const SizedBox(width: 6),
          _ToolbarButton(
            icon: Icons.add_to_photos_outlined,
            label: 'Branch',
            onPressed: controller.isBusy ? null : onCreateBranch,
          ),
          _ToolbarButton(
            icon: Icons.sell_outlined,
            label: 'Tag',
            onPressed: controller.isBusy ? null : onCreateTag,
          ),
          const Spacer(),
          if (status.value case final value?)
            Text(
              '↑${value.branch.ahead}  ↓${value.branch.behind}',
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Refresh repository',
            onPressed: controller.isBusy ? null : controller.refresh,
            icon: const Icon(Icons.refresh, size: 19),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

class _ToolbarLabel extends StatelessWidget {
  const _ToolbarLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          Text(label),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.status,
    required this.branches,
    required this.remotes,
    required this.tags,
    required this.stashes,
    required this.controller,
  });

  final AsyncValue<RepositoryStatus> status;
  final AsyncValue<List<BranchInfo>> branches;
  final AsyncValue<List<RemoteInfo>> remotes;
  final AsyncValue<List<String>> tags;
  final AsyncValue<List<StashEntry>> stashes;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ColoredBox(
      color: tokens.backgroundSecondary,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _PanelSectionHeader(
              title: 'LOCAL BRANCHES',
              trailing:
                  branches.value
                      ?.where((branch) => !branch.isRemote)
                      .length
                      .toString() ??
                  '',
            ),
          ),
          if (branches.isLoading)
            const SliverToBoxAdapter(child: LinearProgressIndicator())
          else
            SliverList.list(
              children: <Widget>[
                for (final branch in branches.value ?? const <BranchInfo>[])
                  if (!branch.isRemote)
                    _BranchRow(branch: branch, controller: controller),
              ],
            ),
          const SliverToBoxAdapter(
            child: _PanelSectionHeader(title: 'REMOTES', trailing: ''),
          ),
          SliverList.list(
            children: <Widget>[
              for (final remote in remotes.value ?? const <RemoteInfo>[])
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud_outlined, size: 16),
                  title: Text(remote.name),
                  subtitle: Text(
                    remote.fetchUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if ((remotes.value ?? const <RemoteInfo>[]).isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: Text(
                    'No remotes configured.',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                ),
            ],
          ),
          _SimpleRefSection(
            title: 'TAGS',
            icon: Icons.sell_outlined,
            items: tags.value ?? const <String>[],
          ),
          SliverToBoxAdapter(
            child: _PanelSectionHeader(
              title: 'STASHES',
              trailing: '${stashes.value?.length ?? 0}',
            ),
          ),
          SliverList.list(
            children: <Widget>[
              for (final stash in stashes.value ?? const <StashEntry>[])
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.inventory_2_outlined, size: 15),
                  title: Text(stash.selector),
                  subtitle: Text(
                    stash.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'apply') {
                        controller.applyStash(stash.selector);
                      }
                      if (action == 'pop') {
                        controller.applyStash(stash.selector, pop: true);
                      }
                      if (action == 'drop') {
                        _confirmDropStash(context, controller, stash.selector);
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'apply', child: Text('Apply')),
                      PopupMenuItem(value: 'pop', child: Text('Pop')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'drop', child: Text('Drop')),
                    ],
                  ),
                ),
              if ((stashes.value ?? const <StashEntry>[]).isEmpty)
                const _EmptySection(text: 'No stashes.'),
            ],
          ),
          SliverToBoxAdapter(
            child: _WorkingTreeSection(status: status, controller: controller),
          ),
        ],
      ),
    );
  }
}

class _WorkingTreeSection extends StatelessWidget {
  const _WorkingTreeSection({required this.status, required this.controller});

  final AsyncValue<RepositoryStatus> status;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return status.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => _PanelError(error: error),
      data: (value) {
        final staged = value.files.where((file) => file.isStaged).toList();
        final changed = value.files
            .where(
              (file) =>
                  !file.isIgnored &&
                  (file.workTreeStatus != '.' || file.isUntracked),
            )
            .toList();
        final conflicted = value.files
            .where((file) => file.isConflicted)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _PanelSectionHeader(
              title: 'STAGED CHANGES',
              trailing: '${staged.length}',
              action: staged.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Unstage all',
                      onPressed: controller.isBusy
                          ? null
                          : controller.unstageAll,
                      icon: const Icon(Icons.remove_done, size: 16),
                    ),
            ),
            for (final file in staged)
              _FileRow(
                file: file,
                stagedView: true,
                selected:
                    controller.selectedFile?.path == file.path &&
                    controller.selectedFileStaged,
                onSelect: () => controller.selectFile(file, staged: true),
                onPrimaryAction: () => controller.unstage(file),
                primaryTooltip: 'Unstage file',
                primaryIcon: Icons.remove,
              ),
            if (staged.isEmpty)
              _EmptySection(text: 'Stage changes to prepare a commit.'),
            _PanelSectionHeader(
              title: 'CHANGES',
              trailing: '${changed.length}',
              action: changed.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Stage all',
                      onPressed: controller.isBusy ? null : controller.stageAll,
                      icon: const Icon(Icons.done_all, size: 16),
                    ),
            ),
            for (final file in changed)
              _FileRow(
                file: file,
                stagedView: false,
                selected:
                    controller.selectedFile?.path == file.path &&
                    !controller.selectedFileStaged,
                onSelect: () => controller.selectFile(file, staged: false),
                onPrimaryAction: file.isConflicted
                    ? null
                    : () => controller.stage(file),
                primaryTooltip: 'Stage file',
                primaryIcon: Icons.add,
                onDiscard: file.isConflicted
                    ? null
                    : () => _confirmDiscard(context, controller, file),
              ),
            if (changed.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline,
                      size: 17,
                      color: tokens.success,
                    ),
                    const SizedBox(width: 7),
                    const Text('Working tree clean'),
                  ],
                ),
              ),
            if (conflicted.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  '${conflicted.length} conflicted file(s) require resolution.',
                  style: TextStyle(color: tokens.danger),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.branch, required this.controller});

  final BranchInfo branch;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ListTile(
      dense: true,
      selected: branch.isCurrent,
      leading: Icon(
        branch.isCurrent ? Icons.radio_button_checked : Icons.call_split,
        size: 16,
        color: branch.isCurrent ? tokens.success : tokens.textSecondary,
      ),
      title: Text(branch.name, overflow: TextOverflow.ellipsis),
      subtitle: branch.upstream == null
          ? null
          : Text(branch.upstream!, overflow: TextOverflow.ellipsis),
      onTap: branch.isCurrent || controller.isBusy
          ? null
          : () => controller.checkoutBranch(branch.name),
      trailing: branch.isCurrent
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Branch actions',
              onSelected: (action) {
                if (action == 'checkout') {
                  controller.checkoutBranch(branch.name);
                }
                if (action == 'merge') controller.mergeBranch(branch.name);
                if (action == 'delete') {
                  _confirmDeleteBranch(context, controller, branch.name);
                }
              },
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem(value: 'checkout', child: Text('Checkout')),
                PopupMenuItem(
                  value: 'merge',
                  child: Text('Merge into current'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('Delete branch')),
              ],
            ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.stagedView,
    required this.selected,
    required this.onSelect,
    required this.onPrimaryAction,
    required this.primaryTooltip,
    required this.primaryIcon,
    this.onDiscard,
  });

  final GitFileStatus file;
  final bool stagedView;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onPrimaryAction;
  final String primaryTooltip;
  final IconData primaryIcon;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    final kind = stagedView && file.indexStatus == 'A'
        ? GitChangeKind.added
        : file.kind;
    final (label, color) = switch (kind) {
      GitChangeKind.added => ('A', tokens.success),
      GitChangeKind.deleted => ('D', tokens.danger),
      GitChangeKind.renamed => ('R', tokens.warning),
      GitChangeKind.copied => ('C', tokens.warning),
      GitChangeKind.untracked => ('?', tokens.textSecondary),
      GitChangeKind.ignored => ('!', tokens.textSecondary),
      GitChangeKind.conflicted => ('U', tokens.danger),
      GitChangeKind.typeChanged => ('T', tokens.warning),
      GitChangeKind.modified => ('M', tokens.warning),
      GitChangeKind.unknown => ('•', tokens.textSecondary),
    };
    return Material(
      color: selected
          ? tokens.graphLaneColors.first.withValues(alpha: 0.12)
          : null,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 3, bottom: 3),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 20,
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  file.path,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (onDiscard != null)
                IconButton(
                  tooltip: 'Discard with recovery snapshot',
                  onPressed: onDiscard,
                  icon: const Icon(Icons.undo, size: 14),
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                tooltip: primaryTooltip,
                onPressed: onPrimaryAction,
                icon: Icon(primaryIcon, size: 15),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitGraphPanel extends StatelessWidget {
  const _CommitGraphPanel({
    required this.commits,
    required this.status,
    required this.controller,
  });

  final AsyncValue<List<CommitNode>> commits;
  final AsyncValue<RepositoryStatus> status;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ColoredBox(
      color: tokens.backgroundPrimary,
      child: Column(
        children: <Widget>[
          _CenterPanelHeader(
            title: 'COMMIT GRAPH',
            trailing: commits.value == null
                ? ''
                : '${commits.value!.length} loaded',
          ),
          if (status.value case final value?)
            if (!value.isClean) _WipRow(status: value),
          Expanded(
            child: commits.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _PanelError(error: error),
              data: (items) => items.isEmpty
                  ? const Center(
                      child: Text('No commits yet. Create the first commit.'),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemExtent: 42,
                      itemBuilder: (context, index) {
                        final commit = items[index];
                        return _CommitRow(
                          commit: commit,
                          selected:
                              controller.selectedCommit?.hash == commit.hash,
                          lane: index % tokens.graphLaneColors.length,
                          onTap: () => controller.selectCommit(commit),
                          onAction: (action) => _handleCommitAction(
                            context,
                            controller,
                            commit,
                            action,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({
    required this.commit,
    required this.selected,
    required this.lane,
    required this.onTap,
    required this.onAction,
  });

  final CommitNode commit;
  final bool selected;
  final int lane;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    final laneColor = tokens.graphLaneColors[lane];
    return Material(
      color: selected ? tokens.surface : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 44,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(width: 2, color: laneColor.withValues(alpha: 0.55)),
                  Container(
                    width: commit.parents.length > 1 ? 14 : 11,
                    height: commit.parents.length > 1 ? 14 : 11,
                    decoration: BoxDecoration(
                      color: tokens.backgroundPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: laneColor, width: 2),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Commit actions',
              onSelected: onAction,
              itemBuilder: (context) => const <PopupMenuEntry<String>>[
                PopupMenuItem(
                  value: 'branch',
                  child: Text('Create branch here'),
                ),
                PopupMenuItem(value: 'tag', child: Text('Create tag here')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'cherry', child: Text('Cherry-pick')),
                PopupMenuItem(value: 'revert', child: Text('Revert')),
                PopupMenuItem(
                  value: 'reset',
                  child: Text('Reset branch here…'),
                ),
              ],
              icon: const Icon(Icons.more_horiz, size: 16),
            ),
            Expanded(
              child: Text(
                commit.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            for (final decoration in commit.decorations.take(2))
              Container(
                margin: const EdgeInsets.only(left: 5),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: laneColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: laneColor.withValues(alpha: 0.55)),
                ),
                child: Text(decoration, style: const TextStyle(fontSize: 10)),
              ),
            const SizedBox(width: 10),
            SizedBox(
              width: 68,
              child: Text(
                commit.shortHash,
                style: TextStyle(color: tokens.textSecondary, fontSize: 11),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                commit.authorName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffPanel extends ConsumerWidget {
  const _DiffPanel({required this.rootPath, required this.controller});

  final String rootPath;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = controller.selectedFile;
    if (file == null) {
      return const _EmptyDiffPanel();
    }
    final diff = ref.watch(
      repositoryDiffProvider((
        rootPath: rootPath,
        path: file.path,
        staged: controller.selectedFileStaged,
      )),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CenterPanelHeader(
          title: controller.selectedFileStaged ? 'STAGED DIFF' : 'WORKING DIFF',
          trailing: file.path,
        ),
        if (file.isConflicted)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: context.gitTheme.danger.withValues(alpha: 0.12),
            child: Row(
              children: <Widget>[
                Text(
                  'Conflict: ${file.path}',
                  style: TextStyle(color: context.gitTheme.danger),
                ),
                const Spacer(),
                TextButton(
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.resolveConflict(file, ours: true),
                  child: const Text('Use Ours'),
                ),
                TextButton(
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.resolveConflict(file, ours: false),
                  child: const Text('Use Theirs'),
                ),
                TextButton(
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.markResolved(file),
                  child: const Text('Mark Resolved'),
                ),
              ],
            ),
          ),
        Expanded(
          child: diff.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _PanelError(error: error),
            data: (value) => _UnifiedDiffView(diff: value),
          ),
        ),
      ],
    );
  }
}

class _UnifiedDiffView extends StatelessWidget {
  const _UnifiedDiffView({required this.diff});

  final GitDiff diff;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    if (diff.isBinary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.insert_drive_file_outlined, size: 34),
            const SizedBox(height: 10),
            Text('Binary file: ${diff.path}'),
          ],
        ),
      );
    }
    if (diff.text.isEmpty) {
      return const Center(child: Text('No textual diff for this selection.'));
    }
    final lines = diff.text.split('\n');
    return SelectionArea(
      child: ListView.builder(
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          final isAdded = line.startsWith('+') && !line.startsWith('+++');
          final isDeleted = line.startsWith('-') && !line.startsWith('---');
          final isHunk = line.startsWith('@@');
          final background = isAdded
              ? tokens.success.withValues(alpha: 0.10)
              : isDeleted
              ? tokens.danger.withValues(alpha: 0.10)
              : isHunk
              ? tokens.graphLaneColors.first.withValues(alpha: 0.10)
              : Colors.transparent;
          final foreground = isAdded
              ? tokens.success
              : isDeleted
              ? tokens.danger
              : isHunk
              ? tokens.graphLaneColors.first
              : tokens.textPrimary;
          return ColoredBox(
            color: background,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 48,
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  alignment: Alignment.topRight,
                  color: tokens.backgroundSecondary,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      line.isEmpty ? ' ' : line,
                      style: TextStyle(
                        color: foreground,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CommitEditorPanel extends StatelessWidget {
  const _CommitEditorPanel({
    required this.status,
    required this.summaryController,
    required this.descriptionController,
    required this.amend,
    required this.busy,
    required this.onAmendChanged,
    required this.onCommit,
  });

  final AsyncValue<RepositoryStatus> status;
  final TextEditingController summaryController;
  final TextEditingController descriptionController;
  final bool amend;
  final bool busy;
  final ValueChanged<bool> onAmendChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    final stagedCount = status.value?.stagedCount ?? 0;
    return ColoredBox(
      color: tokens.backgroundSecondary,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'CREATE COMMIT',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '$stagedCount staged',
                  style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: summaryController,
              maxLength: 72,
              decoration: const InputDecoration(
                labelText: 'Summary',
                hintText: 'Describe this change',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: descriptionController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: amend,
              onChanged: busy
                  ? null
                  : (value) => onAmendChanged(value ?? false),
              title: const Text('Amend previous commit'),
            ),
            FilledButton.icon(
              onPressed: busy || stagedCount == 0 ? null : onCommit,
              icon: const Icon(Icons.commit, size: 18),
              label: Text(amend ? 'Amend Commit' : 'Commit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitDetailsPanel extends StatelessWidget {
  const _CommitDetailsPanel({required this.commit, required this.onClose});

  final CommitNode commit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ColoredBox(
      color: tokens.backgroundSecondary,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'COMMIT DETAILS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Close details',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            commit.subject,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (commit.body.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            SelectableText(commit.body),
          ],
          const SizedBox(height: 18),
          _Detail(label: 'SHA', value: commit.hash),
          _Detail(label: 'Author', value: commit.authorName),
          _Detail(label: 'Email', value: commit.authorEmail),
          _Detail(
            label: 'Date',
            value: commit.authorDate?.toLocal().toString() ?? 'Unknown',
          ),
          _Detail(
            label: 'Parents',
            value: commit.parents.isEmpty
                ? 'Root commit'
                : commit.parents.join('\n'),
          ),
          if (commit.decorations.isNotEmpty)
            _Detail(label: 'References', value: commit.decorations.join('\n')),
        ],
      ),
    );
  }
}

class _OperationMessage extends StatelessWidget {
  const _OperationMessage({required this.controller});

  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    final error = controller.error;
    return Container(
      color: error == null
          ? tokens.success.withValues(alpha: 0.12)
          : tokens.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(
            error == null ? Icons.check_circle_outline : Icons.error_outline,
            size: 17,
            color: error == null ? tokens.success : tokens.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error?.message ?? controller.lastSuccess ?? '',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: controller.clearMessage,
            icon: const Icon(Icons.close, size: 15),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _InProgressOperationBanner extends StatelessWidget {
  const _InProgressOperationBanner({
    required this.state,
    required this.status,
    required this.controller,
  });

  final RepositoryOperationState state;
  final AsyncValue<RepositoryStatus> status;
  final RepositoryWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    final conflictCount = status.value?.conflictedCount ?? 0;
    final operationName = switch (state.type) {
      RepositoryOperationType.merge => 'Merge',
      RepositoryOperationType.rebase => 'Rebase',
      RepositoryOperationType.cherryPick => 'Cherry-pick',
      RepositoryOperationType.revert => 'Revert',
      RepositoryOperationType.none => 'Git operation',
    };
    return Container(
      color: tokens.warning.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber, size: 18, color: tokens.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$operationName in progress'
              '${conflictCount == 0 ? '' : ' • $conflictCount conflict(s)'}',
            ),
          ),
          TextButton(
            onPressed: controller.isBusy || conflictCount > 0
                ? null
                : controller.continueOperation,
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: controller.isBusy
                ? null
                : () => _confirmAbortOperation(
                    context,
                    controller,
                    operationName,
                  ),
            child: const Text('Abort'),
          ),
        ],
      ),
    );
  }
}

class _ActivityBar extends StatelessWidget {
  const _ActivityBar({
    required this.controller,
    required this.session,
    required this.git,
  });

  final RepositoryWorkspaceController controller;
  final RepositorySession session;
  final GitInstallation git;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          if (controller.isBusy) ...<Widget>[
            const SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 7),
            Text(controller.operationLabel ?? 'Git operation…'),
          ] else ...<Widget>[
            Icon(Icons.check_circle, size: 14, color: tokens.success),
            const SizedBox(width: 6),
            const Text('Ready'),
          ],
          const Spacer(),
          Text(
            'Git ${git.version}',
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              session.rootPath,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _WipRow extends StatelessWidget {
  const _WipRow({required this.status});

  final RepositoryStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 40,
      color: tokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: tokens.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('WIP  •  Uncommitted working-tree changes'),
          ),
          Text(
            '${status.files.where((file) => !file.isIgnored).length} files',
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _CenterPanelHeader extends StatelessWidget {
  const _CenterPanelHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              trailing,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSectionHeader extends StatelessWidget {
  const _PanelSectionHeader({
    required this.title,
    required this.trailing,
    this.action,
  });

  final String title;
  final String trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 35,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          top: BorderSide(color: tokens.border),
          bottom: BorderSide(color: tokens.border),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            trailing,
            style: TextStyle(color: tokens.textSecondary, fontSize: 10),
          ),
          ?action,
          if (action == null) const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _SimpleRefSection extends StatelessWidget {
  const _SimpleRefSection({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PanelSectionHeader(title: title, trailing: '${items.length}'),
          for (final item in items)
            ListTile(
              dense: true,
              leading: Icon(icon, size: 15),
              title: Text(item, overflow: TextOverflow.ellipsis),
            ),
          if (items.isEmpty) _EmptySection(text: 'No ${title.toLowerCase()}.'),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: TextStyle(color: context.gitTheme.textSecondary, fontSize: 11),
      ),
    );
  }
}

class _EmptyDiffPanel extends StatelessWidget {
  const _EmptyDiffPanel();

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ColoredBox(
      color: tokens.backgroundPrimary,
      child: Center(
        child: Text(
          'Select a changed file to inspect its diff.',
          style: TextStyle(color: tokens.textSecondary),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(color: tokens.textSecondary, fontSize: 10),
          ),
          const SizedBox(height: 3),
          SelectableText(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  const _PanelError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          error.toString(),
          textAlign: TextAlign.center,
          style: TextStyle(color: tokens.danger),
        ),
      ),
    );
  }
}

Future<void> _showCreateBranch(
  BuildContext context,
  RepositoryWorkspaceController controller, {
  String? startPoint,
}) async {
  final nameController = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create Branch'),
      content: TextField(
        controller: nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Branch name'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(nameController.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  nameController.dispose();
  if (name != null && name.isNotEmpty) {
    await controller.createBranch(name, startPoint: startPoint);
  }
}

Future<void> _showCreateTag(
  BuildContext context,
  RepositoryWorkspaceController controller, {
  String? target,
}) async {
  final nameController = TextEditingController();
  final messageController = TextEditingController();
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create Tag'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Tag name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Annotation (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((nameController.text.trim(), messageController.text.trim())),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  nameController.dispose();
  messageController.dispose();
  if (result != null && result.$1.isNotEmpty) {
    await controller.createTag(
      result.$1,
      target: target,
      message: result.$2.isEmpty ? null : result.$2,
    );
  }
}

Future<void> _showCreateStash(
  BuildContext context,
  RepositoryWorkspaceController controller,
) async {
  final messageController = TextEditingController();
  var includeUntracked = false;
  final result = await showDialog<(String, bool)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Create Stash'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: messageController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Message (optional)',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeUntracked,
                onChanged: (value) =>
                    setDialogState(() => includeUntracked = value ?? false),
                title: const Text('Include untracked files'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop((messageController.text.trim(), includeUntracked)),
            child: const Text('Stash'),
          ),
        ],
      ),
    ),
  );
  messageController.dispose();
  if (result != null) {
    await controller.createStash(
      message: result.$1.isEmpty ? null : result.$1,
      includeUntracked: result.$2,
    );
  }
}

Future<void> _handleCommitAction(
  BuildContext context,
  RepositoryWorkspaceController controller,
  CommitNode commit,
  String action,
) async {
  switch (action) {
    case 'branch':
      await _showCreateBranch(context, controller, startPoint: commit.hash);
    case 'tag':
      await _showCreateTag(context, controller, target: commit.hash);
    case 'cherry':
      await controller.cherryPick(commit.hash);
    case 'revert':
      final confirmed = await _confirm(
        context,
        title: 'Revert commit?',
        message: 'Create a new commit that reverses ${commit.shortHash}?',
        actionLabel: 'Revert',
      );
      if (confirmed) await controller.revertCommit(commit.hash);
    case 'reset':
      await _showResetDialog(context, controller, commit);
  }
}

Future<void> _showResetDialog(
  BuildContext context,
  RepositoryWorkspaceController controller,
  CommitNode commit,
) async {
  final mode = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Reset to ${commit.shortHash}'),
      content: const Text(
        'SOFT moves HEAD only. MIXED also resets the index. '
        'HARD replaces both the index and working tree.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('soft'),
          child: const Text('Soft'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop('mixed'),
          child: const Text('Mixed'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('hard'),
          child: const Text('Hard…'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (mode == null) return;
  if (mode == 'hard') {
    final confirmed = await _confirm(
      context,
      title: 'Confirm hard reset',
      message: 'Hard reset will replace the index and working tree. Continue?',
      actionLabel: 'Hard Reset',
    );
    if (!confirmed) return;
  }
  await controller.resetTo(commit.hash, mode: mode);
}

Future<void> _confirmDropStash(
  BuildContext context,
  RepositoryWorkspaceController controller,
  String selector,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Drop stash?',
    message: 'Permanently drop $selector?',
    actionLabel: 'Drop',
  );
  if (confirmed) await controller.dropStash(selector);
}

Future<void> _confirmAbortOperation(
  BuildContext context,
  RepositoryWorkspaceController controller,
  String operation,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Abort $operation?',
    message: 'Return the repository to its state before this operation?',
    actionLabel: 'Abort',
  );
  if (confirmed) await controller.abortOperation();
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _confirmDiscard(
  BuildContext context,
  RepositoryWorkspaceController controller,
  GitFileStatus file,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard changes?'),
      content: Text(
        'Discard changes in ${file.path}? A recovery snapshot will be created first.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await controller.discard(file);
}

Future<void> _confirmDeleteBranch(
  BuildContext context,
  RepositoryWorkspaceController controller,
  String branch,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete branch?'),
      content: Text('Delete local branch "$branch" using the safe -d mode?'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) await controller.deleteBranch(branch);
}
