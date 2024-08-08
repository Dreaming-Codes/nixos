{ config, pkgs, ... }:
   {
     home-manager.users.dreamingcodes.programs.starship = {
           enable = true;
           settings = {
             "$schema" = "https://starship.rs/config-schema.json";
             username = {
               format = " [╭─$user]($style)@";
               style_user = "bold red";
               style_root = "bold red";
               show_always = true;
             };
             hostname = {
               format = "[$hostname]($style) in ";
               style = "bold dimmed red";
               trim_at = "-";
               ssh_only = false;
               disabled = false;
             };
             directory = {
               style = "purple";
               truncation_length = 0;
               truncate_to_repo = true;
               truncation_symbol = "repo: ";
             };
             git_status = {
               style = "white";
               ahead = "⇡\${count}";
               diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
               behind = "⇣\${count}";
               deleted = "x";
             };
             cmd_duration = {
               min_time = 1;
               format = "took [\$duration](\$style)";
               disabled = false;
             };
             time = {
               format = " 🕙 \$time(\$style)\n";
               time_format = "%T";
               style = "bright-white";
               disabled = true;
             };
             character = {
               success_symbol = " [╰─λ](bold red)";
               error_symbol = " [×](bold red)";
             };
             status = {
               symbol = "🔴";
               format = "[\\[\$symbol\$status_common_meaning\$status_signal_name\$status_maybe_int\\]](\$style)";
               map_symbol = true;
               disabled = false;
             };
             aws = { symbol = " "; };
             conda = { symbol = " "; };
             dart = { symbol = " "; };
             elixir = { symbol = " "; };
             elm = { symbol = " "; };
             git_branch = { symbol = " "; };
             golang = { symbol = " "; };
             nix_shell = { symbol = " "; };
             haskell = { symbol = " "; };
             hg_branch = { symbol = " "; };
             java = { symbol = " "; };
             julia = { symbol = " "; };
             nim = { symbol = " "; };
             nodejs = { symbol = " "; };
             package = { symbol = " "; };
             perl = { symbol = " "; };
             php = { symbol = " "; };
             python = { symbol = " "; };
             ruby = { symbol = " "; };
             rust = { symbol = " "; };
             swift = { symbol = "ﯣ "; };
           };
     };
   }
