{ lib
, rustPlatform
, fetchFromGitHub
, systemd
}:

rustPlatform.buildRustPackage {
  pname = "virtme-ng-init";
  version = "unstable-2024-01-31";

  src = fetchFromGitHub {
    owner = "arighi";
    repo = "virtme-ng-init";
    rev = "b8cba09b3cef230cf80aa63fc8dec24f913809c9";
    hash = "sha256-kNsPjlKQB4b067kVuJsSH/NJi5iiwhG6Eg3H0PKVN40=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
    sed -i 's,/usr/lib/systemd/systemd-udevd,${systemd}/lib/systemd/systemd-udevd,' src/main.rs
  '';

  meta = with lib; {
    description = "Fast init process for virtme-ng";
    homepage = "https://github.com/arighi/virtme-ng-init";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ ];
    mainProgram = "virtme-ng-init";
  };
}
