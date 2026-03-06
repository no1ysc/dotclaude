#!/bin/bash
# =============================================================================
# claude-sync installer
# 사용법:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-sync/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-sync/main/install.sh | PRIVATE_REMOTE=git@github.com:you/private-claude.git bash
# =============================================================================

set -e

PRIVATE_REMOTE="${PRIVATE_REMOTE:-}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $1"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $1"; }
err()  { echo -e "${RED}✗${RESET} $1"; exit 1; }
info() { echo -e "  $1"; }

echo ""
echo -e "${BOLD}claude-sync installer${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 사전 확인 ─────────────────────────────────
command -v git >/dev/null 2>&1 || err "git이 설치되어 있지 않습니다"

MAIN_REPO=$(git rev-parse --show-toplevel 2>/dev/null) \
  || err "git 레포 안에서 실행해주세요"

CLAUDE_DIR="$MAIN_REPO/.claude"
HOOKS_DIR="$MAIN_REPO/.git/hooks"
CURRENT_BRANCH=$(git -C "$MAIN_REPO" rev-parse --abbrev-ref HEAD)

ok "메인 레포: $MAIN_REPO"
ok "현재 브랜치: $CURRENT_BRANCH"

# ── .gitignore ────────────────────────────────
GITIGNORE="$MAIN_REPO/.gitignore"
if ! grep -qxF ".claude/" "$GITIGNORE" 2>/dev/null; then
  echo ".claude/" >> "$GITIGNORE"
  ok ".claude/ → .gitignore 추가"
else
  info ".claude/ 이미 .gitignore에 있음"
fi

# ── .claude/ git repo 초기화 ──────────────────
mkdir -p "$CLAUDE_DIR"

if [ ! -d "$CLAUDE_DIR/.git" ]; then
  git -C "$CLAUDE_DIR" init --quiet
  ok ".claude/ git repo 초기화"
else
  info ".claude/ 이미 git repo"
fi

if [ -n "$PRIVATE_REMOTE" ]; then
  if git -C "$CLAUDE_DIR" remote get-url origin &>/dev/null; then
    git -C "$CLAUDE_DIR" remote set-url origin "$PRIVATE_REMOTE"
  else
    git -C "$CLAUDE_DIR" remote add origin "$PRIVATE_REMOTE"
  fi
  ok "remote origin: $PRIVATE_REMOTE"
else
  warn "PRIVATE_REMOTE 미설정 — 나중에 추가: git -C .claude remote add origin <url>"
fi

# 브랜치 맞추기
git -C "$CLAUDE_DIR" checkout -b "$CURRENT_BRANCH" --quiet 2>/dev/null || \
  git -C "$CLAUDE_DIR" checkout "$CURRENT_BRANCH" --quiet 2>/dev/null || true

# ── hooks 설치 ────────────────────────────────
echo ""
echo -e "${BOLD}hooks 설치 중...${RESET}"

install_hook() {
  local NAME="$1"
  local DEST="$HOOKS_DIR/$NAME"

  # 기존 훅 백업
  if [ -f "$DEST" ] && ! grep -q "claude-sync" "$DEST" 2>/dev/null; then
    cp "$DEST" "${DEST}.bak"
    info "기존 $NAME → ${NAME}.bak 백업"
  fi

  cat > "$DEST"
  chmod +x "$DEST"
  ok "$NAME"
}

# ── post-commit ───────────────────────────────
install_hook "post-commit" << 'HOOK'
#!/bin/bash
# claude-sync: post-commit
MAIN_REPO=$(git rev-parse --show-toplevel)
CLAUDE_DIR="$MAIN_REPO/.claude"
[ ! -d "$CLAUDE_DIR/.git" ] && exit 0
MAIN_HASH=$(git rev-parse HEAD)
MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
cd "$CLAUDE_DIR"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "sync: $MAIN_BRANCH@${MAIN_HASH:0:8}" --quiet
fi
exit 0
HOOK

# ── pre-push ──────────────────────────────────
install_hook "pre-push" << 'HOOK'
#!/bin/bash
# claude-sync: pre-push
MAIN_REPO=$(git rev-parse --show-toplevel)
CLAUDE_DIR="$MAIN_REPO/.claude"
[ ! -d "$CLAUDE_DIR/.git" ] && exit 0
MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
cd "$CLAUDE_DIR"
if ! git remote get-url origin &>/dev/null; then exit 0; fi
git add -A
if ! git diff --cached --quiet; then
  MAIN_HASH=$(git -C "$MAIN_REPO" rev-parse HEAD)
  git commit -m "sync: $MAIN_BRANCH@${MAIN_HASH:0:8} (pre-push)" --quiet
fi
git push origin "$MAIN_BRANCH" --quiet 2>/dev/null || \
  git push origin HEAD:"$MAIN_BRANCH" --quiet 2>/dev/null || true
exit 0
HOOK

