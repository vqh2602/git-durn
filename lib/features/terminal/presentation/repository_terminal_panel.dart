import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/app_theme.dart';
import '../application/terminal_manager.dart';
import '../application/terminal_providers.dart';

class RepositoryTerminalPanel extends ConsumerWidget {
  const RepositoryTerminalPanel({required this.repositoryRoot, super.key});

  final String repositoryRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(terminalManagerProvider(repositoryRoot));
    final tokens = context.gitTheme;
    final selected = manager.selected;
    return Container(
      height: 210,
      decoration: BoxDecoration(
        color: tokens.backgroundPrimary,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 34,
            color: tokens.backgroundSecondary,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 8),
                const Icon(Icons.terminal, size: 15),
                const SizedBox(width: 7),
                for (final session in manager.sessions)
                  _TerminalTab(
                    session: session,
                    selected: session.id == selected?.id,
                    onSelect: () => manager.select(session.id),
                    onClose: () => manager.close(session.id),
                  ),
                IconButton(
                  tooltip: 'New terminal',
                  onPressed: manager.createSession,
                  icon: const Icon(Icons.add, size: 16),
                ),
                const Spacer(),
                Text(
                  repositoryRoot,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 10),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      manager.error ?? 'No terminal session.',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  )
                : TerminalView(
                    selected.terminal,
                    autofocus: true,
                    padding: const EdgeInsets.all(7),
                    textStyle: const TerminalStyle(fontSize: 12),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TerminalTab extends StatelessWidget {
  const _TerminalTab({
    required this.session,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final TerminalSession session;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gitTheme;
    return InkWell(
      onTap: onSelect,
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 9),
        color: selected ? tokens.surface : Colors.transparent,
        child: Row(
          children: <Widget>[
            Text(session.title, style: const TextStyle(fontSize: 11)),
            IconButton(
              tooltip: 'Close terminal',
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 13),
            ),
          ],
        ),
      ),
    );
  }
}
