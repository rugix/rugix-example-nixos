{ pkgs }:

# Exercise the actual initrd generator with synthetic EFI variable contents.
pkgs.runCommand "boot-store-generator-test" { nativeBuildInputs = [ pkgs.glibc.bin ]; } ''
  substitute ${../system-configuration/mount-nix-store.sh} generator.sh \
    --replace-fail /sys/firmware/efi/efivars/LoaderEntrySelected-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f "$PWD/entry"

  mkdir units
  expect_failure() {
    if sh generator.sh "$PWD/units" 2>error; then
      echo "Generator accepted a missing or unsupported boot entry" >&2
      exit 1
    fi
    grep -q "Cannot select Nix store:" error
    test ! -e units/sysroot-nix-store.mount
  }

  expect_failure
  printf '\007\000\000\000' > entry
  expect_failure
  printf 'unexpected.efi' >> entry
  expect_failure

  for group in a b; do
    printf '\007\000\000\000' > entry
    printf '%s' "nixos-$group.efi" | iconv -f UTF-8 -t UTF-16LE >> entry
    printf '\000\000' >> entry
    sh generator.sh "$PWD/units"
    grep -qx "What=/dev/disk/by-partlabel/nix-store-$group" units/sysroot-nix-store.mount
    test -e units/initrd-fs.target.requires/sysroot-nix-store.mount
    rm -r units
    mkdir units
  done

  touch "$out"
''
