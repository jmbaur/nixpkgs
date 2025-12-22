{
  callPackage,
  lib,
  stdenv,
  chicken,
  makeWrapper,
  pkgsBuildBuild,
  breakpointHook,
}:
{
  # src,
  buildInputs ? [ ],
  chickenInstallFlags ? [ ],
  cscOptions ? [ ],
  ...
}@args:

let
  nameVersionAssertion =
    pred: lib.assertMsg pred "either name or both pname and version must be given";
  pname =
    if args ? pname then
      assert nameVersionAssertion (!args ? name && args ? version);
      args.pname
    else
      assert nameVersionAssertion (args ? name && !args ? version);
      lib.getName args.name;
  version = if args ? version then args.version else lib.getVersion args.name;
  # TODO(jared): delete this
  # name = if args ? name then args.name else "${args.pname}-${args.version}";
  overrides = callPackage ./overrides.nix { };
  override = if builtins.hasAttr pname overrides then builtins.getAttr pname overrides else lib.id;
in
(stdenv.mkDerivation (
  {
    __structuredAttrs = true;

    pname = "chicken-${pname}";
    inherit version;

    propagatedBuildInputs = buildInputs;

    depsBuildBuild = [ pkgsBuildBuild.stdenv.cc ];

    nativeBuildInputs = [
      chicken
      makeWrapper
      breakpointHook
    ];

    strictDeps = true;

    env = {
      CSC_OPTIONS = lib.concatStringsSep " " cscOptions;
      CHICKEN_INSTALL_PREFIX = placeholder "out";
      CHICKEN_INSTALL_REPOSITORY = "${placeholder "out"}/lib/chicken/${toString chicken.binaryVersion}";
    };

    buildPhase = ''
      runHook preBuild

      ${/* stdenv.cc.targetPrefix */ ""}chicken-install -cached -no-install ${lib.escapeShellArgs chickenInstallFlags}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      DESTDIR=$out ${/* stdenv.cc.targetPrefix */ ""}chicken-install -cached -target ${lib.escapeShellArgs chickenInstallFlags}
      # ${/* stdenv.cc.targetPrefix */ ""}chicken-install -cached ${lib.escapeShellArgs chickenInstallFlags}

      # Patching generated .egg-info instead of original .egg to work around https://bugs.call-cc.org/ticket/1855
      ${
        /* stdenv.cc.targetPrefix */ ""
      }csi -e "(write (cons '(version \"${version}\") (read)))" < "$out/lib/chicken/${toString chicken.binaryVersion}/${pname}.egg-info" > "${pname}.egg-info.new"
      mv "${pname}.egg-info.new" "$out/lib/chicken/${toString chicken.binaryVersion}/${pname}.egg-info"

      # exit 1
      runHook postInstall
    '';

    # for f in $out/bin/*; do
    #   wrapProgram $f \
    #     --prefix CHICKEN_REPOSITORY_PATH : "$out/lib/chicken/${toString chicken.binaryVersion}:$CHICKEN_REPOSITORY_PATH" \
    #     --prefix CHICKEN_INCLUDE_PATH : "$CHICKEN_INCLUDE_PATH:$out/share" \
    #     --prefix PATH : "$out/bin:${chicken}/bin:$CHICKEN_REPOSITORY_PATH"
    # done

    dontConfigure = true;

    meta = {
      # inherit (chicken.meta) platforms;
    }
    // args.meta or { };
  }
  // removeAttrs args [
    "name"
    "pname"
    "version"
    "buildInputs"
    "meta"
  ]
)).overrideAttrs
  override
