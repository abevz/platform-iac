#!/bin/bash

# Colors for output
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Audit references to 'config/' directory ===${NC}"
echo "Searching for files that will break when renaming 'config' -> 'ansible'..."
echo ""

# 1. Search for direct 'config/' occurrences in code and scripts
# Excludes: .git, .bare (worktrees), this script and README (text doesn't break build)
grep -rnI "config/" . \
  --exclude-dir={.git,.bare,.idea,.vscode} \
  --exclude="audit_config_refs.sh" \
  --exclude="README.md" \
  --exclude="*.log" |
  grep --color=always "config/"

echo ""
echo -e "${BLUE}=== Checking ansible.cfg ===${NC}"

# 2. Check paths inside ansible.cfg (roles_path)
# If roles_path is relative, it may break when moving the config itself
if [ -f config/ansible.cfg ]; then
  echo "Found config/ansible.cfg. Checking roles_path:"
  grep -H "roles_path" config/ansible.cfg
else
  echo -e "${RED}File config/ansible.cfg not found!${NC}"
fi

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "1. CI/CD: Check .github/workflows or .gitlab-ci.yml (if any)"
echo "2. Wrappers: Pay attention to scripts in tools/"
echo "3. Hooks: Check .pre-commit-config.yaml"
