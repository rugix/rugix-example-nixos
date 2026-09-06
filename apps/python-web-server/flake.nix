{
  description = "Self-contained Python container app for Rugix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    rugix.url = "github:rugix/rugix/e9c3a2677d9389c71209e792f7c6777a243275ff";
    rugix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      rugix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      lib.mkApp =
        {
          buildPkgs,
          targetPkgs,
          version ? "1.0.0",
        }:
        import ./default.nix {
          inherit buildPkgs targetPkgs version;
          mkComposeBundle = rugix.lib.mkComposeBundle { pkgs = buildPkgs; };
        };

      packages = forEachSystem (
        system:
        let
          buildPkgs = nixpkgs.legacyPackages.${system};
          targetSystem = builtins.replaceStrings [ "darwin" ] [ "linux" ] system;
          targetPkgs = nixpkgs.legacyPackages.${targetSystem};
          app = version: self.lib.mkApp { inherit buildPkgs targetPkgs version; };
        in
        {
          default = self.packages.${system}.v1;
          v1 = app "1.0.0";
          v2 = app "2.0.0";
          image = self.packages.${system}.v1.images.web;
        }
      );

      checks = forEachSystem (system: {
        inherit (self.packages.${system}) v1 v2;
      });
    };
}
