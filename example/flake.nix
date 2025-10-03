{
  description = "imguiz example";

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
            version = "0.15.1";
            src = pkgs.fetchurl {
              url = "https://builds.zigtools.org/zls-x86_64-linux-0.15.1.tar.xz";
              sha256 = "sha256-O7OPUiyyMhPowHWsaxcCc/5JtCdLjBKwNMxJZAdAAGc=";
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
            zigpkgs."0.15.2"
            self.packages.${system}.zls-custom

            libxkbcommon
            wayland
            vulkan-loader
            vulkan-validation-layers
          ];

          VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
        };
      }
    );
}
