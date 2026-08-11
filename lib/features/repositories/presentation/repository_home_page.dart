import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/git/git_executable_locator.dart';
import '../application/repository_providers.dart';
import '../application/repository_tabs_controller.dart';
import '../domain/repository_session.dart';
import 'widgets/repository_workspace.dart';

class RepositoryHomePage extends ConsumerWidget {
  const RepositoryHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installation = ref.watch(gitInstallationProvider);
    return installation.when(
      loading: () => const _StartupScreen(),
      error: (error, stackTrace) => _GitUnavailableScreen(
        details: error.toString(),
        onRetry: () => ref.invalidate(gitInstallationProvider),
      ),
      data: (git) {
        if (git == null) {
          return _GitUnavailableScreen(
            onRetry: () => ref.invalidate(gitInstallationProvider),
          );
        }
        return _RepositoryShell(git: git);
      },
    );
  }
}

class _RepositoryShell extends ConsumerWidget {
  const _RepositoryShell({required this.git});

  final GitInstallation git;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(repositoryTabsProvider);
    final controller = ref.read(repositoryTabsProvider.notifier);
    final tokens = context.gitTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TabBar(
              state: tabs,
              onOpen: controller.openRepository,
              onSelect: controller.select,
              onClose: controller.close,
            ),
            if (tabs.error case final error?)
              MaterialBanner(
                backgroundColor: tokens.danger.withValues(alpha: 0.14),
                leading: Icon(Icons.error_outline, color: tokens.danger),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(error.message),
                    if (error.technicalDetails case final details?)
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: controller.clearError,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            Expanded(
              child: switch (tabs.selected) {
                final selected? => RepositoryWorkspace(
                  session: selected,
                  git: git,
                ),
                null => _WelcomeView(
                  isOpening: tabs.isOpening,
                  onOpen: controller.openRepository,
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.state,
    required this.onOpen,
    required this.onSelect,
    required this.onClose,
  });

  final RepositoryTabsState state;
  final VoidCallback onOpen;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          Icon(
            Icons.account_tree_outlined,
            size: 18,
            color: tokens.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            'Git Desktop',
            style: TextStyle(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final session in state.sessions)
                  _RepositoryTab(
                    session: session,
                    selected: session.id == state.selectedId,
                    onSelect: () => onSelect(session.id),
                    onClose: () => onClose(session.id),
                  ),
              ],
            ),
          ),
          if (state.isOpening)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Open repository',
            onPressed: state.isOpening ? null : onOpen,
            icon: const Icon(Icons.add, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _RepositoryTab extends StatelessWidget {
  const _RepositoryTab({
    required this.session,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final RepositorySession session;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return InkWell(
      onTap: onSelect,
      child: Container(
        constraints: const BoxConstraints(minWidth: 130, maxWidth: 220),
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: selected ? tokens.surface : Colors.transparent,
          border: Border(
            left: BorderSide(color: tokens.border),
            right: BorderSide(color: tokens.border),
            bottom: BorderSide(
              color: selected
                  ? tokens.graphLaneColors.first
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.folder_outlined, size: 15, color: tokens.textSecondary),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                session.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.textPrimary),
              ),
            ),
            IconButton(
              tooltip: 'Close ${session.name}',
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 14),
              splashRadius: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.isOpening, required this.onOpen});

  final bool isOpening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.account_tree,
                size: 56,
                color: tokens.graphLaneColors.first,
              ),
              const SizedBox(height: 20),
              Text(
                'Open a Git repository',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'Git data stays on disk and every status request is read from the system Git executable.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: isOpening ? null : onOpen,
                icon: const Icon(Icons.folder_open),
                label: Text(isOpening ? 'Opening…' : 'Open Repository'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Detecting system Git…'),
          ],
        ),
      ),
    );
  }
}

class _GitUnavailableScreen extends StatelessWidget {
  const _GitUnavailableScreen({required this.onRetry, this.details});

  final VoidCallback onRetry;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.terminal, size: 52),
                const SizedBox(height: 18),
                Text(
                  'Git was not found',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Install Git or configure a custom executable before opening a repository.',
                  textAlign: TextAlign.center,
                ),
                if (details != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(details!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Detect Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
