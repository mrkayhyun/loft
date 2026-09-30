<div align="center">
  <h1>Loft</h1>
  <p><em>🧹 Safe, fast macOS cleanup — a Rust engine with a native SwiftUI app.</em></p>
</div>

<p align="center">
  <a href="https://github.com/mrkayhyun/loft/stargazers"><img src="https://img.shields.io/github/stars/mrkayhyun/loft?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/mrkayhyun/loft/releases"><img src="https://img.shields.io/github/v/tag/mrkayhyun/loft?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL_v3-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/mrkayhyun/loft/actions"><img src="https://img.shields.io/github/actions/workflow/status/mrkayhyun/loft/ci.yml?branch=master&style=flat-square" alt="CI"></a>
  <a href="https://github.com/mrkayhyun/loft/commits"><img src="https://img.shields.io/github/commit-activity/m/mrkayhyun/loft?style=flat-square" alt="Commits"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square&logo=apple" alt="macOS 15+">
</p>

<p align="center">
  <em>English · <a href="#한국어">한국어</a></em>
</p>

<!-- Add a hero screenshot once available, e.g.:
<p align="center">
  <img src="./docs/img/loft.png" alt="Loft cleanup results" width="1000" />
</p>
-->

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

Requires macOS 15+, Swift 6 toolchain (Xcode 16) and Rust 1.80+.

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

## Contributing

Bug reports, feature ideas and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
To report a security issue, see [SECURITY.md](SECURITY.md).

## License

GPL-3.0-only. The cleanup rules and safety approach are derived from
[tw93/mole](https://github.com/tw93/mole) (GPL-3.0). Loft is an independent project and is not
affiliated with or endorsed by Mole.

---

## 한국어

안전하고 빠른 macOS 정리 도구 — Rust 엔진과 네이티브 SwiftUI 앱.

- **스마트 클린** — 캐시·로그·개발 잔여물을 정리하며, 휴지통으로 옮기기 전에 항목을 검토합니다
- **삭제 관리자(Uninstaller)** — 앱과, 정확한 번들 식별자로 매칭된 관련 파일을 함께 삭제합니다
- **스페이스 렌즈** — 트리맵 방식 디스크 탐색기
- **모니터** — CPU·메모리·디스크·네트워크·배터리 실시간 확인

UI 언어: English, 한국어 (시스템 설정 또는 앱별 언어 설정을 따릅니다).

### 구성

| 경로 | 내용 |
|---|---|
| `engine/` | Rust 워크스페이스: `loft-core`(스캔·가드·용량 계산·실행)와 `loft` CLI |
| `engine/rules/clean.toml` | 선언형 정리 규칙 카탈로그 |
| `app/` | SwiftPM 패키지: `LoftKit`(모델·엔진 클라이언트·트리맵)와 `Loft` 앱 |
| `app/Localization/` | `.strings` 테이블 (UI는 `Localizable`, 엔진 텍스트는 `Engine`) |
| `scripts/` | `build-app.sh`, `check-l10n.sh`, `make-icon.swift` |

### 빌드

macOS 15 이상, Swift 6 툴체인(Xcode 16), Rust 1.80 이상이 필요합니다.

```sh
scripts/build-app.sh          # → dist/Loft.app (엔진 + 앱 + 아이콘, ad-hoc 서명)
```

테스트:

```sh
cargo test --manifest-path engine/Cargo.toml
swift test --package-path app
scripts/check-l10n.sh         # 모든 UI 문자열과 카테고리에 한국어 번역이 있는지 검사
```

### 안전 모델

스캔은 읽기 전용이며 실행 계획만 만듭니다. 각 항목을 실제로 제거하기 전에 엔진은 다음을 다시 확인합니다:
경로가 여전히 카탈로그 규칙에 매칭되는지, 경로 가드를 통과하는지(홈 디렉터리 한정 — 문서·iCloud·키체인·비밀번호
관리자는 대상에서 제외), 실행 중인 앱이 점유하고 있지 않은지, 스캔 당시와 동일한 `(dev, ino)` 값을 유지하는지.
항목은 휴지통으로 이동하며, 이미 휴지통에 있는 항목만 영구 삭제할 수 있습니다.

### 기여

버그 리포트·기능 제안·풀 리퀘스트를 환영합니다 — [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.
보안 취약점 제보는 [SECURITY.md](SECURITY.md)를 확인하세요.

### 라이선스

GPL-3.0-only. 정리 규칙과 안전 접근 방식은 [tw93/mole](https://github.com/tw93/mole)(GPL-3.0)에서
파생되었습니다. Loft는 독립적인 프로젝트이며 Mole와 제휴하거나 승인을 받은 관계가 아닙니다.
