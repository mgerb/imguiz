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
            version = "0.15.0-dev.348+b00ed99c";
            src = pkgs.fetchurl {
              url = "https://builds.zigtools.org/zls-linux-x86_64-0.15.0-dev.348+b00ed99c.tar.xz";
              sha256 = "sha256-7gLM9L8KRq8GQ/y6HJQ9+ONbR88duGxHMqEc36Ac4no=";
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
            python312Full
            python312Packages.ply
            zigpkgs.master
            self.packages.${system}.zls-custom
            bash
          ];
        };
      }
    );
}
