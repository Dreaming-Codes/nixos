{pkgs ? import <nixpkgs> {}}: let
  system-current = pkgs.writeShellScriptBin "system-current" ''
    CACHE_FILE="/var/lib/nixos-config-hash"

    if [ ! -f "$CACHE_FILE" ]; then
      echo "No previous switch recorded"
      exit 1
    fi

    CURRENT_HASH=$(git ls-files -s | git hash-object --stdin)
    STORED_HASH=$(cat "$CACHE_FILE")

    if [ "$CURRENT_HASH" = "$STORED_HASH" ]; then
      echo "System is up to date"
      exit 0
    else
      echo "System is outdated"
      exit 1
    fi
  '';

  update-system-common = pkgs.writeShellScriptBin "update-system-common" ''
    MODE="$1"

    if [ "$MODE" != "switch" ] && [ "$MODE" != "boot" ]; then
      echo "Usage: update-system-common <switch|boot>"
      exit 1
    fi

    apply_if_needed() {
      if ${system-current}/bin/system-current > /dev/null 2>&1; then
        echo "System is already up to date! Skipping $MODE."
      else
        echo "Configuration changed. Running $MODE..."
        nh os "$MODE" -- --impure --accept-flake-config
      fi
    }

    restore_stash() {
      echo "Restoring stashed changes..."
      if ! git stash pop 2>&1; then
        if git diff --name-only --diff-filter=U | grep -q .; then
          echo "Stash pop caused conflicts!"
          echo "Conflicting files:"
          git diff --name-only --diff-filter=U
          echo ""
          echo "Launching opencode to resolve stash conflicts..."
          opencode run "Please resolve the git stash pop conflicts in this repository. The conflicting files are: $(git diff --name-only --diff-filter=U | tr '\n' ' ')"
          if git diff --name-only --diff-filter=U | grep -q .; then
            echo "Conflicts still exist. Please resolve them manually."
            return 1
          fi
          echo "Stash conflicts resolved!"
          git stash drop
        else
          echo "Stash pop failed for an unknown reason."
          return 1
        fi
      fi
      # Re-stage files that were previously staged
      if [ -n "$STAGED_FILES" ]; then
        echo "Re-staging previously staged files..."
        echo "$STAGED_FILES" | while IFS= read -r file; do
          if [ -n "$file" ] && [ -e "$file" ]; then
            git add "$file"
          fi
        done
      fi
      return 0
    }

    # Check if remote has changes
    echo "Fetching remote..."
    git fetch
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse @{u} 2>/dev/null)

    if [ "$LOCAL" = "$REMOTE" ]; then
      echo "Already up to date with remote."
      apply_if_needed
      exit 0
    fi

    # Check for unstaged/uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "You have uncommitted changes:"
      git status --short
      echo ""
      read -p "Would you like to stash them before pulling? [y/N] " response
      case "$response" in
        [yY][eE][sS]|[yY])
          echo "Stashing changes..."
          STAGED_FILES=$(git diff --cached --name-only)
          git stash push -m "update-system auto-stash"
          STASHED=1
          ;;
        *)
          echo "Please commit or stash your changes and try again."
          exit 1
          ;;
      esac
    fi

    echo "Pulling latest changes..."
    if git pull 2>&1; then
      echo "Pull successful!"
      if [ "$STASHED" = "1" ]; then
        if ! restore_stash; then
          exit 1
        fi
      fi
      apply_if_needed
    else
      if git diff --name-only --diff-filter=U | grep -q .; then
        echo "Merge conflicts detected!"
        echo "Conflicting files:"
        git diff --name-only --diff-filter=U
        echo ""
        read -p "Would you like to invoke opencode to fix the conflicts? [y/N] " response
        case "$response" in
          [yY][eE][sS]|[yY])
            echo "Launching opencode to resolve conflicts..."
            opencode run "Please resolve the git merge conflicts in this repository. The conflicting files are: $(git diff --name-only --diff-filter=U | tr '\n' ' ')"
            if git diff --name-only --diff-filter=U | grep -q .; then
              echo "Conflicts still exist. Please resolve them manually or try again."
              exit 1
            fi
            echo "Conflicts resolved!"
            if [ "$STASHED" = "1" ]; then
              if ! restore_stash; then
                exit 1
              fi
            fi
            apply_if_needed
            ;;
          *)
            echo "Please resolve the conflicts manually and try again."
            exit 1
            ;;
        esac
      else
        echo "Git pull failed for a reason other than merge conflicts."
        exit 1
      fi
    fi
  '';

  update-system = pkgs.writeShellScriptBin "update-system" ''
    ${update-system-common}/bin/update-system-common switch
  '';

  update-system-boot = pkgs.writeShellScriptBin "update-system-boot" ''
    ${update-system-common}/bin/update-system-common boot
  '';
in
  pkgs.mkShell {
    packages = [pkgs.nil pkgs.nixd pkgs.nixfmt system-current update-system update-system-boot];
  }
