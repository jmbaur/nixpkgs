{
  config,
  lib,
  ...
}:

{

  imports = [
    ./etc.nix
    ./confext.nix
  ];

  config = {
    system.activationScripts.etc = lib.stringAfter [
      "users"
      "groups"
      "specialfs"
    ] config.system.build.etcActivationCommands;
  };
}
