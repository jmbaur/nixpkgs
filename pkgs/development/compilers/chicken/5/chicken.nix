{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  darwin,
  testers,
  hostname,
  targetPackages,
  isBootstrap ? false,
  chicken-bootstrap,
  breakpointHook,
  hexdump,
  tk,
}:

let
  platform =
    with stdenv.hostPlatform;
    if isDarwin then
      "macosx"
    else if isCygwin then
      "cygwin"
    else if isBSD then
      "bsd"
    else if isSunOS then
      "solaris"
    else if isLinux then
      "linux"
    else
      throw "unsupported chicken platform ${uname.system}";

  pname = "chicken" + lib.optionalString isBootstrap "-bootstrap";
  version = "5.4.0";

  dontCheck = true;

  binaryVersion = 11;

  src = fetchurl {
    url = "https://code.call-cc.org/releases/${version}/chicken-${version}.tar.gz";
    sha256 = "sha256-PF1KphwRZ79tm/nq+JHadjC6n188Fb8JUVpwOb/N7F8=";
  };

  targetChicken = stdenv.mkDerivation {
    __structuredAttrs = true;

    inherit
      pname
      version
      src
      dontCheck
      binaryVersion
      ;

    enableParallelBuilding = true;

    # make -jN install doesn't work, we end up with a failure when linking libchicken.so
    enableParallelInstalling = false;

    makeFlags = [
      "CHICKEN=chicken-bootstrap"
      "ARCH="
      "PREFIX=${placeholder "out"}"
      "PLATFORM=${platform}"
      "C_COMPILER=${targetPackages.stdenv.cc.targetPrefix}cc"
      "CXX_COMPILER=${targetPackages.stdenv.cc.targetPrefix}c++"
      "LIBRARIAN=${targetPackages.stdenv.cc.targetPrefix}ar"
      "TARGET_PREFIX=${placeholder "out"}" # this already defaults to $PREFIX, but whatever
      "TARGET_RUN_PREFIX="
      "WISH=${lib.getExe' targetPackages.tk "wish"}"
    ];

    patches = [ ../../../../../test.patch ];

    nativeBuildInputs = [
      chicken-bootstrap
      hexdump
      breakpointHook
      hostname
      makeWrapper
      targetPackages.stdenv.cc
    ];

    dontPatchShebangs = true;
  };

  chicken = stdenv.mkDerivation {
    __structuredAttrs = true;

    inherit
      pname
      version
      src
      dontCheck
      binaryVersion
      ;

    enableParallelBuilding = true;

    # make -jN install doesn't work, we end up with a failure when linking libchicken.so
    enableParallelInstalling = false;

    makeFlags = [
      "CHICKEN=chicken-bootstrap"
      "PLATFORM=${platform}"
      "PREFIX=${placeholder "out"}"
      "C_COMPILER=${stdenv.cc.targetPrefix}cc"
      "CXX_COMPILER=${stdenv.cc.targetPrefix}c++"
      "LIBRARIAN=${stdenv.cc.targetPrefix}ar"
      # "PROGRAM_PREFIX=${targetPackages.stdenv.cc.targetPrefix}"
      "TARGET_C_COMPILER=${targetPackages.stdenv.cc.targetPrefix}cc"
      "TARGET_CXX_COMPILER=${targetPackages.stdenv.cc.targetPrefix}c++"
      "TARGET_LIBRARIAN=${targetPackages.stdenv.cc.targetPrefix}ar"
      "TARGET_PREFIX=${targetChicken}"
      "TARGET_RUN_PREFIX="
      "WISH=${lib.getExe' tk "wish"}"
    ];

    patches = [ ../../../../../test.patch ];

    nativeBuildInputs = [
      chicken-bootstrap
      hexdump
      breakpointHook
      hostname
      makeWrapper
      targetPackages.stdenv.cc
    ];

    dontPatchShebangs = true;

    # postInstall = ''
    #   mkdir -p $out/nix-support
    #   echo "-I${targetChicken}/include/chicken" >$out/nix-support/cc-cflags
    #   echo "-L${targetChicken}/lib" >$out/nix-support/cc-ldflags
    # '';

    setupHook = ./setup-hook.sh;

    passthru = { inherit targetChicken; };
  };

  bootstrapChicken = stdenv.mkDerivation {
    __structuredAttrs = true;

    inherit
      pname
      version
      src
      dontCheck
      binaryVersion
      ;

    enableParallelBuilding = true;

    # make -jN install doesn't work, we end up with a failure when linking libchicken.so
    enableParallelInstalling = false;

    makeFlags = [
      "PLATFORM=${platform}"
      "PREFIX=${placeholder "out"}"
      "C_COMPILER=${stdenv.cc.targetPrefix}cc"
      "CXX_COMPILER=${stdenv.cc.targetPrefix}c++"
      "LIBRARIAN=${stdenv.cc.targetPrefix}ar"
      "PROGRAM_SUFFIX=-bootstrap"
    ];
  };
