{
  stdenv,
  lib,
  fetchurl,
  replaceVars,
  autoreconfHook,
  pkg-config,
  intltool,
  babl,
  gegl,
  gtk2,
  glib,
  gdk-pixbuf,
  isocodes,
  pango,
  cairo,
  freetype,
  fontconfig,
  lcms,
  libpng,
  libjpeg,
  libjxl,
  poppler,
  poppler_data,
  libtiff,
  libmng,
  librsvg,
  libwmf,
  zlib,
  libzip,
  ghostscript,
  aalib,
  shared-mime-info,
  libexif,
  gettext,
  makeWrapper,
  gtk-doc,
  xorg,
  glib-networking,
  libmypaint,
  gexiv2,
  harfbuzz,
  mypaint-brushes1,
  libwebp,
  libheif,
  libxslt,
  libgudev,
  openexr,
  desktopToDarwinBundle,
  gtk-mac-integration-gtk2,
  withPython ? false,
  python2,
}:

let
  python = python2.withPackages (pp: [ pp.pygtk ]);
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gimp";
  version = "2.10.38";

  outputs = [
    "out"
    "dev"
  ];

  src = fetchurl {
    url = "http://download.gimp.org/pub/gimp/v${lib.versions.majorMinor finalAttrs.version}/gimp-${finalAttrs.version}.tar.bz2";
    sha256 = "sha256-UKhF7sEciDH+hmFweVD1uERuNfMO37ms+Y+FwRM/hW4=";
  };

  patches = [
    # to remove compiler from the runtime closure, reference was retained via
    # gimp --version --verbose output
    (replaceVars ./remove-cc-reference.patch {
      cc_version = stdenv.cc.cc.name;
    })

    # Use absolute paths instead of relying on PATH
    # to make sure plug-ins are loaded by the correct interpreter.
    ./hardcode-plugin-interpreters.patch

    # GIMP queries libheif.pc for builtin encoder/decoder support to determine if AVIF/HEIC files are supported
    # (see https://gitlab.gnome.org/GNOME/gimp/-/blob/a8b1173ca441283971ee48f4778e2ffd1cca7284/configure.ac?page=2#L1846-1852)
    # These variables have been removed since libheif 1.18.0
    # (see https://github.com/strukturag/libheif/commit/cf0d89c6e0809427427583290547a7757428cf5a)
    # This has already been fixed for the upcoming GIMP 3, but the fix has not been backported to 2.x yet
    # (see https://gitlab.gnome.org/GNOME/gimp/-/issues/9080)
    ./force-enable-libheif.patch
  ];

  # error: possibly undefined macro: AM_NLS
  preAutoreconf = ''
    cp ${gettext}/share/gettext/m4/nls.m4 m4macros
  '';

  nativeBuildInputs = [
    autoreconfHook # hardcode-plugin-interpreters.patch changes Makefile.am
    pkg-config
    intltool
    gettext
    makeWrapper
    gtk-doc
    libxslt
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    desktopToDarwinBundle
  ];

  buildInputs = [
    babl
    gegl
    gtk2
    glib
    gdk-pixbuf
    pango
    cairo
    gexiv2
    harfbuzz
    isocodes
    freetype
    fontconfig
    lcms
    libpng
    libjpeg
    libjxl
    poppler
    poppler_data
    libtiff
    openexr
    libmng
    librsvg
    libwmf
    zlib
    libzip
    ghostscript
    aalib
    shared-mime-info
    libwebp
    libheif
    libexif
    xorg.libXpm
    glib-networking
    libmypaint
    mypaint-brushes1
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    gtk-mac-integration-gtk2
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    libgudev
  ]
  ++ lib.optionals withPython [
    python
    # Duplicated here because python.withPackages does not expose the dev output with pkg-config files
    python2.pkgs.pygtk
  ];

  # needed by gimp-2.0.pc
  propagatedBuildInputs = [
    gegl
  ];

  configureFlags = [
    "--without-webkit" # old version is required
    "--disable-check-update"
    "--with-bug-report-url=https://github.com/NixOS/nixpkgs/issues/new"
    "--with-icc-directory=/run/current-system/sw/share/color/icc"
    # fix libdir in pc files (${exec_prefix} needs to be passed verbatim)
    "--libdir=\${exec_prefix}/lib"
  ]
  ++ lib.optionals (!withPython) [
    "--disable-python" # depends on Python2 which was EOLed on 2020-01-01
  ];

  enableParallelBuilding = true;

  doCheck = true;

  env = {
    NIX_CFLAGS_COMPILE = toString (
      [ ]
      ++ lib.optionals stdenv.cc.isGNU [ "-Wno-error=incompatible-pointer-types" ]
      ++ lib.optionals stdenv.hostPlatform.isDarwin [ "-DGDK_OSX_BIG_SUR=16" ]
    );

    # Check if librsvg was built with --disable-pixbuf-loader.
    PKG_CONFIG_GDK_PIXBUF_2_0_GDK_PIXBUF_MODULEDIR = "${librsvg}/${gdk-pixbuf.moduleDir}";
  };

  preConfigure = ''
    # The check runs before glib-networking is registered
    export GIO_EXTRA_MODULES="${glib-networking}/lib/gio/modules:$GIO_EXTRA_MODULES"
  '';

  postFixup = ''
    wrapProgram $out/bin/gimp-${lib.versions.majorMinor finalAttrs.version} \
      --set GDK_PIXBUF_MODULE_FILE "$GDK_PIXBUF_MODULE_FILE"
  '';

  passthru = {
    # The declarations for `gimp-with-plugins` wrapper,
    # used for determining plug-in installation paths
    majorVersion = "${lib.versions.major finalAttrs.version}.0";
    targetLibDir = "lib/gimp/${finalAttrs.passthru.majorVersion}";
    targetDataDir = "share/gimp/${finalAttrs.passthru.majorVersion}";
    targetPluginDir = "${finalAttrs.passthru.targetLibDir}/plug-ins";
    targetScriptDir = "${finalAttrs.passthru.targetDataDir}/scripts";

    # probably its a good idea to use the same gtk in plugins ?
    gtk = gtk2;

    python2Support = withPython;
  };

  meta = with lib; {
    description = "GNU Image Manipulation Program";
    homepage = "https://www.gimp.org/";
    maintainers = with maintainers; [ ];
    license = licenses.gpl3Plus;
    platforms = platforms.unix;
    mainProgram = "gimp";
  };
})
