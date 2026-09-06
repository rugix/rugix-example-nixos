{ lib, ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    (builtins.readFile ../tests/test-key.pub)
  ];

  # The test appliance reaches its update server through the single-label
  # hostname handed out over DHCP.
  services.resolved.settings.Resolve.ResolveUnicastSingleLabel = true;

  # Test speed-ups do not affect the production image.

  image.repart.partitions = {
    # The real image pads each A/B store partition to 2G for headroom, but
    # the test image is well below 768M. Shrinking the partitions makes the
    # full update bundle smaller than the production artifact while retaining
    # room for the Docker and Python runtime in the immutable Nix store.
    nix-store-a.repartConfig = {
      SizeMinBytes = lib.mkForce "768M";
      SizeMaxBytes = lib.mkForce "768M";
    };
    nix-store-b.repartConfig = {
      SizeMinBytes = lib.mkForce "768M";
      SizeMaxBytes = lib.mkForce "768M";
    };

    # Boot the default/one-shot entry immediately. Once a second UKI exists
    # (after the first update) systemd-boot otherwise sits at its menu for
    # the full 20s timeout on every subsequent boot — ~40s of the test.
    esp.contents."/loader/loader.conf".source = lib.mkForce (
      builtins.toFile "loader.conf" ''
        timeout 0
        default nixos-a.efi
      ''
    );
  };
}
