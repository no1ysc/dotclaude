# dotclaude

> [Read in English](README.md)

> `.claude/` 폴더를 public repo에서 완전히 숨기면서, 메인 레포의 모든 git 동작과 자동으로 동기화하는 훅 모음

---

## 배경과 철학

Claude Code는 `.claude/rules/` 디렉토리를 재귀적으로 스캔하여 작업 중인 모듈의 컨텍스트를 자동으로 주입한다.
이 특성을 활용하면, 모노레포의 실제 폴더 구조를 `.claude/rules/` 안에 그대로 미러링하는 것이 가능하다.
```
.claude/
└── rules/
    └── packages/
        ├── frontend/
        │   ├── components/
        │   │   └── button.md      ← packages/frontend/components/** 작업 시 자동 로드
        │   └── hooks/
        │       └── auth.md
        └── backend/
            └── api/
                └── payment.md
```

각 `.md` 파일에는 해당 모듈의 spec, 구현 규칙, 그리고 Claude에게 줄 컨텍스트를 담는다.
path glob frontmatter를 붙이면 관련 없는 작업에는 로드되지 않아 **토큰 비용도 최소화**된다.
```markdown
---
paths:
  - "packages/frontend/components/**"
---

# Button 컴포넌트 spec
...
```

이 구조의 문제는 하나다.
`.claude/rules/` 안에는 팀에 공개하고 싶지 않은 개인 노하우, 작업 방식, 프롬프트 전략이 담긴다.
그렇다고 버저닝을 포기할 수는 없다. 브랜치마다, 기능마다 축적된 컨텍스트가 있기 때문이다.

**dotclaude는 이 문제를 해결한다.**

- `.claude/` 폴더 전체를 public repo에서 완전히 제거한다
- 별도의 private repo에서 독립적으로 버저닝한다
- 메인 레포의 commit, push, pull, checkout, rebase, stash, worktree 모든 동작에 자동으로 따라붙는다
- 메인 레포의 .gitignore 의 설정에 따라 메인리포에 여전히 남겨 둘 수도 있다.
- **public repo에 private repo의 흔적은 단 하나도 남지 않는다**

---

## public repo에 남는 것

설치 후 public repo에 추가되는 내용은 `.gitignore`의 한 줄뿐이다.
```
.claude/
```

private repo의 URL, 훅 파일, wrapper 스크립트는 모두 아래 위치에만 존재한다.

| 항목 | 위치 | 버저닝 여부 |
|---|---|---|
| `.claude/` 전체 | gitignore, 로컬에만 존재 | private repo |
| git hooks | `.git/hooks/` (git이 버저닝 안 함) | — |
| shell wrapper | `~/.claude-sync-wrapper.sh` (홈 디렉토리) | — |

---

## 커버 범위

| git 작업 | 처리 방식 | 동작 |
|---|---|---|
| `commit` | post-commit hook | .claude 변경사항 자동 커밋 |
| `push` | pre-push hook | .claude도 함께 push |
| `pull` / `merge` | post-merge hook | .claude도 함께 pull |
| `checkout` | post-checkout hook | .claude 브랜치 동기화 |
| `rebase` / `amend` | post-rewrite hook | .claude 커밋 정리 |
| `fetch` | shell wrapper | .claude도 fetch |
| `stash push/pop` | shell wrapper | .claude stash 동기화 |
| `worktree add` | shell wrapper | 새 worktree에 .claude 초기화 |
| `worktree remove` | shell wrapper | worktree .claude 정리 |

---

## 설치

### 요구사항

- git 2.x 이상
- bash 또는 zsh

### 한 줄 설치
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotclaude-sync/main/install.sh | bash
```

private repo URL을 함께 전달하면 remote까지 한 번에 설정된다.
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotclaude-sync/main/install.sh \
  | PRIVATE_REMOTE=git@github.com:you/private-claude.git bash
```

