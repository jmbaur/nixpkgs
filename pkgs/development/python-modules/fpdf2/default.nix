{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  setuptools,

  defusedxml,
  pillow,
  fonttools,

  pytestCheckHook,
  pytest-cov-stub,
  qrcode,
  camelot,
  uharfbuzz,
  lxml,
}:

buildPythonPackage rec {
  pname = "fpdf2";
  version = "2.8.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "py-pdf";
    repo = "fpdf2";
    tag = version;
    hash = "sha256-NfHMmyFT+ZpqfRc41DetbFXs/twr12XagOkk3nGhrYk=";
  };

  nativeBuildInputs = [ setuptools ];

  propagatedBuildInputs = [
    defusedxml
    pillow
    fonttools
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-cov-stub
    qrcode
    camelot
    uharfbuzz
    lxml
  ];

  disabledTestPaths = [
    "test/table/test_table_extraction.py" # tabula-py not packaged yet
    "test/signing/test_sign.py" # endesive not packaged yet
  ];

  disabledTests = [
    "test_png_url" # tries to download file
    "test_page_background" # tries to download file
    "test_share_images_cache" # uses timing functions
    "test_bidi_character" # tries to download file
    "test_bidi_conformance" # tries to download file
    "test_insert_jpg_jpxdecode" # JPEG2000 is broken
  ];

  meta = {
    homepage = "https://github.com/py-pdf/fpdf2";
    description = "Simple PDF generation for Python";
    changelog = "https://github.com/py-pdf/fpdf2/blob/${version}/CHANGELOG.md";
    license = lib.licenses.lgpl3Only;
    maintainers = with lib.maintainers; [ jfvillablanca ];
  };
}
