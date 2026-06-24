#!/usr/bin/env bash
set -euo pipefail

# Sanitize tracked files for public GitHub publishing.
# Replaces real IPs, domains, and usernames with safe placeholders.
#
# Usage:
#   tools/sanitize-for-github.sh              # sanitize staged files only
#   tools/sanitize-for-github.sh --all        # sanitize all tracked files
#   tools/sanitize-for-github.sh --dry-run    # show what would change (no writes)
#   tools/sanitize-for-github.sh --check      # exit 1 if any real values found
#   tools/sanitize-for-github.sh --strip-git   # rewrite branch history to remove Co-Authored-By trailers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=false
CHECK_ONLY=false
ALL_FILES=false
STRIP_GIT=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --check)      CHECK_ONLY=true ;;
    --all)        ALL_FILES=true ;;
    --strip-git)  STRIP_GIT=true ;;
    -h|--help)
      echo "Usage: $0 [--all] [--dry-run] [--check] [--strip-git]"
      echo "  --all        Process all tracked files (default: staged only)"
      echo "  --dry-run    Show replacements without writing"
      echo "  --check      Exit 1 if any private values found"
      echo "  --strip-git  Rewrite current branch to remove Co-Authored-By trailers"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

cd "$REPO_ROOT"

# --strip-git: rewrite branch history to remove AI Co-Authored-By trailers
if $STRIP_GIT; then
  BEFORE=$(git log --all --format='%b' | grep -ci 'co-authored-by' || true)
  if [ "$BEFORE" -eq 0 ]; then
    echo "No Co-Authored-By trailers found in history."
    exit 0
  fi
  echo "Found $BEFORE Co-Authored-By trailer(s). Rewriting current branch..."
  git filter-branch -f --msg-filter '
    sed "/^Co-[Aa]uthored-[Bb]y:.*$/d"
  ' -- --all
  AFTER=$(git log --all --format='%b' | grep -ci 'co-authored-by' || true)
  echo "Done. Trailers before: $BEFORE, after: $AFTER"
  echo "Run 'git push origin github-public --force' to update remote."
  exit 0
fi

if $ALL_FILES; then
  files=$(git ls-files)
else
  files=$(git diff --cached --name-only --diff-filter=ACMR)
fi

if [ -z "$files" ]; then
  echo "No files to process."
  exit 0
fi

# Replacement rules: pattern → replacement
declare -A RULES=(
  ["gitlab\.bevz\.net"]="gitlab.example.com"
  ["s3\.minio\.bevz\.net"]="s3.minio.example.com"
  ["minio\.bevz\.net"]="minio.example.com"
  ["bevz\.net"]="example.com"
  ["bevz\.dev"]="example.com"
  ["10\.10\.10\."]="192.0.2."
)

FOUND=0
REPLACED=0

for file in $files; do
  [ -f "$file" ] || continue
  # skip binary files
  file -b --mime "$file" | grep -q 'text/' || continue

  for pattern in "${!RULES[@]}"; do
    replacement="${RULES[$pattern]}"
    matches=$(grep -c "$pattern" "$file" 2>/dev/null || true)
    if [ "$matches" -gt 0 ]; then
      FOUND=$((FOUND + matches))
      if $CHECK_ONLY; then
        echo "FOUND: $file ($matches matches for $pattern)"
      elif $DRY_RUN; then
        echo "WOULD REPLACE in $file: $pattern → $replacement ($matches)"
      else
        sed -i "s/$pattern/$replacement/g" "$file"
        REPLACED=$((REPLACED + matches))
        echo "REPLACED in $file: $pattern → $replacement ($matches)"
      fi
    fi
  done
done

if $CHECK_ONLY; then
  if [ "$FOUND" -gt 0 ]; then
    echo ""
    echo "FAIL: $FOUND private values found. Run 'tools/sanitize-for-github.sh' to fix."
    exit 1
  else
    echo "OK: no private values found."
    exit 0
  fi
fi

if $DRY_RUN; then
  echo ""
  echo "Dry run complete. $FOUND replacements would be made."
else
  echo ""
  echo "Done. $REPLACED replacements made."
fi