설치 스크립트가 자동으로 처리하는 것들:
- `.claude/` → `.gitignore` 추가
  - 메인 레포의 .gitignore 의 설정에 따라 메인리포에 여전히 남겨 둘 수도 있다.
- `.claude/` git repo 초기화 및 remote 설정
- git hooks 5개 설치 (기존 훅 있으면 `.bak`으로 백업)
- `~/.claude-sync-wrapper.sh` 생성
- `~/.zshrc` 또는 `~/.bashrc`에 wrapper 자동 등록
- 현재 브랜치로 `.claude/` 브랜치 즉시 동기화

### shell wrapper 적용

설치 완료 후 한 번만 실행한다.
```bash
source ~/.zshrc  # 또는 source ~/.bashrc
```

이후부터 `git` 명령어는 자동으로 `.claude/`를 함께 동기화한다.

---

## 사용법

설치 후에는 기존 git 워크플로우 그대로 사용하면 된다.
```bash
# 메인 레포 작업
git add .
git commit -m "feat: 버튼 컴포넌트 추가"
# → post-commit hook이 .claude/도 자동 커밋

git push origin main
# → pre-push hook이 .claude/도 자동 push

git pull
# → post-merge hook이 .claude/도 자동 pull

git checkout -b feature/payment
# → post-checkout hook이 .claude/도 같은 브랜치로 전환

git fetch origin
# → shell wrapper가 .claude/도 fetch

git stash
# → shell wrapper가 .claude/도 stash

git worktree add ../payment-worktree feature/payment
# → shell wrapper가 새 worktree에 .claude/ 자동 초기화
```

### private repo 최초 연결

설치 후 처음 한 번만 실행한다.
```bash
# remote가 설치 시 설정되지 않은 경우
git -C .claude remote add origin git@github.com:you/private-claude.git

# 최초 push
git -C .claude push -u origin main
```

### 브랜치 수동 동기화

훅이 어긋났거나 새 환경에서 맞춰야 할 때 사용한다.
```bash
# 현재 메인 레포 브랜치로 맞추기
git -C .claude checkout main

# 또는 설치 스크립트를 다시 실행
curl -fsSL .../install.sh | bash
```

---

## 새 환경 / 팀 합류 시
```bash
# 1. 메인 레포 clone
git clone git@github.com:team/main-repo.git
cd main-repo

# 2. dotclaude-sync 설치
curl -fsSL .../install.sh | PRIVATE_REMOTE=git@github.com:you/private-claude.git bash

# 3. private repo에서 기존 .claude/ 복원
git -C .claude pull origin main

# 4. shell wrapper 적용
source ~/.zshrc
```

---

## .claude/rules/ 구조 설계 예시 및 가이드

path glob frontmatter를 활용하면 불필요한 컨텍스트 로딩을 방지할 수 있다.
```markdown
---
paths:
  - "packages/frontend/**"
---
```

glob 없이 작성한 파일은 세션 시작 시 항상 로드된다. 프로젝트 전역 규칙에 적합하다.

권장 구조:
```
.claude/
├── CLAUDE.md                         ← 프로젝트 전역 규칙 (항상 로드)
└── rules/
    ├── conventions.md                ← 전역 코드 컨벤션 (항상 로드)
    └── packages/
        ├── frontend/
        │   ├── index.md              ← frontend 전체 규칙
        │   ├── components/
        │   │   └── *.md              ← 컴포넌트별 spec
        │   └── hooks/
        │       └── *.md
        └── backend/
            ├── index.md
            └── api/
                └── *.md
```

---

## 주의사항

- pull 충돌 시 로컬(내 작업) 우선 전략 적용
- remote origin 미설정 시 push/pull은 조용히 스킵됨 (에러 없음)
- 기존 git hook 있으면 `.bak`으로 백업 후 교체
- worktree는 메인 `.claude/`를 local clone하여 독립적으로 구성됨

---

## License

MIT
