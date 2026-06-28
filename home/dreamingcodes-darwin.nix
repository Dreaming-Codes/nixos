{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./cli.nix
    # The NeuraBook is a work Mac, so the work config is always on here. The
    # Linux work hosts get the same home/work.nix via the `dreaming.work` toggle.
    ./work.nix
  ];

  home.username = "dreamingcodes";
  home.homeDirectory = "/Users/dreamingcodes";

  programs.zed-editor.enable = true;

  programs.rio.enable = true;

  # macOS can't run a native Linux dockerd, so Colima provides a lightweight
  # Linux VM (Apple's Virtualization.framework) that runs the engine. The docker
  # CLI talks to it over the colima socket. On Linux this comes from
  # modules/services/docker.nix (native daemon) instead.
  home.packages = with pkgs; [
    docker # client CLI
    docker-compose
    docker-buildx
    colima # the VM/engine manager
  ];

  # The docker CLI discovers subcommands as plugins in ~/.docker/cli-plugins,
  # so `docker compose` / `docker buildx` resolve to the nix-provided binaries.
  home.file.".docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/libexec/docker/cli-plugins/docker-compose";
  home.file.".docker/cli-plugins/docker-buildx".source = "${pkgs.docker-buildx}/libexec/docker/cli-plugins/docker-buildx";

  # Auto-start Colima on login. `colima start` is idempotent (it no-ops if the
  # VM is already running), and it shells out to lima/ssh/etc., so the agent runs
  # under a shell with the colima package's runtime deps on PATH.
  launchd.agents.colima = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-lc"
        "exec ${pkgs.colima}/bin/colima start --foreground"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/.colima/colima.launchd.log";
      StandardErrorPath = "${config.home.homeDirectory}/.colima/colima.launchd.log";
      EnvironmentVariables = {
        PATH = "${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };
}
