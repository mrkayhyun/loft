# Security Policy

_English · [한국어](#보안-정책-한국어)_

Loft deletes files on the user's machine, so we take safety and security seriously.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, use GitHub's private
[**Report a vulnerability**](https://github.com/mrkayhyun/loft/security/advisories/new) advisory flow.

Include: affected version, a description of the issue, and steps to reproduce or a proof of concept.
We aim to acknowledge reports within a few days.

## Scope

Of particular interest: any path or bundle that bypasses the path guard (home-only; documents,
iCloud, keychains and password managers are off limits), any case where an item is removed without
passing the pre-delete re-check, or any escalation beyond the current user's permissions.

---

## 보안 정책 (한국어)

Loft는 사용자 기기의 파일을 삭제하므로 안전성과 보안을 중요하게 다룹니다.

### 취약점 제보

보안 문제는 **공개 이슈로 올리지 말아 주세요.** 대신 GitHub의 비공개
[**Report a vulnerability**](https://github.com/mrkayhyun/loft/security/advisories/new) 권고 절차를 이용해 주세요.

제보 시 영향받는 버전, 문제 설명, 재현 절차 또는 개념 증명(PoC)을 포함해 주세요.
가능한 한 며칠 안에 접수 확인을 드리겠습니다.

### 관심 범위

특히 다음에 주목합니다: 경로 가드(홈 디렉터리 한정 — 문서·iCloud·키체인·비밀번호 관리자 제외)를 우회하는
경로·번들, 삭제 전 재확인을 통과하지 않고 항목이 제거되는 경우, 현재 사용자 권한을 넘어서는 권한 상승.
