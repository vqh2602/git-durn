import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/git/git_executable_locator.dart';
import '../../../../core/git/git_status.dart';
import '../../application/repository_providers.dart';
import '../../domain/repository_session.dart';

class RepositoryWorkspace extends ConsumerWidget {
  const RepositoryWorkspace({
    required this.session,
    required this.git,
    super.key,
  });

  final RepositorySession session;
  final GitInstallation git;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(repositoryStatusProvider(session.rootPath));
    final tokens = context.gitTheme;

    return Column(
      children: <Widget>[
        _Toolbar(
          session: session,
          status: status,
          onRefresh: () =>
              ref.invalidate(repositoryStatusProvider(session.rootPath)),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showRightPanel = constraints.maxWidth >= 960;
              final leftWidth = constraints.maxWidth >= 1120 ? 240.0 : 200.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: leftWidth,
                    child: _WorkingTreePanel(status: status),
                  ),
                  VerticalDivider(width: 1, color: tokens.border),
                  Expanded(child: _GraphFoundation(status: status)),
                  if (showRightPanel) ...<Widget>[
                    VerticalDivider(width: 1, color: tokens.border),
                    SizedBox(
                      width: 280,
                      child: _RepositoryDetails(
                        session: session,
                        git: git,
                        status: status,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const _TerminalFoundation(),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.session,
    required this.status,
    required this.onRefresh,
  });

  final RepositorySession session;
  final AsyncValue<RepositoryStatus> status;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.source_outlined, size: 18, color: tokens.textSecondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              status.value?.branch.displayName ?? session.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
          if (status.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Refresh repository status',
            onPressed: status.isLoading ? null : onRefresh,
            icon: const Icon(Icons.refresh, size: 19),
          ),
        ],
      ),
    );
  }
}

class _WorkingTreePanel extends StatelessWidget {
  const _WorkingTreePanel({required this.status});

  final AsyncValue<RepositoryStatus> status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ColoredBox(
      color: tokens.backgroundSecondary,
      child: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _PanelError(error: error),
        data: (value) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SectionHeader(
              title: 'WORKING TREE',
              count: value.files.where((file) => !file.isIgnored).length,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.call_split,
                    size: 15,
                    color: tokens.graphLaneColors.first,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      value.branch.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.border),
            Expanded(
              child: value.files.isEmpty
                  ? _CleanState(color: tokens.success)
                  : ListView.builder(
                      itemCount: value.files.length,
                      itemBuilder: (context, index) =>
                          _FileRow(file: value.files[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final GitFileStatus file;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    final (label, color) = switch (file.kind) {
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
    return Semantics(
      label: '${file.kind.name} ${file.path}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 18,
              child: Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Tooltip(
                message: file.originalPath == null
                    ? file.path
                    : '${file.originalPath} → ${file.path}',
                child: Text(file.path, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (file.isStaged)
              Tooltip(
                message: 'Staged',
                child: Icon(
                  Icons.check_circle,
                  size: 13,
                  color: tokens.success,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GraphFoundation extends StatelessWidget {
  const _GraphFoundation({required this.status});

  final AsyncValue<RepositoryStatus> status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ColoredBox(
      color: tokens.backgroundPrimary,
      child: status.when(
        loading: () => const SizedBox.shrink(),
        error: (error, stackTrace) => _PanelError(error: error),
        data: (value) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: <Widget>[
            if (!value.isClean)
              _WipRow(status: value)
            else
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline,
                      color: tokens.success,
                      size: 34,
                    ),
                    const SizedBox(height: 12),
                    const Text('Working tree is clean'),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Commit history arrives in Phase 3. This panel currently shows only live working-tree state from Git.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
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
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: tokens.warning,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.backgroundPrimary, width: 2),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('WIP', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Uncommitted working-tree changes'),
              ],
            ),
          ),
          Text(
            '${status.files.where((file) => !file.isIgnored).length} files',
            style: TextStyle(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RepositoryDetails extends StatelessWidget {
  const _RepositoryDetails({
    required this.session,
    required this.git,
    required this.status,
  });

  final RepositorySession session;
  final GitInstallation git;
  final AsyncValue<RepositoryStatus> status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ColoredBox(
      color: tokens.backgroundSecondary,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          const Text(
            'REPOSITORY',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _Detail(label: 'Name', value: session.name),
          _Detail(label: 'Path', value: session.rootPath),
          _Detail(label: 'Git directory', value: session.gitDirectory),
          const SizedBox(height: 14),
          const Text(
            'SYSTEM GIT',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          _Detail(label: 'Version', value: git.version),
          _Detail(label: 'Executable', value: git.executablePath),
          if (status.value case final value?) ...<Widget>[
            const SizedBox(height: 14),
            const Text(
              'STATUS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            _Detail(label: 'Staged', value: '${value.stagedCount}'),
            _Detail(label: 'Untracked', value: '${value.untrackedCount}'),
            _Detail(label: 'Conflicted', value: '${value.conflictedCount}'),
            if (value.branch.upstream case final upstream?)
              _Detail(
                label: 'Upstream',
                value:
                    '$upstream  ↑${value.branch.ahead} ↓${value.branch.behind}',
              ),
          ],
        ],
      ),
    );
  }
}

class _TerminalFoundation extends StatelessWidget {
  const _TerminalFoundation();

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 78,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.terminal, size: 16),
              SizedBox(width: 7),
              Text(
                'TERMINAL',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'PTY terminal backend is scheduled for Phase 7.',
            style: TextStyle(color: tokens.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _CleanState extends StatelessWidget {
  const _CleanState({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.check, color: color),
          const SizedBox(height: 7),
          const Text('No changes'),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, color: tokens.danger),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
