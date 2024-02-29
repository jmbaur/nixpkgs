{ bison
, callPackage
, curl
, fetchgit
, flex
, getopt
, git
, gnat
, gcc
, lib
, perl
, stdenvNoCC
, zlib
, withAda ? stdenvNoCC.targetPlatform.isx86_64
}:

let
  crossGccArch =
    if stdenvNoCC.targetPlatform.isx86 then
      "i386"
    else if stdenvNoCC.targetPlatform.isAarch32 then
      "arm"
    else if stdenvNoCC.targetPlatform.isAarch64 then
      "aarch64"
    else if stdenvNoCC.targetPlatform.isRiscV64 then
      "riscv"
    else if stdenvNoCC.targetPlatform.isPower64 then
      "ppc64"
    else
      throw "unsupported platform ${stdenvNoCC.targetPlatform.system}"
  ;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "coreboot-toolchain";
  version = "4.22";

  src = fetchgit {
    url = "https://review.coreboot.org/coreboot";
    rev = finalAttrs.version;
    hash = "sha256-OCEBt3YYyfXpnskFojBn/JoWTkNJ4XAI58BG4pyscGc=";
    fetchSubmodules = false;
    leaveDotGit = true;
    postFetch = ''
      ${stdenvNoCC.shell} $out/util/crossgcc/buildgcc -W > $out/.crossgcc_version
      rm -rf $out/.git
    '';
    allowedRequisites = [ ];
  };

  nativeBuildInputs = [ bison curl git perl getopt ];
  buildInputs = [ flex zlib (if withAda then gnat else gcc) ];

  enableParallelBuilding = true;
  dontConfigure = true;
  dontInstall = true;

  postPatch = ''
    patchShebangs util/crossgcc/buildgcc

    mkdir -p util/crossgcc/tarballs

    ${lib.concatMapStringsSep "\n" (
      file: "ln -s ${file.archive} util/crossgcc/tarballs/${file.name}"
      ) (callPackage ./stable.nix { })
    }

    patchShebangs util/genbuild_h/genbuild_h.sh
  '';

  buildPhase = ''
    export CROSSGCC_VERSION=$(cat .crossgcc_version)
    make crossgcc-${crossGccArch} CPUS=$NIX_BUILD_CORES DEST=$out
  '';

  meta = with lib; {
    homepage = "https://www.coreboot.org";
    description = "coreboot toolchain";
    license = with licenses; [ bsd2 bsd3 gpl2 lgpl2Plus gpl3Plus ];
    maintainers = with maintainers; [ felixsinger ];
    platforms = platforms.linux;
  };
})

