{
  stdenv,
  scdoc,
  lib,
  fetchzip,
  meson,
  ninja,
  docbook_xsl,
  gtk-doc,
  pkg-config,
  xz,
  zstd,
  zlib,
  openssl,
  withDevdoc ? stdenv.hostPlatform == stdenv.buildPlatform,
  gitUpdater,
}:

let
  # systems = [
  #   "/run/booted-system/kernel-modules"
  #   "/run/current-system/kernel-modules"
  #   ""
  # ];
  # modulesDirs = lib.concatMapStringsSep ":" (x: "${x}/lib/modules") systems;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "kmod";
  version = "34.2";

  src = fetchzip {
    url = "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git/snapshot/kmod-${finalAttrs.version}.tar.gz";
    hash = "sha256-+fSM9ver+Yg9YbKuqiheKbqkLaZBPRuu0dey6gXQHyE=";
  };

  outputs = [
    "out"
    "dev"
    "lib"
  ]
  ++ lib.optional withDevdoc "devdoc";

  strictDeps = true;
  nativeBuildInputs = [
    meson
    ninja
    scdoc
    pkg-config
  ]
  ++ lib.optionals withDevdoc [
    docbook_xsl
    gtk-doc
  ];

  buildInputs = [
    xz
    zstd
    zlib
    openssl
  ];

  mesonFlags = [
    (lib.mesonOption "distconfdir" "${placeholder "out"}/etc")
    (lib.mesonOption "sysconfdir" "${placeholder "out"}/etc")
    (lib.mesonOption "rootdir" "/run/booted-system/kernel-modules")
    (lib.mesonBool "docs" withDevdoc)
  ];

  patches = [ ./test.patch ];
  postPatch = ''
    patchShebangs ./scripts
  '';

  passthru.updateScript = gitUpdater {
    # No nicer place to find latest release.
    url = "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git";
    rev-prefix = "v";
  };

  meta = {
    description = "Tools for loading and managing Linux kernel modules";
    longDescription = ''
      kmod is a set of tools to handle common tasks with Linux kernel modules
      like insert, remove, list, check properties, resolve dependencies and
      aliases. These tools are designed on top of libkmod, a library that is
      shipped with kmod.
    '';
    homepage = "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git/";
    downloadPage = "https://www.kernel.org/pub/linux/utils/kernel/kmod/";
    changelog = "https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git/plain/NEWS?h=v${finalAttrs.version}";
    license = with lib.licenses; [
      lgpl21Plus
      gpl2Plus
    ]; # GPLv2+ for tools
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ artturin ];
  };
})
