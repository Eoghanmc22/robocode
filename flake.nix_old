# Run `nix run github:cargo2nix/cargo2nix` to update Cargo.nix
# https://github.com/bevyengine/bevy/blob/v0.14.2/docs/linux_dependencies.md#nix
# TODO: Export both nix packages and apps?
# TODO: look into `workspaceShell` function, created by `makePackagSet`
# TODO: Use naersk or crane if crate2nix doesnt work either
{
  description = "A Rusty ROV Control Software Stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crate2nix.url = "github:nix-community/crate2nix";
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      rust-overlay,
      crate2nix,
      ...
    }:
      flake-parts.lib.mkFlake { inherit inputs; } {
        systems = nixpkgs.lib.systems.flakeExposed;
        perSystem = {self', pkgs, system, ...}:
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ rust-overlay.overlays.default ];
            };

            rustToolchain = (pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml).override {
              extensions = [ "rust-src" ];
              targets = [ "aarch64-unknown-linux-gnu" "armv7-unknown-linux-gnueabihf" ];
            };

            buildRustCrateForPkgs =
              crate:
              pkgs.buildRustCrate.override {
                rustc = pkgs.rust-bin.stable.latest.default;
                cargo = pkgs.rust-bin.stable.latest.default;
                defaultCrateOverrides = pkgs.defaultCrateOverrides // {
                  alsa-sys = attrs: {
                    buildInputs = [ pkgs.alsa-lib ];
                  };
                  opencv = attrs: {
                    buildInputs = [
                      pkgs.opencv
                      pkgs.clang
                      pkgs.pkg-config
                      pkgs.libclang.lib
                    ];
                  };
                };
              };

            generatedCargoNix = crate2nix.tools.${system}.generatedCargoNix {
              name = "rustnix";
              src = ./.;
            };


            runtimeDeps = with pkgs;
              (lib.optionals pkgs.stdenv.isLinux [
                udev
                alsa-lib
                vulkan-loader
                xorg.libX11
                xorg.libXcursor
                xorg.libXi
                xorg.libXrandr # To use the x11 feature
                libxkbcommon
                wayland # To use the wayland feature
              ])
              ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
                # https://discourse.nixos.org/t/the-darwin-sdks-have-been-updated/55295/1
                apple-sdk_15
              ])
              ++ [
                # Video streaming deps
                gst_all_1.gstreamer
                gst_all_1.gst-plugins-base
                gst_all_1.gst-plugins-good
                gst_all_1.gst-plugins-bad
                gst_all_1.gst-plugins-ugly
                gst_all_1.gst-libav
                ffmpeg

                # opencv crate
                libclang.lib
                opencv
                stdenv.cc.cc
              ];

            cargoNix = import generatedCargoNix {
              inherit pkgs buildRustCrateForPkgs;
            };
          in {
            packages = rec {
              surface = cargoNix.surface.build;
              default = surface;
            };
            devShells.default = pkgs.mkShell rec {
              buildInputs = with pkgs; [
                rustPlatform.bindgenHook
                pkg-config
              ] ++ runtimeDeps ++ [
                rustToolchain
                # rust-analyzer-nightly
              ];
              LD_LIBRARY_PATH = nixpkgs.lib.makeLibraryPath buildInputs;
            };
          };
      };

    # let
    #   systems = [
    #     "x86_64-linux"
    #     "aarch64-linux"
    #     "aarch64-darwin"
    #   ];
    #   # Helper function to generate a set of attributes for each system
    #   forAllSystems = func: (nixpkgs.lib.genAttrs systems func);
    # in
    # {
    #   devShells = forAllSystems (
    #     system:
    #     let
    #       pkgs = import nixpkgs {
    #         inherit system;
    #         overlays = [ rust-overlay.overlays.default ];
    #       };
    #       lib = pkgs.lib;
    #     in
    #     {
    #       default = pkgs.mkShell rec {
    #         nativeBuildInputs = with pkgs; [
    #           rustPlatform.bindgenHook
    #           pkg-config
    #           # lld is much faster at linking than the default Rust linker
    #           lld
    #         ];
    #         buildInputs =
    #           with pkgs;
    #           [
    #             # rust toolchain
    #             ((rust-bin.fromRustupToolchainFile ./rust-toolchain.toml).override {
    #               extensions = [ "rust-src" ];
    #               targets = [ "aarch64-unknown-linux-gnu" "armv7-unknown-linux-gnueabihf" ];
    #             })
    #           ]
    #           # https://github.com/bevyengine/bevy/blob/v0.14.2/docs/linux_dependencies.md#nix
    #           ++ (lib.optionals pkgs.stdenv.isLinux [
    #             udev
    #             alsa-lib
    #             vulkan-loader
    #             xorg.libX11
    #             xorg.libXcursor
    #             xorg.libXi
    #             xorg.libXrandr # To use the x11 feature
    #             libxkbcommon
    #             wayland # To use the wayland feature
    #           ])
    #           ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
    #             # https://discourse.nixos.org/t/the-darwin-sdks-have-been-updated/55295/1
    #             apple-sdk_15
    #           ])
    #           ++ [
    #             # Video streaming deps
    #             gst_all_1.gstreamer
    #             gst_all_1.gst-plugins-base
    #             gst_all_1.gst-plugins-good
    #             gst_all_1.gst-plugins-bad
    #             gst_all_1.gst-plugins-ugly
    #             gst_all_1.gst-libav
    #             ffmpeg
    #
    #             # opencv crate
    #             libclang.lib
    #             opencv
    #             stdenv.cc.cc
    #           ];
    #         LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
    #       };
    #     }
    #   );
    # };
}

