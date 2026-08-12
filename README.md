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

## ⚡ Current Status: Functional Desktop Git Client

### Implemented Capabilities

- ✅ Open, initialize, and clone repositories (depth, single-branch, and submodule options).
- ✅ Recent and favorite repositories persisted in SQLite, with multi-repository tabs.
- ✅ System Git auto-detection plus a user-selected custom executable fallback.
- ✅ Safe argument-vector process execution (`runInShell: false`), timeouts, typed errors, and a per-repository mutation queue.
- ✅ Porcelain v2 status parsing, ahead/behind state, file watching, and automatic refresh.
- ✅ Stage/unstage files or all changes, discard with a recovery snapshot, and conflict resolution using ours/theirs/mark-resolved.
- ✅ Real unified diffs with line numbers, staged/unstaged views, untracked-file previews, and binary-file handling.
- ✅ Commit and amend, commit history/details, decorations, and common commit actions.
- ✅ Create/switch/delete/merge branches; create tags; fetch, pull, rebase, push, set upstream, push tags, and force-with-lease.
- ✅ Create/apply/pop/drop stashes; cherry-pick, revert, and soft/mixed/hard reset.
- ✅ Detect in-progress merge/rebase/cherry-pick/revert operations and continue or abort them.
- ✅ Embedded multi-session terminal backed by a real PTY and the user's shell.
- ✅ Stage/unstage complete hunks or selected changed lines using generated patches passed to `git apply` over stdin.
- ✅ Three-way conflict workspace with BASE/OURS/THEIRS panes, an editable RESULT, and per-block Ours/Theirs/Both/Neither actions.
- ✅ Worktree management, recursive submodule update/sync, Git LFS tracking/actions, reflog recovery, file history, blame, and patch preview/apply.
- ✅ GitHub/GitLab/Bitbucket hosting-provider abstraction; authenticated CLI JSON powers live pull-request and issue lists without storing hosting tokens.
- ✅ Local AI model catalog and Settings UI, resumable HTTP Range downloads, `.part` persistence, exact-size and SHA-256 verification, and llama.cpp inference.
- ✅ AI commit suggestions stream into a preview and require explicit Apply and Commit actions; staged context is bounded, noisy files are reported, and secrets are redacted.
- ✅ Native macOS lifecycle behavior: standalone release launch, close/reopen, and app activation.

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

## 🗺 Feature Coverage

| Phase | Module | Description | Status |
| :--- | :--- | :--- | :---: |
| **Core Foundation** | System Git process runner, Porcelain v2 parsing, SQLite metadata, multi-tab UI | ✅ Completed |
| **Working Tree** | File staging, unstaging, discard/recovery, diffs, basic conflict resolution | ✅ Completed |
| **Commit & History** | Commit/amend, history, details, decorations, commit actions | ✅ Completed |
| **Branches & Remotes** | Branch/tag management, fetch/pull/push/merge/rebase | ✅ Completed |
| **Stash & Recovery** | Stash lifecycle, operation continue/abort, safe confirmations | ✅ Completed |
| **Terminal** | Real PTY, multiple sessions, resize and shell I/O | ✅ Completed |
| **Advanced Editing** | Hunk/line staging and a three-way block conflict editor | ✅ Completed |
| **Advanced Repository Tools** | Worktrees, submodules UI, LFS, reflog, blame, patch workflows | ✅ Completed |
| **Hosting** | GitHub/GitLab/Bitbucket provider abstraction with authenticated CLI PR/issues | ✅ Completed |
| **Local AI** | Downloadable Qwen3 GGUF catalog, resumable downloads, llama.cpp generation, commit preview/apply | ✅ Completed |

---

## 📄 License

This project is open-source. See the repository configuration for details.
