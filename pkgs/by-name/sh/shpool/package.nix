{
  lib,
  rustPlatform,
  fetchFromGitHub,
  stdenv,
  darwin,
  pam,
}:

rustPlatform.buildRustPackage rec {
  pname = "shpool";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "shell-pool";
    repo = "shpool";
    rev = "v${version}";
    hash = "sha256-c4LfxsNHCP+QmtY+lU1nrcTISGtlIfK2RXsu0BEoa84=";
    fetchSubmodules = true;
  };

  cargoHash = "sha256-Uj8N3N/bTssT40udawLUDjeRLjo1/LIYFqZeCGh2Na4=";

  buildInputs =
    [ pam ]
    ++ lib.optionals stdenv.isDarwin [
      darwin.apple_sdk.frameworks.CoreFoundation
      darwin.apple_sdk.frameworks.CoreServices
    ];

  meta = with lib; {
    description = "Think tmux, then aim... lower";
    homepage = "https://github.com/shell-pool/shpool";
    license = licenses.asl20;
    maintainers = with maintainers; [ jmbaur ];
    mainProgram = "shpool";
  };
}
