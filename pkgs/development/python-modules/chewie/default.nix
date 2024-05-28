{
  beka,
  buildPythonPackage,
  eventlet,
  fetchFromGitHub,
  lib,
  pbr,
  pytest-cov,
  pytestCheckHook,
  pythonOlder,
  setuptools,
  transitions,
}:

buildPythonPackage rec {
  pname = "chewie";
  version = "0.0.25";

  PBR_VERSION = version;

  disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "faucetsdn";
    repo = "chewie";
    rev = "refs/tags/${version}";
    hash = "sha256-mMaGvA+IwA7l69aAWLGjPDOn1UEH2912cGystqdxeX0=";
  };

  build-system = [ setuptools ];

  dependencies = [
    beka
    eventlet
    pbr
    transitions
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-cov
  ];

  pytestFlagsArray = [
    "test/"
    "--ignore=test/integration"
  ];

  pythonImportsCheck = [ "beka" ];

  meta = with lib; {
    description = "A python 802.1x daemon";
    homepage = "https://github.com/faucetsdn/chewie";
    changelog = "https://github.com/faucetsdn/chewie/releases/tag/${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ jmbaur ];
  };
}
