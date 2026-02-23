#!/usr/bin/env bash

PATH_TO_WORKTREES=".rsworktree"
MODEL="github-copilot/gemini-3-flash-preview"
WT_NAME="$1"
WT_PATH="$PATH_TO_WORKTREES/$WT_NAME"

if [ -z "$WT_NAME" ]; then
  echo "Usage $0 <worktree_name>"
  exit 1;
fi


if [ ! -d "$WT_PATH" ]; then
  echo "Error: Worktree does not exist at $WT_PATH"
  exit 2;
fi

if [ -n "$(git -C "$WT_PATH" status --porcelain)" ]; then
  echo "Uncommited changes detected in $WT_PATH. Generating commit..."
  (
    cd $WT_PATH
    git add .
    vibe-commit
  )
fi

opencode run "Merge the branch $WT_NAME into the current branch, resolve any potential conflicts (avoid commiting local changes, stash them and then merge them back if needed), and then delete the worktree using \`rsworktree rm $WT_NAME\`." -m "$MODEL"
