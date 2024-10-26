{
  lib,
  cairo,
  fetchFromGitHub,
  gettext,
  glib,
  libdrm,
  libinput,
  libpng,
  librsvg,
  libsfdo,
  libxcb,
  libxkbcommon,
  libxml2,
  meson,
  ninja,
  pango,
  pkg-config,
  scdoc,
  stdenv,
  wayland,
  wayland-protocols,
  wayland-scanner,
  wlroots_0_18,
  xcbutilwm,
  xwayland,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "labwc";
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "labwc";
    repo = "labwc";
    rev = "refs/tags/${finalAttrs.version}";
    hash = "sha256-TXxdjMkzZQoCqkZBqus5eCBEhA/nvxNNXaNHUTGFQDQ=";
  };

  outputs = [
    "out"
    "doc"
    "man"
  ];

  nativeBuildInputs = [
    gettext
    meson
    ninja
    pkg-config
    scdoc
    wayland-scanner
  ];

  buildInputs = [
    cairo
    glib
    libdrm
    libinput
    libpng
    librsvg
    libsfdo
    libxcb
    libxkbcommon
    libxml2
    pango
    wayland
    wayland-protocols
    wlroots_0_18
    xcbutilwm
    xwayland
  ];

  mesonFlags = [ (lib.mesonEnable "xwayland" true) ];

  strictDeps = true;

  passthru = {
    providedSessions = [ "labwc" ];
  };

  meta = {
    homepage = "https://github.com/labwc/labwc";
    description = "Wayland stacking compositor, inspired by Openbox";
    license = with lib.licenses; [ gpl2Plus ];
    mainProgram = "labwc";
    maintainers = with lib.maintainers; [ AndersonTorres ];
    inherit (wayland.meta) platforms;
  };
})
