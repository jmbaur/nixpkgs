{ lib, buildGoModule, fetchFromGitHub, nixosTests }:

buildGoModule rec {
  pname = "corerad";
  version = "1.2.2";

  src = fetchFromGitHub {
    owner = "jmbaur";
    repo = "corerad";
    rev = "3e7692d2eaf2c814249e63d3711938433e9b64dd";
    hash = "sha256-KktE4xRtSPXtrYQ+fTbIAXmr5cJbL79xlNX66cvBroQ=";
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
