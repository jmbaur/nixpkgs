{
  lib,
  buildPythonPackage,
  fetchPypi,

  # build-system
  hatchling,

  # dependencies
  aiofiles,
  aiohttp,

  # tests
  mock,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "evolutionhttp";
  version = "0.0.19";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-VhWYhkrZVUDu1I6ZZTZlTUhNfpma29tEYBLoT7xBd1M=";
  };

  build-system = [ hatchling ];

  dependencies = [
    aiofiles
    aiohttp
  ];

  nativeCheckInputs = [
    mock
    pytestCheckHook
  ];

  pythonImportsCheck = [ "evolutionhttp" ];

  meta = with lib; {
    description = "HTTP client for controlling a Bryant Evolution HVAC system";
    homepage = "https://github.com/danielsmyers/evolutionhttp";
    license = licenses.asl20;
    maintainers = with maintainers; [ hexa ];
  };
}
