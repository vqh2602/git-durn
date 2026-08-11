import 'package:flutter/material.dart';

import '../features/repositories/presentation/repository_home_page.dart';
import 'theme/app_theme.dart';

class GitDesktopApp extends StatelessWidget {
  const GitDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Git Desktop',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark(),
      home: const RepositoryHomePage(),
    );
  }
}
