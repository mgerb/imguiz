{
  description = "imguiz";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [];
        };
        zigpkgs = zig.packages.${system};
      in {
        packages = {
          zls-custom = pkgs.stdenv.mkDerivation {
            pname = "zls";
            version = "0.17.0-dev.44+8da87d4f";
            src = pkgs.fetchurl {
              url = "https://builds.zigtools.org/zls-x86_64-linux-0.17.0-dev.44+8da87d4f.tar.xz";
              sha256 = "sha256-nqIj+ohCRnFVWRG+ul1okZGuCApOgn71x2yPZOOf8pY=";
            };
            sourceRoot = ".";
            installPhase = ''
              mkdir -p $out/bin
              mv zls $out/bin/
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            python312
            python312Packages.ply
            zigpkgs.master
            self.packages.${system}.zls-custom
            bash
          ];
        };
      }
    );
}
