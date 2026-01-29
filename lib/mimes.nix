{
  textMimes = [
    "text/plain"
    "text/markdown"
    "text/html"
    "text/css"
    "text/javascript"
    "text/x-cmake"
    "text/x-c++src"
    "text/x-csrc"
    "text/x-chdr"
    "text/x-c++hdr"
    "text/x-python"
    "text/x-shellscript"
    "text/x-makefile"
    "text/x-lua"
    "text/x-java"
    "text/x-go"
    "text/x-rust"
    "text/x-dockerfile"
    "text/x-yaml"
    "text/x-toml"
    "text/x-ini"
    "text/x-config"
    "text/x-log"
    "application/json"
    "application/x-shellscript"
    "application/javascript"
    "application/xml"
    "application/yaml"
    "application/toml"
    "application/x-yaml"
  ];

  # Generates shell commands to set the default mime type for a list of mimes
  bindMimes = app: mimes:
    builtins.concatStringsSep "\n" (
      builtins.map (mime: "/run/current-system/sw/bin/xdg-mime default \"${app}\" \"${mime}\"") mimes
    );
}
