# Run `nix run github:cargo2nix/cargo2nix` to update Cargo.nix
# https://github.com/bevyengine/bevy/blob/v0.14.2/docs/linux_dependencies.md#nix
# TODO: use cargo2nix for builds
# TODO: Export both nix packages and apps?
# TODO: Switch to flake parts instead of our own forAllSystems
{
  description = "A Rusty ROV Control Software Stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cargo2nix = {
      url = "github:cargo2nix/cargo2nix/release-0.12";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    {
      nixpkgs,
      fenix,
      # cargo2nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      # Helper function to generate a set of attributes for each system
      forAllSystems = func: (nixpkgs.lib.genAttrs systems func);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ fenix.overlays.default ];
          };
          lib = pkgs.lib;
        in
        {
          default = pkgs.mkShell rec {
            nativeBuildInputs = with pkgs; [
              rustPlatform.bindgenHook
              pkg-config
              # lld is much faster at linking than the default Rust linker
              lld
            ];
            buildInputs =
              with pkgs;
              [
                # rust toolchain
                (pkgs.fenix.complete.withComponents [
                  "cargo"
                  "clippy"
                  "rust-src"
                  "rustc"
                  "rustfmt"
                ])
                # use rust-analyzer-nightly for better type inference
                # rust-analyzer-nightly
                # cargo-watch
              ]
              # https://github.com/bevyengine/bevy/blob/v0.14.2/docs/linux_dependencies.md#nix
              ++ (lib.optionals pkgs.stdenv.isLinux [
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
            LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
          };
        }
      );
    };
}

