# Contributing to SPPStudio

Thanks for your interest. SPPStudio is in early development and contributions are welcome, but the codebase has specific architectural constraints that are easy to violate accidentally. Read this before opening a PR.

---

## Before you start

1. Read `docs/architecture.md` — especially the NSTextView pool invariants
2. Read `PROJECT_CONTEXT.md` — coding standards and repo layout
3. Check `ROADMAP.md` — if the thing you want to build is already planned, open an issue first to coordinate

If you are unsure whether a change is in scope, open an issue before writing code. A brief description of what you intend to change is enough.

---

## Hard invariants — do not violate these

These are architectural rules that exist for concrete, tested reasons. Violating them breaks per-tab undo history, caret position, or scroll state, usually in ways that are not immediately obvious.

**NSTextView pool — never recreate editors**
`EditorAreaView` keeps one `NSScrollView`/`NSTextView` per open tab alive in a `ZStack`. Do not use `.id(tabID)` to force SwiftUI recreation. Do not create a new `NSTextView` for each tab switch. Use `isActive`/`isHidden` to switch visibility.

**Diagnostics ownership — by file identity, not editor**
Diagnostics are owned by `FileDiagnosticsStore` keyed by file/document identity. They are rendered with `NSLayoutManager` temporary attributes only. Do not mutate `NSTextStorage` permanently for diagnostic rendering. Do not make `BuildService` the owner of diagnostics.

**All file mutations via `ProjectService`**
Never call `FileManager` directly from a view or from `AppEnvironment`. All file system mutations go through `ProjectService`.

**All colors and fonts from `IDETheme`**
No hardcoded hex values in view files. If a color or font constant is not in `IDETheme`, add it there.

**One-way routing: event → file identity → editor**
`BuildService` and `RuntimeService` route to editors via file/document identity events. The reverse (editor holding a reference to a build or runtime service) is forbidden.

---

## Coding standards

- **macOS 14+ only** — use the two-parameter `onChange(of:) { old, new in }` syntax; no backwards compatibility shims
- **No force unwraps** except where the invariant is guaranteed and locally obvious
- **No `print()` in committed code** — use `SPPLogger`
- **Views are thin wrappers** — no business logic in SwiftUI views; logic belongs in services or view models
- **No TODO comments in code** — if something is incomplete, track it in an issue

---

## Pull request scope

Keep PRs narrow. A PR that fixes a bug in the file navigator should not also touch the editor. A PR that adds a new syntax highlighting rule should not also refactor the highlighter's data structures.

If you are making a large change, propose it in an issue first. The architecture has been through several rounds of refactoring and the current structure is stable by design.

---

## What to work on

Good first contributions:
- Syntax highlighting improvements (new languages or token patterns)
- File type icon additions
- Build console output parsing improvements
- `SPPTheosKit` NIC template additions
- Documentation improvements

Higher-risk areas (coordinate first):
- Any change to `EditorAreaView` or the NSTextView pool
- `AppEnvironment` state management changes
- `FileDiagnosticsStore` (in active development during M6)
- Any new service with side effects

---

## Build and test

```bash
# Build the app
swift build --package-path Apps/SwiftPlaygroundPlusPlusStudio

# Build and launch for manual testing
./script/build_and_run.sh

# Build and verify the app launches (for CI-style checks)
./script/build_and_run.sh --verify
```

The build must pass after every change. There are no automated tests yet (UI testing a pooled NSTextView is non-trivial). Manual verification of the affected feature is expected.

---

## Issues

Use the GitHub issue templates. For bugs, include:
- macOS version
- What you were doing
- What happened
- What you expected

For feature requests, explain the tweak development workflow problem you are trying to solve, not just the feature you want.

---

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
