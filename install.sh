#!/bin/bash
# =============================================================================
# claude-sync installer
# Usage:
#   curl -fsSL https://github.com/no1ysc/dotclaude/main/install.sh | bash
#   curl -fsSL https://github.com/no1ysc/dotclaude/main/install.sh | PRIVATE_REMOTE=git@github.com:you/private-claude.git bash
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

# ── Prerequisites ─────────────────────────────
command -v git >/dev/null 2>&1 || err "git is not installed"

MAIN_REPO=$(git rev-parse --show-toplevel 2>/dev/null) \
  || err "Please run inside a git repository"

CLAUDE_DIR="$MAIN_REPO/.claude"
HOOKS_DIR="$MAIN_REPO/.git/hooks"
CURRENT_BRANCH=$(git -C "$MAIN_REPO" rev-parse --abbrev-ref HEAD)

ok "Main repo: $MAIN_REPO"
ok "Current branch: $CURRENT_BRANCH"

# ── .gitignore ────────────────────────────────
GITIGNORE="$MAIN_REPO/.gitignore"
if ! grep -qxF ".claude/" "$GITIGNORE" 2>/dev/null; then
  echo ".claude/" >> "$GITIGNORE"
  ok "Added .claude/ to .gitignore"
else
  info ".claude/ is already in .gitignore"
fi

# ── Initialize .claude/ git repo ─────────────
mkdir -p "$CLAUDE_DIR"

if [ ! -d "$CLAUDE_DIR/.git" ]; then
  git -C "$CLAUDE_DIR" init --quiet
  ok "Initialized .claude/ git repo"
else
  info ".claude/ is already a git repo"
fi

if [ -n "$PRIVATE_REMOTE" ]; then
  if git -C "$CLAUDE_DIR" remote get-url origin &>/dev/null; then
    git -C "$CLAUDE_DIR" remote set-url origin "$PRIVATE_REMOTE"
  else
    git -C "$CLAUDE_DIR" remote add origin "$PRIVATE_REMOTE"
  fi
  ok "remote origin: $PRIVATE_REMOTE"
else
  warn "PRIVATE_REMOTE not set — you can add it later: git -C .claude remote add origin <url>"
fi

# Match branch
git -C "$CLAUDE_DIR" checkout -b "$CURRENT_BRANCH" --quiet 2>/dev/null || \
  git -C "$CLAUDE_DIR" checkout "$CURRENT_BRANCH" --quiet 2>/dev/null || true

# ── Install hooks ────────────────────────────
echo ""
echo -e "${BOLD}Installing hooks...${RESET}"

install_hook() {
  local NAME="$1"
  local DEST="$HOOKS_DIR/$NAME"

  # Backup existing hook
  if [ -f "$DEST" ] && ! grep -q "claude-sync" "$DEST" 2>/dev/null; then
    cp "$DEST" "${DEST}.bak"
    info "Backed up existing $NAME to ${NAME}.bak"
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

# ── Create git-wrapper.sh ────────────────────
WRAPPER_PATH="$HOME/.claude-sync-wrapper.sh"

cat > "$WRAPPER_PATH" << 'WRAPPER'
#!/bin/bash
# claude-sync git wrapper
# fetch / stash / worktree synchronization
# source path: ~/.claude-sync-wrapper.sh

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

# ── Check shell rc registration ──────────────
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
    ok "Auto-registered shell wrapper in $SHELL_RC"
  else
    info "Shell wrapper is already registered"
  fi
else
  warn "Could not find a shell rc file. Please add this manually:"
  info "$SOURCE_LINE"
fi

# ── Branch sync function (can be called manually after install) ──
claude_sync_branch() {
  local TARGET_BRANCH="${1:-}"

  # If no argument, use current main repo branch
  if [ -z "$TARGET_BRANCH" ]; then
    TARGET_BRANCH=$(git -C "$MAIN_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null) \
      || { warn "Failed to detect branch"; return 1; }
  fi

  if [ ! -d "$CLAUDE_DIR/.git" ]; then
    warn ".claude/ git repo not found - please complete installation first"
    return 1
  fi

  cd "$CLAUDE_DIR"

  # Temporarily stash uncommitted changes
  local HAS_CHANGES=false
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    git stash push --quiet -m "claude-sync branch-sync stash" 2>/dev/null
    HAS_CHANGES=true
  fi

  # Switch branch (create if not exists)
  if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    git checkout "$TARGET_BRANCH" --quiet
  elif git remote get-url origin &>/dev/null && \
       git ls-remote --exit-code origin "$TARGET_BRANCH" &>/dev/null; then
    git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH" --quiet
  else
    git checkout -b "$TARGET_BRANCH" --quiet
  fi

  ok ".claude/ branch → $TARGET_BRANCH"

  # Pull latest from remote
  if git remote get-url origin &>/dev/null; then
    git pull origin "$TARGET_BRANCH" --quiet --strategy-option=ours 2>/dev/null \
      && ok ".claude/ pull complete" || true
  fi

  # Restore stash
  [ "$HAS_CHANGES" = true ] && git stash pop --quiet 2>/dev/null || true

  cd "$MAIN_REPO"
}

# Immediately sync with current branch at the end of installation
echo ""
echo -e "${BOLD}Syncing branch...${RESET}"
claude_sync_branch "$CURRENT_BRANCH"

# ── Complete ─────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}${BOLD}Installation Complete!${RESET}"
echo ""
if [ -n "$PRIVATE_REMOTE" ]; then
  echo "  First push to private repo:"
  echo -e "  ${BOLD}git -C .claude push -u origin $CURRENT_BRANCH${RESET}"
else
  echo "  Connect to private repo:"
  echo -e "  ${BOLD}git -C .claude remote add origin git@github.com:YOU/private-claude.git${RESET}"
  echo -e "  ${BOLD}git -C .claude push -u origin $CURRENT_BRANCH${RESET}"
fi
echo ""
echo "  Apply shell wrapper:"
echo -e "  ${BOLD}source ${SHELL_RC:-~/.zshrc}${RESET}"
echo ""
echo "  Manual branch sync (if needed):"
echo -e "  ${BOLD}git -C .claude checkout <branch_name>${RESET}"
echo ""
