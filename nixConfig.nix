# Binary caches consumed by modules/core/nix.nix and flake-modules/devshell.nix.
# NOTE: flake.nix's `nixConfig` attr must be a literal (Nix reads it before
# evaluation and rejects an `import`), so it holds a duplicate of this attrset.
# Keep the two in sync.
{
  substituters = [
    "https://artifact-s3-gateway.int.n7k.io/n7k-nix-cache?priority=10"
    "https://install.determinate.systems?priority=20"
    "https://cache.nixos.org?priority=40"
    "https://nix-community.cachix.org?priority=41"
    "https://attic.xuyh0120.win/lantian?priority=42"
    "https://numtide.cachix.org?priority=43"
    "https://cache.nixos-cuda.org?priority=45"
  ];
  extra-trusted-public-keys = [
    "nix-cache.infra.n7k.io-0:WyML6bRQeGqxs/1iSoQrlMuooDlxG15rgjuo7Elmpf4="
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
  ];
}
