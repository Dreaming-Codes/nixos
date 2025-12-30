#!/usr/bin/env bash

MODEL="github-copilot/gemini-3-flash-preview"
COMMIT_ADDITIONAL_INFO="$*"
CONTEXT=$(git log --oneline -n 10)

ADDITIONAL_DEV_CONTEXT=""

if [ -n "$COMMIT_ADDITIONAL_INFO" ]; then
  ADDITIONAL_DEV_CONTEXT="Developer notes for the commit message: $COMMIT_ADDITIONAL_INFO"
fi

if [ -n "$(git status --porcelain)" ]; then
  STAGED_FILES=$(git diff --cached --name-only)
  bunx opencode-ai@latest run "Create a commit message for the following modified files:
  $STAGED_FILES
  
  Ensure the style of the commit message is similar to the existing one in the repo history:
  $CONTEXT

  $ADDITIONAL_DEV_CONTEXT

  Commit all staged changes with that message." -m "$MODEL"
else
  echo "No changes to commit"
fi
