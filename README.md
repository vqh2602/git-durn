# Git Desktop

A native Flutter desktop Git client for macOS and Windows. System Git is the
source of truth; the application invokes the executable with argument lists and
never routes repository operations through a shell command string.

## Phase 0

Implemented foundation:

- macOS and Windows Flutter runners
- feature-first project structure and Riverpod state
- system Git discovery and version display
- safe, timeout-aware Git process runner with typed errors
- real repository validation through `git rev-parse`
- NUL-delimited `git status --porcelain=v2 -z --branch` parsing
- independent repository tabs and status providers
- working-tree, repository-detail, graph-foundation, and terminal-foundation panels
- dark design tokens with responsive desktop layout

The commit graph and PTY terminal panels state their planned phases and do not
simulate data or actions.

## Run and verify

```sh
flutter run -d macos
flutter analyze
flutter test
flutter build macos --debug
```

Windows runner sources are generated and checked into the project. Build them
on a Windows host with `flutter build windows`.
