{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "tidy-viewer";
  version = "1.5.2";

  src = fetchFromGitHub {
    owner = "alexhallam";
    repo = "tv";
    rev = version;
    sha256 = "sha256-OnvRiQ5H/Vsmfu+F1i68TowjrDwQLQtV1sC6Jrp4xA4=";
  };

  cargoHash = "sha256-k/8crmGkFOLcakL5roYrSBVoYyGMELh1Mu/X6SlUeds=";

  # this test parses command line arguments
  # error: Found argument '--test-threads' which wasn't expected, or isn't valid in this context
  checkFlags = [
    "--skip=build_reader_can_create_reader_without_file_specified"
  ];

  meta = {
    description = "Cross-platform CLI csv pretty printer that uses column styling to maximize viewer enjoyment";
    mainProgram = "tidy-viewer";
    homepage = "https://github.com/alexhallam/tv";
    changelog = "https://github.com/alexhallam/tv/blob/${version}/CHANGELOG.md";
    license = lib.licenses.unlicense;
    maintainers = with lib.maintainers; [ figsoda ];
  };
}
