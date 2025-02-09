{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchFromGitLab,
  dtc,
  openssl,
  pkgsCross,
  buildPackages,

  # Warning: this blob (hdcp.bin) runs on the main CPU (not the GPU) at
  # privilege level EL3, which is above both the kernel and the
  # hypervisor.
  #
  # This parameter applies only to platforms which are believed to use
  # hdcp.bin. On all other platforms, or if unfreeIncludeHDCPBlob=false,
  # hdcp.bin will be deleted before building.
  unfreeIncludeHDCPBlob ? true,
}:

let
  buildArmTrustedFirmware =
    {
      filesToInstall,
      installDir ? "$out",
      platform ? null,
      platformCanUseHDCPBlob ? false, # set this to true if the platform is able to use hdcp.bin
      extraMakeFlags ? [ ],
      extraMeta ? { },
      ...
    }@args:

    # delete hdcp.bin if either: the platform is thought to
    # not need it or unfreeIncludeHDCPBlob is false
    let
      deleteHDCPBlobBeforeBuild = !platformCanUseHDCPBlob || !unfreeIncludeHDCPBlob;
    in

    stdenv.mkDerivation (
      finalAttrs:
      {

        pname = "arm-trusted-firmware${lib.optionalString (platform != null) "-${platform}"}";
        version = "2.12.0";

        src = fetchFromGitHub {
          owner = "ARM-software";
          repo = "arm-trusted-firmware";
          tag = "v${finalAttrs.version}";
          hash = "sha256-PCUKLfmvIBiJqVmKSUKkNig1h44+4RypZ04BvJ+HP6M=";
        };

        patches =
          [
            ./m0-objcopy.patch
          ]
          ++ lib.optionals deleteHDCPBlobBeforeBuild [
            # this is a rebased version of https://gitlab.com/vicencb/kevinboot/-/blob/master/atf.patch
            ./remove-hdcp-blob.patch
          ];

        postPatch = lib.optionalString deleteHDCPBlobBeforeBuild ''
          rm plat/rockchip/rk3399/drivers/dp/hdcp.bin
        '';

        strictDeps = true;

        depsBuildBuild = [ buildPackages.stdenv.cc ];

        nativeBuildInputs = [
          dtc

          # For Cortex-M0 firmware in RK3399
          pkgsCross.arm-embedded.stdenv.cc
        ];

        buildInputs = [ openssl ];

        env.NIX_CFLAGS_COMPILE = toString [
          # Accommodate -flto:
          "-ffat-lto-objects"
        ];

        makeFlags =
          [
            "HOSTCC=$(CC_FOR_BUILD)"
            "M0_CROSS_COMPILE=${pkgsCross.arm-embedded.stdenv.cc.targetPrefix}"
            "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
            "OD=$(OBJDUMP)"
            "OC=$(OBJCOPY)"
            # GNU's assembler doesn't recognize the `-x` option, so instead,
            # use the GNU C compiler, which does recognize it.
            "HOSTAS=$(CC_FOR_BUILD)"
            "AS=$(CC)"
          ]
          ++ (lib.optional (platform != null) "PLAT=${platform}")
          ++ extraMakeFlags;

        installPhase = ''
          runHook preInstall

          mkdir -p ${installDir}
          cp ${lib.concatStringsSep " " filesToInstall} ${installDir}

          runHook postInstall
        '';

        hardeningDisable = [ "all" ];
        dontStrip = true;

        enableParallelBuilding = true;

        meta =
          with lib;
          {
            homepage = "https://github.com/ARM-software/arm-trusted-firmware";
            description = "Reference implementation of secure world software for ARMv8-A";
            license = [
              licenses.bsd3
            ] ++ lib.optionals (!deleteHDCPBlobBeforeBuild) [ licenses.unfreeRedistributable ];
            maintainers = with maintainers; [ lopsided98 ];
          }
          // extraMeta;
      }
      // builtins.removeAttrs args [ "extraMeta" ]
    );

in
{
  inherit buildArmTrustedFirmware;

  armTrustedFirmwareTools = buildArmTrustedFirmware {
    # Normally, arm-trusted-firmware builds the build tools for buildPlatform
    # using CC_FOR_BUILD (or as it calls it HOSTCC). Since want to build them
    # for the hostPlatform here, we trick it by overriding the HOSTCC setting
    # and, to be safe, remove CC_FOR_BUILD from the environment.
    depsBuildBuild = [ ];
    extraMakeFlags = [
      "HOSTCC=${stdenv.cc.targetPrefix}cc"
      "fiptool"
      "certtool"
    ];
    filesToInstall = [
      "tools/fiptool/fiptool"
      "tools/cert_create/cert_create"
    ];
    postInstall = ''
      mkdir -p "$out/bin"
      find "$out" -type f -executable -exec mv -t "$out/bin" {} +
    '';
  };

  armTrustedFirmwareAllwinner = buildArmTrustedFirmware rec {
    platform = "sun50i_a64";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/release/bl31.bin" ];
  };

  armTrustedFirmwareAllwinnerH616 = buildArmTrustedFirmware rec {
    platform = "sun50i_h616";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/release/bl31.bin" ];
  };

  armTrustedFirmwareAllwinnerH6 = buildArmTrustedFirmware rec {
    platform = "sun50i_h6";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/release/bl31.bin" ];
  };

  armTrustedFirmwareQemu = buildArmTrustedFirmware rec {
    platform = "qemu";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [
      "build/${platform}/release/bl1.bin"
      "build/${platform}/release/bl2.bin"
      "build/${platform}/release/bl31.bin"
    ];
  };

  armTrustedFirmwareRK3328 = buildArmTrustedFirmware rec {
    extraMakeFlags = [ "bl31" ];
    platform = "rk3328";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/release/bl31/bl31.elf" ];
  };

  armTrustedFirmwareRK3399 = buildArmTrustedFirmware rec {
    extraMakeFlags = [ "bl31" ];
    platform = "rk3399";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/release/bl31/bl31.elf" ];
    platformCanUseHDCPBlob = true;
  };

  armTrustedFirmwareRK3588 = buildArmTrustedFirmware rec {
    extraMakeFlags = [ "bl31" ];
    platform = "rk3588";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/release/bl31/bl31.elf" ];
  };

  armTrustedFirmwareS905 = buildArmTrustedFirmware rec {
    extraMakeFlags = [ "bl31" ];
    platform = "gxbb";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/release/bl31.bin" ];
  };
}
