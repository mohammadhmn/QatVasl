# Contributing to QatVasl

Thanks for contributing.

## Development Setup

1. Install Xcode.
2. Install `just` (optional):
   - `brew install just`
3. Clone and enter the repo.
4. Run:

```bash
just doctor
just dev
```

## Branch and PR Flow

1. Create a feature branch from `main`.
2. Keep changes scoped and atomic.
3. Run a local build before opening a PR:

```bash
just build-debug
```

4. Open a pull request with:
   - clear summary
   - testing notes
   - screenshots/GIFs for UI changes

## Code Guidelines

- Prefer small, composable SwiftUI views.
- Keep networking and state logic outside view bodies.
- Avoid adding dependencies unless justified.
- Do not commit local artifacts (`build/`, `DerivedData/`, `.dmg`).

## Commit Message Style

Use short, descriptive commit messages. Conventional commits are recommended:

- `feat:`
- `fix:`
- `refactor:`
- `docs:`
- `test:`
- `chore:`

## Reporting Bugs

Use the bug report issue template and include:

- expected behavior
- actual behavior
- reproduction steps
- macOS and Xcode versions
- app logs (`just logs`) when relevant

## Security Issues

Do not open public issues for vulnerabilities. Follow `SECURITY.md`.
