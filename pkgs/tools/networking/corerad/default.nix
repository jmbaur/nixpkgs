{ lib, buildGoModule, fetchFromGitHub, nixosTests }:

buildGoModule rec {
  pname = "corerad";
  version = "1.2.2";

  src = fetchFromGitHub {
    owner = "jmbaur";
    repo = "corerad";
    rev = "16bf4d50427a70ae19ee63fd9eb6fb6e9776902d";
    hash = "sha256-Scv8IkAo12WRsZDVQfSse8LRTu4UkHhafhRrYglUOK4=";
  };

  vendorHash = "sha256-SPYsTfNRPUIyWQSR82ytgVIq+hNqxV8ys8ATTZaj8N0=";

  # Since the tarball pulled from GitHub doesn't contain git tag information,
  # we fetch the expected tag's timestamp from a file in the root of the
  # repository.
  preBuild = ''
    buildFlagsArray=(
      -ldflags="
        -X github.com/mdlayher/corerad/internal/build.linkTimestamp=$(<.gittagtime)
        -X github.com/mdlayher/corerad/internal/build.linkVersion=v${version}
      "
    )
  '';

  passthru.tests = {
    inherit (nixosTests) corerad;
  };

  meta = with lib; {
    homepage = "https://github.com/mdlayher/corerad";
    description = "Extensible and observable IPv6 NDP RA daemon";
    license = licenses.asl20;
    maintainers = with maintainers; [ mdlayher ];
    platforms = platforms.linux;
    mainProgram = "corerad";
  };
}
