{
  callPackage,
  lib,
  stdenv,
  __splicedPackages,
  chicken,
  makeWrapper,

  # Release-specific arguments, supplied by the per-release directory.
  overridesFile,
}:

let
  # With the spliced package set, what overrides add to each list of
  # dependencies is built for the platform that list is for.
  overrides = callPackage overridesFile { pkgs = __splicedPackages; };

  # When cross-compiling, the chicken in nativeBuildInputs is a cross chicken.
  # Its chicken-install would build every egg twice: once for the build
  # platform, which the build platform's egg set provides already, and once for
  # the target. It is only asked for the scripts it would run, of which those
  # for the target are then run by hand. They install into the repository of
  # the target's runtime, the path of which is fixed when the cross chicken is
  # built, so DESTDIR redirects them to where they can be moved into $out.
  isCross = stdenv.hostPlatform != stdenv.buildPlatform;
  binaryVersion = toString chicken.binaryVersion;

  # The chicken that runs where the egg does, which the egg links to and its
  # programs run with. Spliced, chicken alone is the one compiling for the
  # target platform, which is a cross chicken in the build platform's egg set
  # of a cross-compiled one, as that set's target is the host platform.
  hostChicken = chicken.__spliced.hostHost or chicken;
in
lib.extendMkDerivation {
  constructDrv = stdenv.mkDerivation;

  excludeDrvArgNames = [
    "name"
    "buildPlatformEgg"
  ];

  extendDrvArgs =
    finalAttrs:
    {
      src,
      chickenInstallFlags ? [ ],
      cscOptions ? [ ],
      # When cross-compiling, this egg built for the build platform, for
      # compiling what imports it and for eggs which load parts of themselves
      # while being compiled.
      buildPlatformEgg ? null,
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
    in
    {
      pname = "chicken-${pname}";
      inherit version;
      # Eggs are found in dev, which propagates out and the eggs they depend on.
      outputs =
        args.outputs or [
          "out"
          "dev"
        ];
      nativeBuildInputs = [
        chicken
        makeWrapper
      ]
      ++ args.nativeBuildInputs or [ ];
      # The runtime the egg is compiled against and links to, which, with
      # strictDeps, the chicken in nativeBuildInputs does not provide when
      # cross-compiling.
      buildInputs = [ hostChicken ] ++ args.buildInputs or [ ];

      strictDeps = args.strictDeps or true;

      env = {
        CSC_OPTIONS = lib.concatStringsSep " " cscOptions;
      }
      // args.env or { };

      buildPhase =
        args.buildPhase or (
          ''
            runHook preBuild

            # From CHICKEN 6 on, chicken-install takes a lock in its egg cache even
            # when building an egg from the current directory, and the cache defaults
            # to a location under HOME, which is not writable in the sandbox. The
            # cache itself stays empty: with -cached, chicken-install builds the
            # unpacked egg in place. The install phase runs in the same shell, so it
            # inherits this.
            export CHICKEN_EGG_CACHE="$NIX_BUILD_TOP/chicken-egg-cache"
            mkdir -p "$CHICKEN_EGG_CACHE"

          ''
          + (
            if isCross then
              ''
                chicken-install -cached -dry-run ${lib.escapeShellArgs chickenInstallFlags}

                # Files built for the target get a .target suffix, to set them apart
                # from those built for the build platform. The scripts are not
                # consistent about it for objects, though: the C objects some eggs
                # link into their extensions are passed to csc with the suffix, which
                # hides that they are objects, and to ar without it. As no objects
                # are built for the build platform here, dropping the suffix from
                # objects is safe. It must stay on import libraries, lest the compiler
                # try to load those built for the target.
                sed -i 's/\.o\.target\b/.o/g' *.target.sh
              ''
              + lib.optionalString (buildPlatformEgg != null) ''

                # Eggs whose modules are needed while compiling others, such as for
                # their macros, rely on those built for the build platform being in
                # the build directory, where the compiler looks first. Those are the
                # ones the egg installs.
                for file in ${buildPlatformEgg}/lib/chicken/${binaryVersion}/*.so; do
                  [[ -e "''${file##*/}" ]] || ln -s "$file" .
                done
              ''
              + ''

                for script in *.build.target.sh; do
                  sh "$script"
                done
              ''
            else
              ''
                chicken-install -cached -no-install ${lib.escapeShellArgs chickenInstallFlags}
              ''
          )
          + ''

            runHook postBuild
          ''
        );

      installPhase =
        args.installPhase or (
          ''
            runHook preInstall

            repository=$out/lib/chicken/${binaryVersion}
          ''
          + (
            if isCross then
              ''
                for script in *.install.target.sh; do
                  DESTDIR=$NIX_BUILD_TOP/chicken-destdir sh "$script"
                done

                # Most files go to the prefix of the target's runtime, but programs go
                # to that of the cross chicken, as egg-environment.scm defines
                # default-bindir twice, the second time for the build platform.
                mkdir -p $out
                for prefix in "$NIX_BUILD_TOP/chicken-destdir$NIX_STORE"/*; do
                  cp -r "$prefix/." $out
                done
                for prefix in "$NIX_BUILD_TOP/chicken-destdir$NIX_STORE"/*; do
                  substituteInPlace "$repository/${pname}.egg-info" \
                    --replace-quiet "''${prefix#"$NIX_BUILD_TOP/chicken-destdir"}" "$out"
                done
              ''
            else
              ''
                export CHICKEN_INSTALL_PREFIX=$out
                export CHICKEN_INSTALL_REPOSITORY=$repository
                chicken-install -cached ${lib.escapeShellArgs chickenInstallFlags}
              ''
          )
          + ''

            # What only the compiler and the egg tools use goes to dev, so that eggs
            # loaded at run time do not bring it along: objects and link files, for
            # linking statically, type and inlining information, and the .egg-info,
            # by which chicken-install finds that the egg is installed.
            devRepository=$dev/lib/chicken/${binaryVersion}
            mkdir -p "$devRepository"
            for file in "$repository"/*.{o,a,link,types,inline,egg-info}; do
              if [[ -e "$file" ]]; then
                mv "$file" "$devRepository/"
              fi
            done

            # Patching the generated .egg-info instead of the original .egg; see the
            # script for why.
            csi -s ${./patch-egg-info.scm} ${lib.escapeShellArg version} "$devRepository" < "$devRepository/${pname}.egg-info" > "${pname}.egg-info.new"
            mv "${pname}.egg-info.new" "$devRepository/${pname}.egg-info"

            # Programs run with the repositories of the eggs they use, which are the
            # ones holding extensions and import libraries, in the out outputs, and
            # that of the runtime, with the core modules, as setting
            # CHICKEN_REPOSITORY_PATH replaces it.
            runtimeRepositories=$repository:${lib.getLib hostChicken}/lib/chicken/${binaryVersion}
            IFS=: read -ra repositories <<< "''${NIX_CHICKEN_TARGET_REPOSITORY_PATH-}"
            for dependency in "''${repositories[@]}"; do
              for library in "$dependency"/*.so; do
                if [[ -e "$library" && ":$runtimeRepositories:" != *":$dependency:"* ]]; then
                  runtimeRepositories+=":$dependency"
                fi
                break
              done
            done

            for f in $out/bin/*
            do
              wrapProgram $f \
                --prefix CHICKEN_REPOSITORY_PATH : "$runtimeRepositories" \
                --prefix CHICKEN_INCLUDE_PATH : "$NIX_CHICKEN_TARGET_INCLUDE_PATH:$out/share" \
                --prefix PATH : "$out/bin:${hostChicken}/bin"
            done

            runHook postInstall
          ''
        );

      dontConfigure = args.dontConfigure or true;

      # Custom build scripts of eggs, and the helpers they use to probe for
      # libraries, call the C toolchain and pkg-config by their plain names,
      # which do not exist when cross-compiling. As only code for the target is
      # built, they are made to mean the target's tools.
      ${if isCross then "preBuildPhases" else null} = [ "chickenCrossToolsPhase" ];
      ${if isCross then "chickenCrossToolsPhase" else null} = ''
        mkdir -p "$NIX_BUILD_TOP/chicken-cross-tools"
        for tool in cc:CC gcc:CC c++:CXX g++:CXX ar:AR pkg-config:PKG_CONFIG; do
          name=''${tool%:*}
          var=''${tool#*:}
          if [[ -n "''${!var-}" ]]; then
            ln -s "$(command -v "''${!var}")" "$NIX_BUILD_TOP/chicken-cross-tools/$name"
          fi
        done
        export PATH="$NIX_BUILD_TOP/chicken-cross-tools:$PATH"
      '';

      # Compiling code that imports an egg loads the egg, so the cross chicken
      # needs it built for the build platform. Propagating that build puts it,
      # along with the eggs it depends on, in the nativeBuildInputs of whatever
      # takes this egg as a build input. It is only added once the egg is
      # built, as the egg must not see its own declarations while compiling
      # itself, which propagatedNativeBuildInputs would also give it.
      # buildPlatformEgg is this egg spliced, so only values may look at it;
      # attribute names depending on it would recurse infinitely.
      ${if isCross then "preFixupPhases" else null} = lib.optional (
        buildPlatformEgg != null
      ) "chickenPropagateBuildPlatformEggPhase";
      ${if isCross then "chickenPropagateBuildPlatformEggPhase" else null} =
        lib.optionalString (buildPlatformEgg != null)
          ''
            appendToVar propagatedNativeBuildInputs ${lib.getDev buildPlatformEgg}
          '';

      passthru = {
        eggName = pname;
      }
      // args.passthru or { };

      meta = {
        inherit (chicken.meta) platforms;
      }
      // args.meta or { };
    };

  # Overrides are applied to the finished derivation, so that they see and
  # extend its final attributes rather than the arguments.
  transformDrv = drv: drv.overrideAttrs (overrides.${drv.eggName} or lib.id);
}
