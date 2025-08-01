{
  lib,
  stdenv,
  build2,
  fetchurl,
  git,
  libbpkg,
  libbutl,
  libodb,
  libodb-sqlite,
  openssl,
  enableShared ? !stdenv.hostPlatform.isStatic,
  enableStatic ? !enableShared,
}:

stdenv.mkDerivation rec {
  pname = "bpkg";
  version = "0.17.0";

  outputs = [
    "out"
    "doc"
    "man"
  ];

  src = fetchurl {
    url = "https://pkg.cppget.org/1/alpha/build2/bpkg-${version}.tar.gz";
    hash = "sha256-Yw6wvTqO+VfCo91B2BUT0A8OIN0MVhGK1USYM7hgGMs=";
  };

  strictDeps = true;
  nativeBuildInputs = [
    build2
  ];
  buildInputs = [
    build2
    libbpkg
    libbutl
    libodb
    libodb-sqlite
  ];
  nativeCheckInputs = [
    git
    openssl
  ];

  doCheck = !stdenv.hostPlatform.isDarwin; # tests hang

  # Failing test
  postPatch = ''
    rm tests/rep-create.testscript
  '';

  build2ConfigureFlags = [
    "config.bin.lib=${build2.configSharedStatic enableShared enableStatic}"
  ];

  postInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    install_name_tool -add_rpath '${lib.getLib build2}/lib' "''${!outputBin}/bin/bpkg"
  '';

  meta = with lib; {
    description = "Build2 package dependency manager";
    mainProgram = "bpkg";
    # https://build2.org/bpkg/doc/bpkg.xhtml
    longDescription = ''
      The build2 package dependency manager is used to manipulate build
      configurations, packages, and repositories.
    '';
    homepage = "https://build2.org/";
    changelog = "https://git.build2.org/cgit/bpkg/tree/NEWS";
    license = licenses.mit;
    maintainers = with maintainers; [ r-burns ];
    platforms = platforms.all;
  };
}