# ── post-merge ────────────────────────────────
install_hook "post-merge" << 'HOOK'
#!/bin/bash
# claude-sync: post-merge
MAIN_REPO=$(git rev-parse --show-toplevel)
CLAUDE_DIR="$MAIN_REPO/.claude"
[ ! -d "$CLAUDE_DIR/.git" ] && exit 0
MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
cd "$CLAUDE_DIR"
if ! git remote get-url origin &>/dev/null; then exit 0; fi
git fetch origin --quiet 2>/dev/null || true
git checkout "$MAIN_BRANCH" --quiet 2>/dev/null || \
  git checkout -b "$MAIN_BRANCH" "origin/$MAIN_BRANCH" --quiet 2>/dev/null || \
  git checkout -b "$MAIN_BRANCH" --quiet 2>/dev/null || true
git pull origin "$MAIN_BRANCH" --quiet --strategy-option=ours 2>/dev/null || true
exit 0
HOOK

# ── post-checkout ─────────────────────────────
install_hook "post-checkout" << 'HOOK'
#!/bin/bash
# claude-sync: post-checkout
BRANCH_CHECKOUT="$3"
[ "$BRANCH_CHECKOUT" != "1" ] && exit 0
MAIN_REPO=$(git rev-parse --show-toplevel)
CLAUDE_DIR="$MAIN_REPO/.claude"
NEW_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_DIR=$(git rev-parse --git-dir)
IS_WORKTREE=false
[[ "$GIT_DIR" == *"/worktrees/"* ]] && IS_WORKTREE=true
if [ "$IS_WORKTREE" = true ]; then
  MAIN_GIT_TOPLEVEL=$(git rev-parse --git-common-dir | sed 's|/.git.*||')
  if [ -n "$MAIN_GIT_TOPLEVEL" ] && [ -d "$MAIN_GIT_TOPLEVEL/.claude/.git" ]; then
    if [ ! -d "$CLAUDE_DIR/.git" ]; then
      mkdir -p "$CLAUDE_DIR"
      git clone --local --quiet "$MAIN_GIT_TOPLEVEL/.claude" "$CLAUDE_DIR" 2>/dev/null || true
    fi
  fi
fi
[ ! -d "$CLAUDE_DIR/.git" ] && exit 0
cd "$CLAUDE_DIR"
HAS_CHANGES=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push --quiet -m "claude-sync auto-stash" 2>/dev/null
  HAS_CHANGES=true
fi
git checkout "$NEW_BRANCH" --quiet 2>/dev/null || \
  git checkout -b "$NEW_BRANCH" --quiet 2>/dev/null || true
if git remote get-url origin &>/dev/null; then
  git pull origin "$NEW_BRANCH" --quiet 2>/dev/null || true
fi
[ "$HAS_CHANGES" = true ] && git stash pop --quiet 2>/dev/null || true
exit 0
HOOK

# ── post-rewrite ──────────────────────────────
install_hook "post-rewrite" << 'HOOK'
#!/bin/bash
# claude-sync: post-rewrite
MAIN_REPO=$(git rev-parse --show-toplevel)
CLAUDE_DIR="$MAIN_REPO/.claude"
[ ! -d "$CLAUDE_DIR/.git" ] && exit 0
MAIN_HASH=$(git rev-parse HEAD)
MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
cd "$CLAUDE_DIR"
git checkout "$MAIN_BRANCH" --quiet 2>/dev/null || \
  git checkout -b "$MAIN_BRANCH" --quiet 2>/dev/null || true
git add -A
if ! git diff --cached --quiet; then
  git commit -m "sync: $MAIN_BRANCH@${MAIN_HASH:0:8} (post-$1)" --quiet
fi
exit 0
HOOK

# ── git-wrapper.sh 생성 ───────────────────────
WRAPPER_PATH="$HOME/.claude-sync-wrapper.sh"

cat > "$WRAPPER_PATH" << 'WRAPPER'
#!/bin/bash
# claude-sync git wrapper
# fetch / stash / worktree 동기화
# source 경로: ~/.claude-sync-wrapper.sh

