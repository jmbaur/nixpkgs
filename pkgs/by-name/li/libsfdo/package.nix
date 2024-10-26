{
  lib,
  stdenv,
  fetchFromGitLab,
  meson,
  ninja,
  pkg-config,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libsfdo";
  version = "0.1.3";

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "vyivel";
    repo = "libsfdo";
    rev = "refs/tags/v${finalAttrs.version}";
    hash = "sha256-9jCfCIB07mmJ6aWQHvXaxYhEMNikUw/W1xrpmh6FKbo=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];

  meta = {
    description = "A collection of libraries which implement some of the freedesktop.org specifications";
    homepage = "https://gitlab.freedesktop.org/vyivel/libsfdo";
    license = lib.licenses.bsd2;
    platforms = lib.platforms.linux;
    maintainers = [ lib.maintainers.jmbaur ];
  };
})
