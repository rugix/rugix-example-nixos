{
  lib,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/perlless.nix")
    ./image.nix
    ./update.nix
    ./update-package.nix
  ];

  # Keep this fixed when upgrading NixOS on devices with existing state.
  system.stateVersion = "26.05";
  networking.hostName = "appliance";

  environment.systemPackages = [ pkgs.curl ];

  system.disableInstallerTools = true;
  programs.nano.enable = false;
  programs.fuse.enable = false;
  security.sudo.enable = false;
  # The example intentionally ships without administrator credentials. This
  # acknowledges the resulting NixOS lockout assertion; it does not unlock the
  # root account or assign an empty password.
  users.allowNoPasswordLogin = true;

  system.image.version = lib.mkDefault "1";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
