{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "rke";
  version = "1.8.5";

  src = fetchFromGitHub {
    owner = "rancher";
    repo = "rke";
    rev = "v${version}";
    hash = "sha256-ahz5RFqc4pwnyxGoRps2PPj+PFFHuIhrxiD7XC6Tuj8=";
  };

  vendorHash = "sha256-OWC8OZhORHwntAR2YHd4KfQgB2Wtma6ayBWfY94uOA4=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X=main.VERSION=v${version}"
  ];

  meta = {
    homepage = "https://github.com/rancher/rke";
    description = "Extremely simple, lightning fast Kubernetes distribution that runs entirely within containers";
    mainProgram = "rke";
    changelog = "https://github.com/rancher/rke/releases/tag/v${version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ urandom ];
  };
}
