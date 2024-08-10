{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell { packages = [ pkgs.nil pkgs.nixd pkgs.nixfmt ]; }
