{pkgs ? import <nixpkgs> {}}:
let
  update-system = pkgs.writeShellScriptBin "update-system" ''
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
      return 0
    }

    # Check for unstaged/uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "You have uncommitted changes:"
      git status --short
      echo ""
      read -p "Would you like to stash them before pulling? [y/N] " response
      case "$response" in
        [yY][eE][sS]|[yY])
          echo "Stashing changes..."
          git stash push -m "update-system auto-stash"
          STASHED=1
          ;;
        *)
          echo "Please commit or stash your changes and run 'update-system' again."
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
      echo "Switching system..."
      nh os switch -- --impure --accept-flake-config
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
            echo "Switching system..."
            nh os switch -- --impure --accept-flake-config
            ;;
          *)
            echo "Please resolve the conflicts manually and run 'update-system' again."
            exit 1
            ;;
        esac
      else
        echo "Git pull failed for a reason other than merge conflicts."
        exit 1
      fi
    fi
  '';
in
pkgs.mkShell {
  packages = [pkgs.nil pkgs.nixd pkgs.nixfmt update-system];
}