git() {
  _claude_dir() {
    local t; t=$(command git rev-parse --show-toplevel 2>/dev/null) || return 1
    echo "$t/.claude"
  }

  case "$1" in
    fetch)
      command git "$@"; local e=$?
      if [ $e -eq 0 ]; then
        local d; d=$(_claude_dir) || return $e
        if [ -d "$d/.git" ] && command git -C "$d" remote get-url origin &>/dev/null; then
          command git -C "$d" fetch origin --quiet 2>/dev/null || true
        fi
      fi
      return $e ;;

    stash)
      local d; d=$(_claude_dir 2>/dev/null); local hc=false
      [ -d "${d}/.git" ] && hc=true
      case "$2" in
        push|"")
          if [ "$hc" = true ]; then
            local b; b=$(command git rev-parse --abbrev-ref HEAD 2>/dev/null)
            command git -C "$d" stash push --quiet -m "claude-sync:stash:$b" 2>/dev/null || true
          fi
          command git "$@" ;;
        pop|apply)
          command git "$@"; local e=$?
          [ $e -eq 0 ] && [ "$hc" = true ] && command git -C "$d" stash pop --quiet 2>/dev/null || true
          return $e ;;
        drop)
          command git "$@"; local e=$?
          [ $e -eq 0 ] && [ "$hc" = true ] && command git -C "$d" stash drop --quiet 2>/dev/null || true
          return $e ;;
        *) command git "$@" ;;
      esac ;;

    worktree)
      case "$2" in
        add)
          command git "$@"; local e=$?
          if [ $e -eq 0 ] && [ -d "$3" ]; then
            local s; s=$(_claude_dir 2>/dev/null)
            if [ -d "${s}/.git" ] && [ ! -d "$3/.claude/.git" ]; then
              command git clone --local --quiet "$s" "$3/.claude" 2>/dev/null
              local b="${4:-$(basename "$3")}"
              command git -C "$3/.claude" checkout "$b" --quiet 2>/dev/null || \
                command git -C "$3/.claude" checkout -b "$b" --quiet 2>/dev/null || true
            fi
          fi
          return $e ;;
        remove|prune)
          local p="$3"
          command git "$@"; local e=$?
          [ $e -eq 0 ] && [ -d "$p/.claude/.git" ] && rm -rf "$p/.claude"
          return $e ;;
        *) command git "$@" ;;
      esac ;;

    *) command git "$@" ;;
  esac
}
WRAPPER

ok "git-wrapper.sh → $WRAPPER_PATH"

# ── shell rc 등록 여부 확인 ───────────────────
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

SOURCE_LINE="source $WRAPPER_PATH  # claude-sync"

if [ -n "$SHELL_RC" ]; then
  if ! grep -q "claude-sync" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "$SOURCE_LINE" >> "$SHELL_RC"
    ok "shell wrapper → $SHELL_RC 자동 등록"
  else
    info "shell wrapper 이미 등록됨"
  fi
else
  warn "shell rc 파일을 찾지 못했습니다. 아래를 수동으로 추가하세요:"
  info "$SOURCE_LINE"
fi

# ── 브랜치 동기화 함수 (설치 후 수동 호출도 가능) ──
claude_sync_branch() {
  local TARGET_BRANCH="${1:-}"

  # 인자 없으면 현재 메인 레포 브랜치 사용
  if [ -z "$TARGET_BRANCH" ]; then
    TARGET_BRANCH=$(git -C "$MAIN_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null) \
      || { warn "브랜치 감지 실패"; return 1; }
  fi

  if [ ! -d "$CLAUDE_DIR/.git" ]; then
    warn ".claude/ git repo 없음 - 먼저 설치를 완료하세요"
    return 1
  fi

  cd "$CLAUDE_DIR"

  # 미커밋 변경사항 임시 저장
  local HAS_CHANGES=false
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git stash push --quiet -m "claude-sync branch-sync stash" 2>/dev/null
    HAS_CHANGES=true
  fi

  # 브랜치 전환 (없으면 생성)
  if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    git checkout "$TARGET_BRANCH" --quiet
  elif git remote get-url origin &>/dev/null && \
       git ls-remote --exit-code origin "$TARGET_BRANCH" &>/dev/null; then
    git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH" --quiet
  else
    git checkout -b "$TARGET_BRANCH" --quiet
  fi

  ok ".claude/ 브랜치 → $TARGET_BRANCH"

  # remote에서 최신 pull
  if git remote get-url origin &>/dev/null; then
    git pull origin "$TARGET_BRANCH" --quiet --strategy-option=ours 2>/dev/null \
      && ok ".claude/ pull 완료" || true
  fi

  # stash 복원
  [ "$HAS_CHANGES" = true ] && git stash pop --quiet 2>/dev/null || true

  cd "$MAIN_REPO"
}

# 설치 마지막에 현재 브랜치로 즉시 동기화
echo ""
echo -e "${BOLD}브랜치 동기화 중...${RESET}"
claude_sync_branch "$CURRENT_BRANCH"

# ── 완료 ─────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}${BOLD}설치 완료!${RESET}"
echo ""
if [ -n "$PRIVATE_REMOTE" ]; then
  echo "  private repo 최초 push:"
  echo -e "  ${BOLD}git -C .claude push -u origin $CURRENT_BRANCH${RESET}"
else
  echo "  private repo 연결:"
  echo -e "  ${BOLD}git -C .claude remote add origin git@github.com:YOU/private-claude.git${RESET}"
  echo -e "  ${BOLD}git -C .claude push -u origin $CURRENT_BRANCH${RESET}"
fi
echo ""
echo "  shell wrapper 적용:"
echo -e "  ${BOLD}source ${SHELL_RC:-~/.zshrc}${RESET}"
echo ""
echo "  브랜치 수동 동기화 (필요시):"
echo -e "  ${BOLD}git -C .claude checkout <브랜치명>${RESET}"
echo ""
