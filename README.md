# Git Desktop (`git_desktop_client`)

A modern, high-performance, native Flutter desktop client for **macOS** and **Windows**, powered directly by your system's installed Git binary.

> 🔒 **Security & Reliability Guarantee**: System Git is the single source of truth. Operations are executed strictly via explicit process argument vectors without shell invocation (`runInShell: false`), preventing shell injection vulnerabilities and ensuring 100% standard Git behavior.

---

## 🌟 Key Architectural Principles

- **Zero-Dependency Native Execution**: No wrapper shells, no unsafe commands, and no embedded non-standard Git implementations.
- **Robust Process Runner (`GitProcessRunner`)**: Safe command execution engine featuring timeout protection, environment isolation (`GIT_PAGER=cat`, `GIT_EDITOR=false`, `LC_ALL=C`), and typed exception handling (`GitError`, `GitErrorKind`).
- **Porcelain V2 Machine Parser (`GitStatusParser`)**: High-efficiency NUL-delimited (`-z`) `git status --porcelain=v2 --branch` parser capable of handling file renames, copy tracking, conflict states (`u` records), staged vs. unstaged statuses, and branch metrics (`ahead`/`behind` relative to upstream).
- **Feature-First Architecture**: Standardized project layout using Flutter Riverpod (`flutter_riverpod` 3.x) for scalable, decoupled state management.
- **Multi-Tab Workspace**: Open and manage multiple Git repositories side-by-side in separate isolated sessions.
- **Modern Dark Theme**: Custom dark theme design tokens (`GitThemeTokens`) tailored for high-density desktop interfaces with adaptive responsive layouts.

---

## 🏗 Project Architecture & Directory Layout

The codebase follows a modular **feature-first** design pattern:

```text
git_desktop_client/
├── lib/
│   ├── main.dart                             # Application entry point
│   ├── app/                                  # Core app configuration & design tokens
│   │   ├── app.dart                          # Root MaterialApp & Riverpod provider setup
│   │   └── theme/
│   │       └── app_theme.dart                # GitThemeTokens & Dark Theme extension
│   ├── core/                                 # Low-level system & core services
│   │   ├── git/                              # System Git engine & integration layer
│   │   │   ├── git_executable_locator.dart   # Auto-detect system `git` path & version
│   │   │   ├── git_process_runner.dart        # Safe async process runner with timeout
│   │   │   ├── git_status_parser.dart        # Porcelain v2 NUL string parser
│   │   │   ├── git_status.dart               # Data models for repo/file status & branch
│   │   │   ├── git_command.dart              # Git command payload abstraction
│   │   │   └── git_error.dart                # Strongly-typed error definitions
│   │   ├── ai/                               # AI Assistant core infrastructure
│   │   ├── security/                         # Security & credential managers
│   │   ├── storage/                          # Local storage & persistence
│   │   └── terminal/                         # Terminal & PTY backend core
│   └── features/                             # Modular feature sub-domains
│       ├── repositories/                     # Repository tabs, picker, workspace layout
│       ├── working_tree/                     # Working tree file status list & detail view
│       ├── staging/                          # File/hunk staging implementation
│       ├── commits/                          # Commit history & commit composition
│       ├── branches/                         # Local/remote branch manager
│       ├── graph/                            # Visual commit history graph
│       ├── terminal/                         # Embedded PTY terminal interface
│       └── ...                               # Additional modular domains (24 domains total)
└── test/                                     # Automated test suite
    ├── core/git/git_status_parser_test.dart  # Unit tests for Git status parser
    ├── features/repositories/git_repository_service_test.dart # Integration test for Git service
    └── widget_test.dart                      # UI component tests
```

---

## ⚡ Current Status: Phase 0 Completed

### Implemented Capabilities:
- ✅ Native **macOS** & **Windows** desktop target support.
- ✅ Dynamic **System Git Detection**: Locates installed `git` executable and verifies compatibility/version.
- ✅ **Safe Process Execution**: Timeout-aware command runner with typed errors (`GitError`) and sanitized environment variables.
- ✅ **Porcelain v2 NUL Parser**: Robust parsing of working-tree status, file modifications, staged files, untracked/ignored items, renames, copies, and conflicts.
- ✅ **Multi-Repository Workspace**: Open, switch between, and close multiple repository tabs independently.
- ✅ **Responsive Desktop UI**: Adaptive multi-column layout (Working Tree, History Graph Foundation, Repository Details, Terminal Foundation).
- ✅ **Dark Theme Integration**: Visual design tokens customized for developer desktop tools.

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.11.5` or later)
- [Git](https://git-scm.com/) installed on system PATH (or custom binary location)
- **macOS**: Xcode Command Line Tools (`xcode-select --install`)
- **Windows**: Visual Studio 2022 with Desktop development with C++ workload

### Building and Running

1. **Clone the repository**:
   ```bash
   git clone https://github.com/vqh2602/git-durn.git
   cd git-durn
   ```

2. **Fetch Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run on macOS**:
   ```bash
   flutter run -d macos
   ```

4. **Run on Windows**:
   ```bash
   flutter run -d windows
   ```

---

## 🧪 Testing & Code Quality

Run automated test suite and linter before submitting PRs:

```bash
# Run unit & widget tests
flutter test

# Run static code analysis
flutter analyze

# Verify debug build on macOS
flutter build macos --debug

# Verify debug build on Windows
flutter build windows --debug
```

---

## 🗺 Feature Roadmap

| Phase | Module | Description | Status |
| :--- | :--- | :--- | :---: |
| **Phase 0** | **Core Foundation** | System Git process runner, Porcelain v2 parsing, Multi-tab UI layout | ✅ Completed |
| **Phase 1** | **Staging & Discard** | File & line-level hunk staging, discard uncommitted changes | 🚧 Planned |
| **Phase 2** | **Commit Engine** | Commit composer, GPG/SSH commit signing, smart message generator | 🚧 Planned |
| **Phase 3** | **Commit Graph** | Interactive visual commit graph with topological branch rendering | 🚧 Planned |
| **Phase 4** | **Branches & Remotes**| Branch switching/creation, Push, Fetch, Pull, Rebase, Merge & Conflict Editor | 🚧 Planned |
| **Phase 5** | **Advanced Git** | Stash management, Submodules, Worktree isolated workspaces, Git LFS | 🚧 Planned |
| **Phase 6** | **Integrations** | GitHub / GitLab / Bitbucket API integration (PRs, Issues, Code Review) | 🚧 Planned |
| **Phase 7** | **Terminal & AI** | Built-in PTY terminal emulator & AI-assisted git workflow helper | 🚧 Planned |

---

## 📄 License

This project is open-source. See the repository configuration for details.

