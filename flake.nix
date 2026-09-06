{
  description = "Complete NixOS appliance example with Rugix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    nexigon = {
      # GitHub's source-archive endpoint does not expose this repository,
      # while its public Git repository does.
      url = "git+https://github.com/nexigon/nexigon.git?rev=4a838dd26b6a8c6dab2598c1bedc995f18381ae4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rugix = {
      url = "github:rugix/rugix/e9c3a2677d9389c71209e792f7c6777a243275ff";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    python-web-app = {
      url = "path:./apps/python-web-server";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rugix.follows = "rugix";
    };
    rugix-admin = {
      url = "github:rugix/rugix-admin/1812c991153563cde8194c705ad75a013b02f55a";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rugix.follows = "rugix";
    };

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSystem = lib.genAttrs systems;

      toLinux = builtins.replaceStrings [ "darwin" ] [ "linux" ];
      extendConfiguration = configuration: module: configuration.extendModules { modules = [ module ]; };
      image = configuration: configuration.config.system.build.image;
      rugixBundle = configuration: configuration.config.system.build.rugix-bundle;
      treefmtEval =
        pkgs:
        inputs.treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            deadnix.enable = true;
            nixfmt.enable = true;
            prettier.enable = true;
            shfmt.enable = true;
            statix.enable = true;
          };
        };
    in
    {
      nixosConfigurations.appliance = inputs.nixpkgs.lib.nixosSystem {
        modules = [
          inputs.rugix.nixosModules.rugix
          inputs.rugix-admin.nixosModules.rugix-admin
          inputs.nexigon.nixosModules.nexigon-agent
          ./system-configuration/configuration.nix
          ({ pkgs, ... }: {
            nixpkgs.overlays = [
              inputs.rugix.overlays.default
              inputs.rugix-admin.overlays.default
              inputs.nexigon.overlays.default
            ];
            _module.args.mkRugixBundle = inputs.rugix.lib.mkBundle { pkgs = pkgs.buildPackages; };
          })
        ];
      };

      formatter = forEachSystem (
        system: (treefmtEval inputs.nixpkgs.legacyPackages.${system}).config.build.wrapper
      );

      packages = forEachSystem (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          linuxSystem = toLinux system;
          rugixBundler = inputs.rugix.packages.${system}.rugix-bundler;

          makeArtifacts =
            targetSystem: extraModules:
            let
              baseImage = inputs.self.nixosConfigurations.appliance.extendModules {
                modules = [
                  {
                    nixpkgs = {
                      buildPlatform = lib.mkDefault linuxSystem;
                      hostPlatform = targetSystem;
                    };
                  }
                ]
                ++ extraModules;
              };
              pythonWebApp =
                version:
                inputs.python-web-app.lib.mkApp {
                  buildPkgs = pkgs;
                  targetPkgs = baseImage.pkgs;
                  inherit version;
                };
              pythonWebAppV1 = pythonWebApp "1.0.0";
              pythonWebAppV2 = pythonWebApp "2.0.0";
              imageV1 = extendConfiguration baseImage {
                system.image.version = "1";
              };
              imageV2 = extendConfiguration baseImage {
                system.image.version = "2";
              };
              imageV3 = extendConfiguration baseImage {
                system.image.version = "3";
              };
              updateV2 = rugixBundle imageV2;
              updateV3 = rugixBundle imageV3;
              updateV3Delta =
                pkgs.runCommand "rugix-delta-v2-v3-${targetSystem}"
                  {
                    nativeBuildInputs = [ rugixBundler ];
                  }
                  ''
                    mkdir -p "$out"
                    rugix-bundler delta \
                      ${updateV2}/update.rugixb \
                      ${updateV3}/update.rugixb \
                      "$out/update.rugixb"
                  '';
            in
            {
              inherit
                imageV1
                pythonWebAppV1
                pythonWebAppV2
                updateV2
                updateV3
                updateV3Delta
                ;
            };

          nativeArtifacts = makeArtifacts linuxSystem [ ];
          x86Artifacts = makeArtifacts "x86_64-linux" [ ];
          aarch64Artifacts = makeArtifacts "aarch64-linux" [ ];
          testArtifacts = makeArtifacts linuxSystem [ ./system-configuration/test-extras.nix ];
        in
        {
          python-web-app-v1 = nativeArtifacts.pythonWebAppV1;
          python-web-app-v1-x86_64 = x86Artifacts.pythonWebAppV1;
          python-web-app-v1-aarch64 = aarch64Artifacts.pythonWebAppV1;

          python-web-app-v2 = nativeArtifacts.pythonWebAppV2;
          python-web-app-v2-x86_64 = x86Artifacts.pythonWebAppV2;
          python-web-app-v2-aarch64 = aarch64Artifacts.pythonWebAppV2;

          image-v1 = image nativeArtifacts.imageV1;
          image-v1-x86_64 = image x86Artifacts.imageV1;
          image-v1-aarch64 = image aarch64Artifacts.imageV1;

          update-v2 = nativeArtifacts.updateV2;
          update-v2-x86_64 = x86Artifacts.updateV2;
          update-v2-aarch64 = aarch64Artifacts.updateV2;

          update-v3 = nativeArtifacts.updateV3;
          update-v3-x86_64 = x86Artifacts.updateV3;
          update-v3-aarch64 = aarch64Artifacts.updateV3;

          update-v3-delta = nativeArtifacts.updateV3Delta;
          update-v3-delta-x86_64 = x86Artifacts.updateV3Delta;
          update-v3-delta-aarch64 = aarch64Artifacts.updateV3Delta;

          image-test = image testArtifacts.imageV1;
          python-web-app-v1-test = testArtifacts.pythonWebAppV1;
          python-web-app-v2-test = testArtifacts.pythonWebAppV2;
          update-v2-test = testArtifacts.updateV2;
          update-v3-delta-test = testArtifacts.updateV3Delta;
        }
      );

      checks = forEachSystem (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          packages = inputs.self.packages.${system};
        in
        {
          formatting = (treefmtEval pkgs).config.build.check inputs.self;
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          boot-store-generator = import ./tests/boot-store-generator.nix { inherit pkgs; };
          inherit (packages) python-web-app-v1;
          inherit (packages) python-web-app-v2;
          update-test = pkgs.testers.runNixOSTest (
            import ./tests/update.nix {
              app-v1-bundle = packages.python-web-app-v1-test;
              app-v2-bundle = packages.python-web-app-v2-test;
              inherit (packages) image-test;
              v2-bundle = packages.update-v2-test;
              v3-delta-bundle = packages.update-v3-delta-test;
            }
          );
        }
      );

      apps = forEachSystem (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          demo = import ./tests/demo.nix {
            inherit pkgs;
            driver = inputs.self.checks.${system}.update-test.driverInteractive;
          };
        in
        lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          inherit demo;
          default = demo;
        }
      );

    };
}
