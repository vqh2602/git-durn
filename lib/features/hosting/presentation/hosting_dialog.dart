import 'package:flutter/material.dart';

import '../../../core/hosting/cli_hosting_providers.dart';
import '../../../core/hosting/git_hosting_provider.dart';
import '../../../core/hosting/hosting_models.dart';

class HostingDialog extends StatefulWidget {
  const HostingDialog({required this.rootPath, super.key});
  final String rootPath;
  @override
  State<HostingDialog> createState() => _HostingDialogState();
}

class _HostingDialogState extends State<HostingDialog> {
  GitHostingProvider? provider;
  List<GitHostingProvider> availableProviders = const <GitHostingProvider>[];
  List<HostingPullRequest> pullRequests = const <HostingPullRequest>[];
  List<HostingIssue> issues = const <HostingIssue>[];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final available = <GitHostingProvider>[];
      for (final candidate in hostingProviders) {
        if (await candidate.isAvailable()) available.add(candidate);
      }
      if (available.isEmpty) {
        throw StateError(
          'No authenticated hosting CLI found. Install/login with gh, glab, or bb.',
        );
      }
      availableProviders = available;
      provider ??= available.first;
      if (!available.contains(provider)) provider = available.first;
      final values = await Future.wait<Object>([
        provider!.listPullRequests(widget.rootPath),
        provider!.listIssues(widget.rootPath),
      ]);
      pullRequests = values[0] as List<HostingPullRequest>;
      issues = values[1] as List<HostingIssue>;
    } on Object catch (caught) {
      error = caught.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: <Widget>[
              const Text('Pull Requests & Issues'),
              if (availableProviders.isNotEmpty) ...<Widget>[
                const SizedBox(width: 16),
                DropdownButton<GitHostingProvider>(
                  value: provider,
                  items: <DropdownMenuItem<GitHostingProvider>>[
                    for (final item in availableProviders)
                      DropdownMenuItem(
                        value: item,
                        child: Text(item.displayName),
                      ),
                  ],
                  onChanged: loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          provider = value;
                          _load();
                        },
                ),
              ],
            ],
          ),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Pull Requests'),
              Tab(text: 'Issues'),
            ],
          ),
          actions: <Widget>[
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error!, textAlign: TextAlign.center),
                ),
              )
            : TabBarView(
                children: <Widget>[
                  ListView(
                    children: <Widget>[
                      for (final item in pullRequests)
                        ListTile(
                          leading: CircleAvatar(child: Text(item.id)),
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.author} · ${item.branch} · ${item.isDraft ? 'Draft' : item.state}',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () => _checkout(item.id),
                            child: const Text('Checkout'),
                          ),
                        ),
                      if (pullRequests.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('No open pull requests.'),
                          ),
                        ),
                    ],
                  ),
                  ListView(
                    children: <Widget>[
                      for (final item in issues)
                        ListTile(
                          leading: CircleAvatar(child: Text(item.id)),
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.author}${item.labels.isEmpty ? '' : ' · ${item.labels.join(', ')}'}',
                          ),
                        ),
                      if (issues.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('No open issues.'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    ),
  );

  Future<void> _checkout(String id) async {
    setState(() => loading = true);
    try {
      await provider!.checkoutPullRequest(widget.rootPath, id);
    } on Object catch (caught) {
      error = caught.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}
