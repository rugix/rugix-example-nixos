{
  config,
  mkRugixBundle,
  ...
}:

let
  inherit (config.system) build;
  inherit (config.system.image) version id;
  block-encoding = {
    chunker = "casync-64";
    deduplicate = true;
  };
in
{
  config.system.build.rugix-bundle = mkRugixBundle {
    name = "update";
    inherit version;
    manifest = {
      update-type = "full";
      payloads = [
        {
          filename = "system.img";
          delivery = {
            type = "slot";
            slot = "system";
          };
          inherit block-encoding;
        }
        {
          filename = "boot.efi";
          delivery = {
            type = "slot";
            slot = "boot";
          };
          inherit block-encoding;
        }
      ];
    };
    payloads = {
      "system.img" = "${build.image}/${id}_${version}.nix-store.raw";
      "boot.efi" = "${build.uki}/${config.system.boot.loader.ukiFile}";
    };
  };
}
