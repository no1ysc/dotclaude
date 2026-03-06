# dotclaude

> [🇰🇷 한국어로 보기 (Read in Korean)](README_KO.md)

> A collection of git hooks that completely hides the `.claude/` folder from the public repo while automatically synchronizing it with all git operations of the main repo.

---

## Background and Philosophy

Claude Code automatically injects context by recursively scanning the `.claude/rules/` directory for the module you are working on.
By leveraging this feature, you can mirror the actual folder structure of a monorepo directly inside `.claude/rules/`.
```
.claude/
└── rules/
    └── packages/
        ├── frontend/
        │   ├── components/
        │   │   └── button.md      ← Auto-loaded when working on packages/frontend/components/**
        │   └── hooks/
        │       └── auth.md
        └── backend/
            └── api/
                └── payment.md
```

Each `.md` file contains the spec, implementation rules, and context to provide to Claude for its respective module.
By adding a path glob frontmatter, it prevents irrelevant rules from loading during tasks, thereby **minimizing token costs**.
```markdown
---
paths:
  - "packages/frontend/components/**"
---

# Button Component Spec
...
```

There is one problem with this structure.
The `.claude/rules/` directory contains personal know-how, workflow habits, and prompt strategies that you might not want to share with the team.
However, you can't abandon versioning because context accumulates with each branch and feature.

**dotclaude solves this problem.**

- It completely removes the entire `.claude/` folder from the public repo.
- It versions the folder independently in a separate private repo.
- It automatically tracks all git actions of the main repo: commit, push, pull, checkout, rebase, stash, and worktree.
- Depending on the `.gitignore` settings of the main repo, it can optionally be kept in the main repo.
- **Not a single trace of the private repo remains in the public repo.**

---

## What is left in the public repo

After installation, the only thing added to the public repo is a single line in `.gitignore`.
```
.claude/
```

The private repo URL, hook files, and wrapper scripts strictly exist only in the following locations:

| Item | Location | Versioned By |
|---|---|---|
| Complete `.claude/` | gitignore, local only | private repo |
| git hooks | `.git/hooks/` (git ignores this) | — |
| shell wrapper | `~/.claude-sync-wrapper.sh` (home directory) | — |

---

## Coverage

| Git Action | Handler | Behavior |
|---|---|---|
| `commit` | post-commit hook | Auto-commits changes in .claude |
| `push` | pre-push hook | Pushes .claude as well |
| `pull` / `merge` | post-merge hook | Pulls .claude as well |
| `checkout` | post-checkout hook | Synchronizes .claude branch |
| `rebase` / `amend` | post-rewrite hook | Cleans up .claude commits |
| `fetch` | shell wrapper | Fetches .claude as well |
| `stash push/pop` | shell wrapper | Synchronizes .claude stash |
| `worktree add` | shell wrapper | Initializes .claude in new worktree |
| `worktree remove` | shell wrapper | Cleans up worktree .claude |

---

## Installation

### Requirements

- git 2.x or later
- bash or zsh

### One-line Installation
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotclaude-sync/main/install.sh | bash
```

Pass the private repo URL together to configure the remote instantly.
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/dotclaude-sync/main/install.sh \
  | PRIVATE_REMOTE=git@github.com:you/private-claude.git bash
```

What the installation script automatically handles:
- Adds `.claude/` to `.gitignore`
  - Depending on the `.gitignore` config, it might be allowed to stay tracked if desired.
- Initializes `.claude/` git repo and sets up the remote
- Installs 5 git hooks (backs up existing hooks as `.bak`)
- Creates `~/.claude-sync-wrapper.sh`
- Auto-registers the wrapper in `~/.zshrc` or `~/.bashrc`
- Instantly synchronizes the `.claude/` branch with the current branch

### Applying Shell Wrapper

Run this once after installation:
```bash
source ~/.zshrc  # or source ~/.bashrc
```

From now on, the `git` command will automatically synchronize `.claude/`.

---

## Usage

After installation, simply stick to your normal git workflow.
```bash
# Working in the main repo
git add .
git commit -m "feat: Add button component"
# → post-commit hook automatically commits .claude/ too

git push origin main
# → pre-push hook automatically pushes .claude/ too

git pull
# → post-merge hook automatically pulls .claude/ too

git checkout -b feature/payment
# → post-checkout hook switches .claude/ to the same branch

git fetch origin
# → shell wrapper fetches .claude/ too

git stash
# → shell wrapper stashes .claude/ too

git worktree add ../payment-worktree feature/payment
# → shell wrapper automatically initializes .claude/ in the new worktree
```

### Initial Connection to Private Repo

Run this once after installation.
```bash
# If remote wasn't set during installation
git -C .claude remote add origin git@github.com:you/private-claude.git

# Initial push
git -C .claude push -u origin main
```

### Manual Branch Synchronization

Use this when hooks fall out of sync or when matching a new environment.
```bash
# Match the current main repo branch
git -C .claude checkout main

# Or simply re-run the install script
curl -fsSL .../install.sh | bash
```

---

## Setting up a New Environment / Joining a Team
```bash
# 1. Clone main repo
git clone git@github.com:team/main-repo.git
cd main-repo

# 2. Install dotclaude-sync
curl -fsSL .../install.sh | PRIVATE_REMOTE=git@github.com:you/private-claude.git bash

# 3. Restore existing .claude/ from private repo
git -C .claude pull origin main

# 4. Apply shell wrapper
source ~/.zshrc
```

---

## .claude/rules/ Structure Design Examples & Guidelines

Using path glob frontmatter prevents unnecessary context loading.
```markdown
---
paths:
  - "packages/frontend/**"
---
```

Files authored without globs are always loaded at the start of a session. Suitable for global project rules.

Recommended Structure:
```
.claude/
├── CLAUDE.md                         ← Global project rules (always loaded)
└── rules/
    ├── conventions.md                ← Global code conventions (always loaded)
    └── packages/
        ├── frontend/
        │   ├── index.md              ← General frontend rules
        │   ├── components/
        │   │   └── *.md              ← Spec per component
        │   └── hooks/
        │       └── *.md
        └── backend/
            ├── index.md
            └── api/
                └── *.md
```

---

## Caveats

- On pull conflicts, the local (ours) strategy is prioritized.
- If remote origin is not configured, push/pull will be quietly skipped (no errors).
- Existing git hooks are replaced after being backed up as `.bak`.
- Worktrees are configured independently by locally cloning the main `.claude/`.

---

## License

MIT
