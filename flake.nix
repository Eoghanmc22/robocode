# See https://crane.dev/examples/quick-start-workspace.html
#  - Look into the cargo-hakari stuff in this example, but i dont thing we need it
# See https://crane.dev/examples/custom-toolchain.html
# crane kinda sucks since we have to rebuild every dep if we change Cargo.toml
{
  description = "Build a cargo workspace";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";

    flake-utils.url = "github:numtide/flake-utils";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      flake-utils,
      advisory-db,
      rust-overlay,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        inherit (pkgs) lib;

        craneLib = (crane.mkLib pkgs).overrideToolchain (
          p:
          (p.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml).override {
              extensions = [ "rust-src" ];
              targets = [ "aarch64-unknown-linux-gnu" "armv7-unknown-linux-gnueabihf" ];
            }
        );
        src = craneLib.cleanCargoSource ./.;

        depsSurface = with pkgs;
          (lib.optionals pkgs.stdenv.isLinux [
            pkg-config
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
            clang
            libclang.lib
            opencv
            stdenv.cc.cc

            openssl.dev
          ];


        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          inherit src;
          strictDeps = true;

          # TODO: nativeBuildInputs should only have build deps, and buildInputs should only have runtime deps
          # TODO: I dont want depsSurface here since this will leak into the build for robot
          nativeBuildInputs = depsSurface;
          buildInputs = depsSurface ++ [
            # Add additional build inputs here
          ]
          ++ lib.optionals pkgs.stdenv.isDarwin [
            # Additional darwin specific inputs can be set here
            pkgs.libiconv
          ];
          # TODO: I think we can get away with just setting LIBCLANG_PATH
          LD_LIBRARY_PATH = lib.makeLibraryPath depsSurface;

          # Additional environment variables can be set directly
          # MY_CUSTOM_VAR = "some value";
        };

        # Build *just* the cargo dependencies (of the entire workspace),
        # so we can reuse all of that work (e.g. via cachix) when running in CI
        # It is *highly* recommended to use something like cargo-hakari to avoid
        # cache misses when building individual top-level-crates
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        individualCrateArgs = commonArgs // {
          inherit (craneLib.crateNameFromCargoToml { inherit src; }) version;
          # NB: we disable tests since we'll run them all via cargo-nextest
          doCheck = false;
        };

        fileSetForCrate =
          crate:
          lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./Cargo.toml
              ./Cargo.lock
              # TODO: Why is this needed?
              (craneLib.fileset.commonCargoSources ./common)
              (craneLib.fileset.commonCargoSources ./motor_math)
              (craneLib.fileset.commonCargoSources ./networking)
              (craneLib.fileset.commonCargoSources ./stable_hashmap)

              # TODO: Binarie crates absolutely should not be here
              (craneLib.fileset.commonCargoSources ./robot)
              (craneLib.fileset.commonCargoSources ./surface)
              (craneLib.fileset.commonCargoSources ./waterlinked)
              # (craneLib.fileset.commonCargoSources crate)
            ];
          };

        # Build the top-level crates of the workspace as individual derivations.
        # This allows consumers to only depend on (and build) only what they need.
        # Though it is possible to build the entire workspace as a single derivation,
        # so this is left up to you on how to organize things
        #
        # Note that the cargo workspace must define `workspace.members` using wildcards,
        # otherwise, omitting a crate (like we do below) will result in errors since
        # cargo won't be able to find the sources for all members.
        surface = craneLib.buildPackage (
          individualCrateArgs
          // {
            pname = "surface";
            # cargoExtraArgs = "-p my-cli";
            src = fileSetForCrate ./surface;
          }
        );
        # my-server = craneLib.buildPackage (
        #   individualCrateArgs
        #   // {
        #     pname = "my-server";
        #     cargoExtraArgs = "-p my-server";
        #     src = fileSetForCrate ./crates/my-server;
        #   }
        # );
      in
      {
        checks = {
          # Build the crates as part of `nix flake check` for convenience
          inherit surface;

          # Run clippy (and deny all warnings) on the workspace source,
          # again, reusing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          workspace-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          workspace-doc = craneLib.cargoDoc (
            commonArgs
            // {
              inherit cargoArtifacts;
              # This can be commented out or tweaked as necessary, e.g. set to
              # `--deny rustdoc::broken-intra-doc-links` to only enforce that lint
              env.RUSTDOCFLAGS = "--deny warnings";
            }
          );

          # Check formatting
          workspace-fmt = craneLib.cargoFmt {
            inherit src;
          };

          workspace-toml-fmt = craneLib.taploFmt {
            src = pkgs.lib.sources.sourceFilesBySuffices src [ ".toml" ];
            # taplo arguments can be further customized below as needed
            # taploExtraArgs = "--config ./taplo.toml";
          };

          # Audit dependencies
          workspace-audit = craneLib.cargoAudit {
            inherit src advisory-db;
          };

          # Audit licenses
          workspace-deny = craneLib.cargoDeny {
            inherit src;
          };

          # Run tests with cargo-nextest
          # Consider setting `doCheck = false` on other crate derivations
          # if you do not want the tests to run twice
          workspace-nextest = craneLib.cargoNextest (
            commonArgs
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
              cargoNextestPartitionsExtraArgs = "--no-tests=pass";
            }
          );
        };

        packages = {
          inherit surface;
        };

        apps = {
          # Building this seems to also build robot and everyting else
          surface = flake-utils.lib.mkApp {
            drv = surface;
          };
        };

        devShells.default = craneLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};

          # Additional dev-shell environment variables can be set directly
          # MY_CUSTOM_DEVELOPMENT_VAR = "something else";

          # Extra inputs can be added here; cargo and rustc are provided by default.
          packages = [
            # TODO: 
          ] ++ depsSurface;
        };
      }
    );
}

