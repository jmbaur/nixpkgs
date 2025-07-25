{
  lib,
  stdenv,
  buildPythonPackage,
  fastimport,
  fetchFromGitHub,
  gevent,
  geventhttpclient,
  git,
  glibcLocales,
  gnupg,
  gpgme,
  paramiko,
  pytestCheckHook,
  pythonOlder,
  setuptools,
  setuptools-rust,
  urllib3,
}:

buildPythonPackage rec {
  pname = "dulwich";
  version = "0.22.8";
  pyproject = true;

  disabled = pythonOlder "3.9";

  src = fetchFromGitHub {
    owner = "jelmer";
    repo = "dulwich";
    tag = "dulwich-${version}";
    hash = "sha256-T0Tmu5sblTkqiak9U4ltkGbWw8ZE91pTlhPVMRi5Pxk=";
  };

  build-system = [
    setuptools
    setuptools-rust
  ];

  propagatedBuildInputs = [
    urllib3
  ];

  optional-dependencies = {
    fastimport = [ fastimport ];
    https = [ urllib3 ];
    pgp = [
      gpgme
      gnupg
    ];
    paramiko = [ paramiko ];
  };

  nativeCheckInputs = [
    gevent
    geventhttpclient
    git
    glibcLocales
    pytestCheckHook
  ]
  ++ lib.flatten (lib.attrValues optional-dependencies);

  enabledTestPaths = [ "tests" ];

  disabledTests = [
    # AssertionError: 'C:\\\\foo.bar\\\\baz' != 'C:\\foo.bar\\baz'
    "test_file_win"
  ];

  disabledTestPaths = [
    # requires swift config file
    "tests/contrib/test_swift_smoke.py"
  ];

  __darwinAllowLocalNetworking = true;

  pythonImportsCheck = [ "dulwich" ];

  meta = with lib; {
    description = "Implementation of the Git file formats and protocols";
    longDescription = ''
      Dulwich is a Python implementation of the Git file formats and protocols, which
      does not depend on Git itself. All functionality is available in pure Python.
    '';
    homepage = "https://www.dulwich.io/";
    changelog = "https://github.com/jelmer/dulwich/blob/dulwich-${src.tag}/NEWS";
    license = with licenses; [
      asl20
      gpl2Plus
    ];
    maintainers = with maintainers; [ koral ];
  };
}
