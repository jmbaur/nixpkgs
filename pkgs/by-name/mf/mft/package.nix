{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "mft";
  version = "4.29.0";

  src = fetchurl (
    if stdenv.hostPlatform.isAarch64 then
      {
        url = "https://www.mellanox.com/downloads/MFT/mft-${finalAttrs.version}-131-arm64-deb.tgz";
        hash = "";
      }
    else if stdenv.hostPlatform.isPower64 then
      {
        url = "https://www.mellanox.com/downloads/MFT/mft-${finalAttrs.version}-131-ppc64-deb.tgz";
        hash = "";
      }
    else if stdenv.hostPlatform.isx86_64 then
      {
        url = "https://www.mellanox.com/downloads/MFT/mft-${finalAttrs.version}-131-x86_64-deb.tgz";
        hash = "sha256-JQpr3dBwHhEwabT/fksVmlrCi9PfVdmbkoolVKxxz/k=";
      }
    else
      throw "unsupported platform"
  );

  postPatch = ''
    patchShebangs install.sh
  '';

  installPhase = ''
    ./install.sh $out
    find
    exit 3
  '';

  meta = {
    platforms = [
      "aarch64-linux"
      "powerpc64-linux"
      "x86_64-linux"
    ];
    maintainers = [ lib.maintainers.jmbaur ];
  };
})
