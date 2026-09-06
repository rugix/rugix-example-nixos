# Python Web Server App

This directory is a standalone flake for a Rugix Docker Compose app. Copy it
into another repository to start a container-based app; it has no dependency
on the surrounding NixOS appliance configuration.

Nix builds the Python image with `dockerTools`. The upstream Rugix helper
`lib.mkComposeBundle` packages the image, Compose configuration, compatibility
metadata, and app metadata. Image bundling and content-based pinning remain
enabled. Building the bundle needs no container daemon, and installing it needs
no container registry.

## Build the App

```console
nix build .
nix build .#v2
nix build .#image
```

The default is app version 1.0.0; `v2` builds version 2.0.0, and `image` builds
only the version 1 container archive. Bundles contain `python-web-server.rugixb`
and `python-web-server.rugixb-hash`. For example:

```console
rugix-ctrl apps install --bundle-hash "$(cat result/python-web-server.rugixb-hash)" result/python-web-server.rugixb
```

Outputs are available for x86-64 Linux, AArch64 Linux, and Apple Silicon macOS.
macOS builds target AArch64 Linux and require a compatible Linux builder for
image construction. Both app versions use the same source; image metadata and
the status page identify their versions.

## Customize the App

`default.nix` defines the Python image, Compose service, and metadata. Change
those definitions for your workload. Keep packaging in the upstream helper:

```nix
mkComposeBundle {
  name = "my-app";
  version = "1.0.0";
  compose.services.web = {
    image = "my-app:1.0.0";
    ports = [ "127.0.0.1:8080:8080" ];
  };
  images.web = image;
}
```

## Packaging Interface

The helper takes an image archive for each service, writes the build-only
`x-rugix.image` source configuration, and invokes Bundler with Skopeo. The
packaged Compose file contains Rugix-owned content tags and `pull_policy: never`.
Its `images/` directory contains the image archives and provenance metadata.

The flake also exports `lib.mkApp { buildPkgs, targetPkgs, version }` for consumers
such as the NixOS appliance example. This lets the appliance choose a target
platform and app version while sharing the app's own build definition.

## Runtime Behavior

Rugix provides a persistent directory through `RUGIX_APP_DATA_DIR`. The container
records its start count there before dropping to UID and GID 65532. Its root
filesystem is read-only, and the web server is exposed on the appliance's
loopback interface at port 8080.
