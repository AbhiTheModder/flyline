{
  lib,
  bashInteractive,
  fetchFromGitHub,
  rustPlatform,
  stdenv,
}:

let
  ratatuiSource = fetchFromGitHub {
    owner = "HalFrgrd";
    repo = "ratatui";
    rev = "107a2ca60e0c9f58e9e518a9a8709071719faf29";
    hash = "sha256-68o9FXF2ioEuXyCq+3254ud95mVF3FRKVPOuBFKWeSI=";
  };
in

rustPlatform.buildRustPackage {
  __structuredAttrs = true;

  pname = "flyline";
  version = (lib.importTOML ../Cargo.toml).package.version;

  src = lib.cleanSource ../.;

  # The project uses local ratatui path patches during development. Provide
  # the same sibling checkout in the Nix build sandbox without changing the
  # project's Cargo.toml or Cargo.lock.
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ../Cargo.lock;
    allowBuiltinFetchGit = true;
  };
  cargoHash = null;

  # Reproducible builds on macOS (Linux needs nothing extra). Timestamps come
  # from SOURCE_DATE_EPOCH (set by Nix, honored by build.rs); these flags fix
  # Mach-O leaks:
  #   --remap-path-prefix  strip the randomised build dir from rustc paths
  #   -install_name        pin LC_ID_DYLIB (else it's the absolute build path)
  #   -reproducible        normalize LC_UUID / ad-hoc signature
  # Exporting RUSTFLAGS overrides .cargo/config.toml, so re-add -undefined
  # dynamic_lookup (flyline resolves Bash symbols at load time).
  preConfigure = ''
    mkdir -p ../ratatui
    cp -R ${ratatuiSource}/. ../ratatui/
  '' + lib.optionalString stdenv.hostPlatform.isDarwin ''
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build -C link-arg=-undefined -C link-arg=dynamic_lookup -C link-arg=-Wl,-install_name,@rpath/libflyline.dylib -C link-arg=-Wl,-reproducible''${RUSTFLAGS:+ $RUSTFLAGS}"
  '';

  # The docker_integration_tests need Docker, which the sandbox lacks; skip them.
  checkFlags = [
    "--skip=test_bash_3_2_57"
    "--skip=test_bash_4_4_18"
    "--skip=test_bash_4_4_rc1"
    "--skip=test_bash_5_0"
    "--skip=test_bash_5_3"
  ];

  nativeCheckInputs = [ bashInteractive ];

  postCheck = ''
    library="$(find target -type f -name 'libflyline${stdenv.hostPlatform.extensions.sharedLibrary}' -print -quit)"
    test -n "$library"
    ${bashInteractive}/bin/bash --noprofile --norc -i -c \
      'enable -f "$1" flyline' flyline-nix-check "$library"
  '';

  meta = {
    description = "Bash plugin to replace readline for a modern line editing experience";
    longDescription = ''
      Flyline is a Bash loadable builtin (a dynamic library dlopen()ed by Bash)
      that adds a rich line editor: inline suggestions, fuzzy tab completion,
      configurable keybindings and prompts. Enable it in an interactive shell
      with `enable -f ${placeholder "out"}/lib/libflyline.<ext> flyline`.
    '';
    homepage = "https://github.com/HalFrgrd/flyline";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.unix;
  };
}
