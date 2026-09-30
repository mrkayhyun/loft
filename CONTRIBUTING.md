# Contributing to Loft

Thanks for your interest! Loft is a small, focused project — clear bug reports and
well-scoped pull requests are the most helpful contributions.

_English · [한국어](#기여-안내-한국어)_

## Getting started

Requirements: macOS 15+, Swift 6 toolchain (Xcode 16), Rust 1.80+.

```sh
git clone https://github.com/mrkayhyun/loft.git
cd loft
cargo test  --manifest-path engine/Cargo.toml
swift test  --package-path app
scripts/build-app.sh
```

## Before opening a pull request

- Keep changes focused; one logical change per PR.
- Run the full test suite and the localization check:
  ```sh
  cargo test --manifest-path engine/Cargo.toml
  swift test --package-path app
  scripts/check-l10n.sh
  ```
- Any new user-facing string must have both an English and a Korean translation
  (`scripts/check-l10n.sh` enforces this).
- Match the existing code style. Rust: `cargo fmt` and `cargo clippy`. Swift: follow the
  surrounding conventions.

## Reporting bugs

Open an issue with your macOS version, steps to reproduce, and what you expected vs. what happened.
For anything security-sensitive, follow [SECURITY.md](SECURITY.md) instead of filing a public issue.

## License of contributions

By contributing you agree that your contributions are licensed under the project's
**GPL-3.0-only** license.

---

## 기여 안내 (한국어)

관심 가져주셔서 감사합니다! Loft는 작고 목적이 분명한 프로젝트입니다 — 명확한 버그 리포트와
범위가 잘 정리된 풀 리퀘스트가 가장 큰 도움이 됩니다.

### 시작하기

요구 사항: macOS 15 이상, Swift 6 툴체인(Xcode 16), Rust 1.80 이상.

```sh
git clone https://github.com/mrkayhyun/loft.git
cd loft
cargo test  --manifest-path engine/Cargo.toml
swift test  --package-path app
scripts/build-app.sh
```

### 풀 리퀘스트를 열기 전에

- 변경을 한 가지 논리 단위로 좁게 유지해 주세요 (PR 하나당 하나의 변경).
- 전체 테스트와 현지화 검사를 실행하세요:
  ```sh
  cargo test --manifest-path engine/Cargo.toml
  swift test --package-path app
  scripts/check-l10n.sh
  ```
- 새로 추가되는 사용자 노출 문자열에는 영어와 한국어 번역이 모두 있어야 합니다
  (`scripts/check-l10n.sh`가 이를 강제합니다).
- 기존 코드 스타일을 따라 주세요. Rust는 `cargo fmt`·`cargo clippy`, Swift는 주변 코드 관례를 따릅니다.

### 버그 리포트

macOS 버전, 재현 절차, 기대한 동작과 실제 동작을 함께 이슈로 남겨 주세요.
보안 관련 사안은 공개 이슈 대신 [SECURITY.md](SECURITY.md)의 절차를 따라 주세요.

### 기여물의 라이선스

기여하시면 해당 기여물이 프로젝트의 **GPL-3.0-only** 라이선스로 배포되는 데 동의하는 것으로 간주합니다.
