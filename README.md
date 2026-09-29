# Loft

Safe, fast macOS cleanup — a Rust engine with a native SwiftUI app.

- **Smart Clean** — caches, logs and developer leftovers, reviewed before anything moves to the Trash
- **Uninstaller** — apps plus files matched by their exact bundle identifier
- **Space Lens** — treemap disk explorer
- **Monitor** — live CPU, memory, disk, network and battery

UI languages: English, 한국어 (follows the system or per-app language setting).

## Layout

| Path | What |
|---|---|
| `engine/` | Rust workspace: `loft-core` (scan, guard, sizing, execution) and the `loft` CLI |
| `engine/rules/clean.toml` | Declarative cleanup catalog |
| `app/` | SwiftPM package: `LoftKit` (models, engine client, treemap) and the `Loft` app |
| `app/Localization/` | `.strings` tables (`Localizable` for UI, `Engine` for engine text) |
| `scripts/` | `build-app.sh`, `check-l10n.sh`, `make-icon.swift` |

## Build

```sh
scripts/build-app.sh          # → dist/Loft.app (engine + app + icon, ad-hoc signed)
```

Tests:

```sh
cargo test --manifest-path engine/Cargo.toml
swift test --package-path app
scripts/check-l10n.sh         # every UI string and category has a Korean translation
```

## Safety model

Scanning is read-only and produces a plan. Before each item is removed the engine re-checks that the
path still matches its catalog rule, passes the path guard (home only; documents, iCloud, keychains and
password managers are off limits), is not held by a running app, and still has the same `(dev, ino)`
seen during the scan. Items go to the Trash; only items already in the Trash can be deleted permanently.

## License

GPL-3.0-only. The cleanup rules and safety approach are derived from
[tw93/mole](https://github.com/tw93/mole) (GPL-3.0). Loft is an independent project and is not
affiliated with or endorsed by Mole.
