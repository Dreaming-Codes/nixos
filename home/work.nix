{config, ...}: {
  programs.opencode.settings = {
    model = "amazon-bedrock/anthropic.claude-opus-4-8";
    small_model = "amazon-bedrock/anthropic.claude-sonnet-4-6";
  };

  home.file.".config/nixos-local-aws/config".source = ../config/aws/work.config;

  home.sessionVariables = {
    AWS_CONFIG_FILE = "${config.home.homeDirectory}/.config/nixos-local-aws/config";
    AWS_PROFILE = "BedrockAccess";
    AWS_REGION = "us-west-2";
  };
}