in
if isBootstrap then bootstrapChicken else chicken
# stdenv.mkDerivation (finalAttrs: {
#   __structuredAttrs = true;
#
#
#   outputs = [
#     "target"
#     "out"
#
#     # "bin"
#     # "dev"
#     # "doc"
#     # "lib"
#   ];
#
#   enableParallelBuilding = true;
#
#   # make -jN install doesn't work, we end up with a failure when linking libchicken.so
#   enableParallelInstalling = false;
#
#   # Disable two broken tests: "static link" and "linking tests"
#   postPatch = ''
#     sed -i tests/runtests.sh -e "/static link/,+4 { s/^/# / }"
#     sed -i tests/runtests.sh -e "/linking tests/,+11 { s/^/# / }"
#   '';
#
#   setupHook = lib.optional (!isBootstrap) ./setup-hook.sh;
#
#   # makeFlags = [
#   #   "PLATFORM=${platform}"
#   #   "PREFIX=${placeholder "out"}"
#   #   "TARGET_PREFIX=${placeholder "target"}"
#   #   # "BINDIR=${placeholder "bin"}/bin"
#   #   # "LIBDIR=${placeholder "lib"}/lib"
#   #   # "INCLUDEDIR=${placeholder "dev"}/include"
#   #   # "SHAREDIR=${placeholder "doc"}/share"
#   #   # "MANDIR=${placeholder "doc"}/share/man"
#   #   "C_COMPILER=${stdenv.cc.targetPrefix}cc"
#   #   "CXX_COMPILER=${stdenv.cc.targetPrefix}c++"
#   #   "LIBRARIAN=${stdenv.cc.targetPrefix}ar"
#   # ]
#   # ++ lib.optionals stdenv.hostPlatform.isDarwin [
#   #   "XCODE_TOOL_PATH=${darwin.binutils.bintools}/bin"
#   #   "LINKER_OPTIONS=-headerpad_max_install_names"
#   #   "POSTINSTALL_PROGRAM=install_name_tool"
#   # ]
#   # ++ (
#   #   if isBootstrap then
#   #     [ "PROGRAM_SUFFIX=-bootstrap" ]
#   #   else
#   #     [
#   #       "CHICKEN=chicken-bootstrap"
#   #       "ARCH="
#   #       "TARGET_C_COMPILER=${targetPackages.stdenv.cc}/bin/${targetPackages.stdenv.cc.targetPrefix}cc"
#   #       "TARGET_CXX_COMPILER=${targetPackages.stdenv.cc}/bin/${targetPackages.stdenv.cc.targetPrefix}c++"
#   #       "TARGET_LIBRARIAN=${targetPackages.stdenv.cc}/bin/${targetPackages.stdenv.cc.targetPrefix}ar"
#   #     ]
#   # );
#
#   targetFlags = ;
#
#   hostFlags = ;
#
#   buildPhase = ''
#     runHook preBuild
#
#     echo "Using target flags ''${targetFlags[@]}"
#     make -j$NIX_BUILD_CORES ''${targetFlags[@]}
#     make ''${targetFlags[@]} install
#
#     make clean
#
#     echo "Using host flags ''${hostFlags[@]}"
#     make -j$NIX_BUILD_CORES ''${hostFlags[@]}
#     make ''${hostFlags[@]} install
#
#     runHook postBuild
#   '';
#
#   # handled above
#   dontInstall = true;
#
#   nativeBuildInputs = [
#     hexdump
#     breakpointHook
#     hostname
#     makeWrapper
#     targetPackages.stdenv.cc
#   ]
#   # ++ lib.optionals (!isBootstrap) [ chicken-bootstrap ]
#   ++ lib.optionals (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) [
#     darwin.autoSignDarwinBinariesHook
#   ];
#
#   # postInstall = ''
#   #   mkdir -p $dev/nix-support
#   #   echo "-I${placeholder "dev"}/include/chicken" > $dev/nix-support/cc-cflags
#   # '';
#   # moveToOutput bin $bin
#   # moveToOutput include $dev
#   # moveToOutput lib $lib
#
#   # TODO(jared): don't do this
#   dontFixup = true;
#
#   doCheck = false; # !stdenv.hostPlatform.isDarwin;
#   postCheck = ''
#     ./csi${lib.optionalString isBootstrap "-bootstrap"} -R chicken.pathname -R chicken.platform \
#        -p "(assert (equal? \"${toString finalAttrs.binaryVersion}\" (pathname-file (car (repository-path)))))"
#   '';
#
#   postBuild = "exit 1";
#
#   passthru.tests.version = testers.testVersion {
#     package = finalAttrs.finalPackage;
#     command = "csi${lib.optionalString isBootstrap "-bootstrap"} -version";
#   };
#
#   meta = {
#     homepage = "https://call-cc.org/";
#     license = lib.licenses.bsd3;
#     maintainers = with lib.maintainers; [
#       corngood
#       nagy
#       konst-aa
#     ];
#     platforms = lib.platforms.unix;
#     description = "Portable compiler for the Scheme programming language";
#     longDescription = ''
#       CHICKEN is a compiler for the Scheme programming language.
#       CHICKEN produces portable and efficient C, supports almost all
#       of the R5RS Scheme language standard, and includes many
#       enhancements and extensions. CHICKEN runs on Linux, macOS,
#       Windows, and many Unix flavours.
#     '';
#   };
# })
