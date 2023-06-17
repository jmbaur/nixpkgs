{ lib
, fetchFromGitHub
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  pname = "dhcpm";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "leshow";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-vjKN9arR6Os3pgG89qmHt/0Ds5ToO38tLsQBay6VEIk=";
  };

  cargoSha256 = "sha256-+nWP1XgL6MKg6tESvOj/exya21QmwbRNlshwENHfj1U=";

  meta = with lib; {
    description = "A CLI tool for constructing & sending DHCP messages";
    homepage = "https://github.com/leshow/dhcpm";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ jmbaur ];
  };
}
