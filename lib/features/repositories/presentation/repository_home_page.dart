import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../../../core/git/git_executable_locator.dart';
import '../../../core/storage/database.dart';
import '../application/repository_providers.dart';
import '../application/repository_tabs_controller.dart';
import '../domain/repository_session.dart';
import '../../settings/presentation/ai_settings_dialog.dart';
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
              onSettings: () => showDialog<void>(
                context: context,
                builder: (context) => const AiSettingsDialog(),
              ),
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
                  onInitialize: controller.initializeRepository,
                  onOpenRecent: controller.openPath,
                  onRemoveRecent: controller.removeRecent,
                  onSetFavorite: controller.setFavorite,
                  onClone: (request) => controller.cloneRepository(
                    url: request.url,
                    destination: request.destination,
                    depth: request.depth,
                    singleBranch: request.singleBranch,
                    recurseSubmodules: request.recurseSubmodules,
                  ),
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
    required this.onSettings,
  });

  final RepositoryTabsState state;
  final VoidCallback onOpen;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onSettings;

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
          IconButton(
            tooltip: 'Settings · Local AI',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined, size: 19),
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

class _WelcomeView extends ConsumerWidget {
  const _WelcomeView({
    required this.isOpening,
    required this.onOpen,
    required this.onInitialize,
    required this.onClone,
    required this.onOpenRecent,
    required this.onRemoveRecent,
    required this.onSetFavorite,
  });

