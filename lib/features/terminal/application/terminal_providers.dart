import 'package:flutter_riverpod/legacy.dart';

import 'terminal_manager.dart';

final terminalManagerProvider = ChangeNotifierProvider.autoDispose
    .family<TerminalManager, String>(
      (ref, repositoryRoot) => TerminalManager(repositoryRoot: repositoryRoot),
    );
