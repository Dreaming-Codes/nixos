#!/usr/bin/env bash

MODEL="github-copilot/gemini-3-flash-preview"
COMMIT_ADDITIONAL_INFO="$1"

if [ -n "$(git status --porcelain)" ]; then
  bunx opencode-ai@latest run "Create a commit message similar to the existing one in the repo and commit all changes. $COMMIT_ADDITIONAL_INFO" -m "$MODEL"
else
  echo "No changes to commit"
fi
