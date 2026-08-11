import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/app/app.dart';
import 'package:git_desktop_client/core/git/git_executable_locator.dart';
import 'package:git_desktop_client/features/repositories/application/repository_providers.dart';

void main() {
  testWidgets('shows the repository empty state when Git is available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitInstallationProvider.overrideWith(
            (ref) async => const GitInstallation(
              executablePath: '/usr/bin/git',
              version: '2.40.0',
            ),
          ),
        ],
        child: const GitDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Git Desktop'), findsOneWidget);
    expect(find.text('Open a Git repository'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Open Repository'),
      findsOneWidget,
    );
  });
}
