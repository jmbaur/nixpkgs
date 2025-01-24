{
  lib,
  replaceVarsWith,
  runtimeShell,
  installShellFiles,
  jq,
  nixos-enter,
  util-linuxMinimal,
  nixosTests,
  qemu-user,
}:
replaceVarsWith {
  name = "nixos-install";
  src = ./nixos-install.sh;

  replacements = {
    inherit runtimeShell;

    bootloaderInstallScript = ./bootloader-install-script.sh;

    magics = ../../../../magic.json;

    path = lib.makeBinPath [
      jq
      nixos-enter
      util-linuxMinimal
      qemu-user
    ];
  };

  dir = "bin";
  isExecutable = true;

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    installManPage ${./nixos-install.8}
  '';

  passthru.tests.installer-simpleUefiSystemdBoot = nixosTests.installer.simpleUefiSystemdBoot;

  meta = {
    description = "Install bootloader and NixOS";
    homepage = "https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/ni/nixos-install";
    license = lib.licenses.mit;
    mainProgram = "nixos-install";
  };
}
