{
  buildPythonPackage,
  eventlet,
  fetchFromGitHub,
  lib,
  pbr,
  pytest-cov,
  pytestCheckHook,
  pythonOlder,
  setuptools,
}:

buildPythonPackage rec {
  pname = "beka";
  version = "0.4.2";

  PBR_VERSION = version;

  disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "faucetsdn";
    repo = "beka";
    rev = "refs/tags/${version}";
    hash = "sha256-cwavpuOyOvjQbBDYgdGmbJrTaNZ/nKP6jnNJrp+SfZo=";
  };

  build-system = [ setuptools ];

  dependencies = [ eventlet pbr ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-cov
  ];

  pythonImportsCheck = [ "beka" ];

  meta = with lib; {
    description = "A Python BGP Speaker";
    homepage = "https://github.com/faucetsdn/beka";
    changelog = "https://github.com/faucetsdn/beka/releases/tag/${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ jmbaur ];
  };
}
