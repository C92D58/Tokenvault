# Contributing

Thanks for your interest in contributing to TokenVault!

## Requirements

- macOS 14.0 (Sonoma) or later, Apple Silicon (arm64)
- Xcode Command Line Tools:

```bash
xcode-select --install
```

No Xcode project file is needed — the app is compiled directly by `scripts/build-macos.sh` using
`swiftc`, and the version is stamped from `project.yml`.

## Building locally

```bash
git clone https://github.com/C92D58/TokenVault.git
cd TokenVault
scripts/build-macos.sh
```

The compiled app is at `.build/TokenVault.app`. To run it:

```bash
open .build/TokenVault.app
```

To package a DMG (optional):

```bash
scripts/build-macos.sh && bash package.sh
```

## Submitting a Pull Request

1. Fork the repository and clone it locally
2. Create a branch: `git checkout -b feature/your-feature` or `fix/your-fix`
3. Keep changes focused — one PR solves one problem
4. Make sure `scripts/build-macos.sh` succeeds and the app runs
5. Open the PR with a short description of what changed and why

### Commit messages

Use a type prefix:

- `feat:` new feature
- `fix:` bug fix
- `refactor:` refactoring
- `docs:` documentation
- `polish:` UI/UX polish
- `chore:` maintenance

## Code style

- Follow standard Swift conventions
- All token classification goes through `TokenTaxonomy` (single source of truth) — do not add parallel classification systems
- Keep the UI native macOS: SwiftUI + AppKit, reusing the design system in `DesignSystem/`
- Stay at **zero third-party dependencies** — do not add external packages
- Adding a provider: update `TokenProvider`, the `detect()` logic, and the console URL

## Security

Please do **not** report security vulnerabilities through public issues. See [SECURITY.md](SECURITY.md).

## License

Contributions are licensed under the [MIT License](LICENSE).
