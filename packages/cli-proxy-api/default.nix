# CLIProxyAPI with a complete Grok Build model list: Claude rows use the
# messages backend, rows carry output limits and backend search, and image or
# video generators stay out of the picker.
{
  inputs,
  pkgs,
}:
inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.cli-proxy-api.overrideAttrs (old: {
  patches = (old.patches or []) ++ [./grok-models.patch];
})
