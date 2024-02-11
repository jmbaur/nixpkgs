{ lib
, python3
, fetchFromGitHub
, virtme-ng-init
, dpkg
, qemu
, virtiofsd
, rsync
, zstd
, kmod
, kbd
}:

python3.pkgs.buildPythonApplication rec {
  pname = "virtme-ng";
  version = "1.20";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "arighi";
    repo = "virtme-ng";
    rev = "v${version}";
    hash = "sha256-eEk5bG0y/FgKESIkfdlNQ0yGi1YWCaWUfPiGfENeGtc=";
    fetchSubmodules = true;
  };

  env.BUILD_VIRTME_NG_INIT = 0;

  preBuild = ''
    install -D --target-directory virtme/guest/bin ${lib.getExe virtme-ng-init}
  '';

  nativeBuildInputs = with python3.pkgs; [
    argcomplete
    setuptools
    wheel
  ];

  propagatedBuildInputs = [
    dpkg
    qemu
    virtiofsd
    rsync
    zstd
    kmod
    kbd
  ] ++ (with python3.pkgs; [
    argcomplete
    requests
    setuptools
  ]);

  pythonImportsCheck = [ "virtme_ng" ];

  meta = with lib; {
    description = "Quickly build and run kernels inside a virtualized snapshot of your live system";
    homepage = "https://github.com/arighi/virtme-ng";
    license = licenses.gpl2Only;
    maintainers = with maintainers; [ ];
    mainProgram = "virtme-ng";
  };
}
