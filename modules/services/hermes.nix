{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.dreaming.services.hermes;
  hermes = config.services.hermes-agent;
  # The plugin probes $HOME/.local/bin after PATH. Container mode sets HOME to
  # the persistent agent home, which is mounted inside the container.
  claudeBin = "${hermes.stateDir}/home/.local/bin/claude";
  claudeSubscriptionDirectsdk =
    pkgs.runCommand "claude-subscription-directsdk-experimental" {
      src = pkgs.fetchFromGitHub {
        owner = "NousResearch";
        repo = "hermes-official-plugins";
        rev = "2037962fbc3e1ed82fbe5be4df03e99713b0f98e";
        hash = "sha256-MZ9rEtdR9UdlLrc1ySrLVf2jFVp1e927g/p3D5HBm5c=";
      };
    } ''
      mkdir "$out"
      cp -a "$src/claude-subscription-directsdk/." "$out/"
      test -f "$out/plugin.yaml"
    '';
in {
  imports = [inputs.hermes-agent.nixosModules.default];

  options.dreaming.services.hermes.enable =
    lib.mkEnableOption "Hermes Agent OCI container mode"
    // {
      default = false;
    };

  config = lib.mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      container = {
        enable = true;
        backend = "docker";
        hostUsers = ["dreamingcodes"];
      };
      extraPlugins = [claudeSubscriptionDirectsdk];
      settings.model = {
        provider = "claude-subscription-directsdk-experimental";
        default = "sonnet";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${hermes.stateDir}/home/.local 0750 ${hermes.user} ${hermes.group} - -"
      "d ${dirOf claudeBin} 0750 ${hermes.user} ${hermes.group} - -"
      "L+ ${claudeBin} - - - - ${pkgs.claude-code}/bin/claude"
    ];
  };
}