  final bool isOpening;
  final VoidCallback onOpen;
  final VoidCallback onInitialize;
  final ValueChanged<_CloneRequest> onClone;
  final ValueChanged<String> onOpenRecent;
  final ValueChanged<String> onRemoveRecent;
  final void Function(String path, {required bool isFavorite}) onSetFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.gitTheme;
    final recent = ref.watch(recentRepositoriesProvider);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.account_tree,
                  size: 48,
                  color: tokens.graphLaneColors.first,
                ),
                const SizedBox(height: 18),
                Text(
                  'Git Desktop',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Open, clone, or initialize a real repository using system Git.',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                const SizedBox(height: 26),
                _WelcomeAction(
                  icon: Icons.folder_open,
                  title: 'Open Repository',
                  subtitle: 'Open an existing local working tree',
                  onPressed: isOpening ? null : onOpen,
                ),
                _WelcomeAction(
                  icon: Icons.cloud_download_outlined,
                  title: 'Clone Repository',
                  subtitle: 'Clone from an SSH or HTTPS URL',
                  onPressed: isOpening
                      ? null
                      : () async {
                          final request = await showDialog<_CloneRequest>(
                            context: context,
                            builder: (context) =>
                                const _CloneRepositoryDialog(),
                          );
                          if (request != null) onClone(request);
                        },
                ),
                _WelcomeAction(
                  icon: Icons.create_new_folder_outlined,
                  title: 'Initialize Repository',
                  subtitle: 'Run git init in a selected folder',
                  onPressed: isOpening ? null : onInitialize,
                ),
                if (isOpening) ...<Widget>[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'Git operation in progress…',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 44),
          VerticalDivider(width: 1, color: tokens.border),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Recent repositories',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: recent.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: Text('Could not load recent repositories: $error'),
                    ),
                    data: (items) => items.isEmpty
                        ? Center(
                            child: Text(
                              'Repositories you open will appear here.',
                              style: TextStyle(color: tokens.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: tokens.border),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _RecentRepositoryTile(
                                repository: item,
                                onOpen: () => onOpenRecent(item.path),
                                onRemove: () => onRemoveRecent(item.path),
                                onFavorite: () => onSetFavorite(
                                  item.path,
                                  isFavorite: !item.isFavorite,
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeAction extends StatelessWidget {
  const _WelcomeAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(14),
          side: BorderSide(color: tokens.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: tokens.graphLaneColors.first),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _RecentRepositoryTile extends StatelessWidget {
  const _RecentRepositoryTile({
    required this.repository,
    required this.onOpen,
    required this.onRemove,
    required this.onFavorite,
  });

  final RecentRepository repository;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return ListTile(
      onTap: onOpen,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      leading: Icon(Icons.folder_outlined, color: tokens.graphLaneColors.first),
      title: Text(repository.name),
      subtitle: Text(
        repository.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: repository.isFavorite ? 'Remove favorite' : 'Add favorite',
            onPressed: onFavorite,
            icon: Icon(
              repository.isFavorite ? Icons.star : Icons.star_border,
              color: repository.isFavorite
                  ? tokens.warning
                  : tokens.textSecondary,
            ),
          ),
          IconButton(
            tooltip: 'Remove from recent repositories',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _CloneRequest {
  const _CloneRequest({
    required this.url,
    required this.destination,
    required this.depth,
    required this.singleBranch,
    required this.recurseSubmodules,
  });

  final String url;
  final String destination;
  final int? depth;
  final bool singleBranch;
  final bool recurseSubmodules;
}

class _CloneRepositoryDialog extends StatefulWidget {
  const _CloneRepositoryDialog();

  @override
  State<_CloneRepositoryDialog> createState() => _CloneRepositoryDialogState();
}

class _CloneRepositoryDialogState extends State<_CloneRepositoryDialog> {
  final _urlController = TextEditingController();
  final _destinationController = TextEditingController();
  String _depth = 'Full';
  bool _singleBranch = false;
  bool _recurseSubmodules = false;

  @override
  void dispose() {
    _urlController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clone Repository'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _urlController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Repository URL',
                hintText: 'git@github.com:owner/repository.git',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _destinationController,
              decoration: InputDecoration(
                labelText: 'Destination folder',
                suffixIcon: IconButton(
                  tooltip: 'Choose parent folder',
                  onPressed: _chooseDestination,
                  icon: const Icon(Icons.folder_open),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _depth,
              decoration: const InputDecoration(labelText: 'Clone depth'),
              items: const <String>['Full', '1', '10', '50', '100']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _depth = value ?? 'Full'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _singleBranch,
              onChanged: (value) =>
                  setState(() => _singleBranch = value ?? false),
              title: const Text('Single branch'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _recurseSubmodules,
              onChanged: (value) =>
                  setState(() => _recurseSubmodules = value ?? false),
              title: const Text('Recurse submodules'),
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
          onPressed:
              _urlController.text.trim().isEmpty ||
                  _destinationController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _CloneRequest(
                    url: _urlController.text.trim(),
                    destination: _destinationController.text.trim(),
                    depth: _depth == 'Full' ? null : int.parse(_depth),
                    singleBranch: _singleBranch,
                    recurseSubmodules: _recurseSubmodules,
                  ),
                ),
          child: const Text('Clone'),
        ),
      ],
    );
  }

  Future<void> _chooseDestination() async {
    final parent = await getDirectoryPath(confirmButtonText: 'Select');
    if (parent == null) return;
    final rawUrl = _urlController.text.trim().replaceAll('\\', '/');
    final lastSegment = rawUrl.split('/').last.split(':').last;
    final repositoryName = lastSegment.endsWith('.git')
        ? lastSegment.substring(0, lastSegment.length - 4)
        : lastSegment;
    _destinationController.text = repositoryName.isEmpty
        ? parent
        : p.join(parent, repositoryName);
    setState(() {});
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

class _GitUnavailableScreen extends ConsumerWidget {
  const _GitUnavailableScreen({required this.onRetry, this.details});

  final VoidCallback onRetry;
  final String? details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customPath = ref.watch(customGitExecutableProvider);

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
                  'Install Git or configure a custom executable path before opening a repository.',
                  textAlign: TextAlign.center,
                ),
                if (customPath != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Configured executable: $customPath',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (details != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(details!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Detect Again'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final file = await openFile(
                          confirmButtonText: 'Select Git Executable',
                        );
                        if (file != null) {
                          ref
                              .read(customGitExecutableProvider.notifier)
                              .setPath(file.path);
                          ref.invalidate(gitInstallationProvider);
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Choose Git Executable'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
