{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pythonOlder,
  # build inputs
  tqdm,
  portalocker,
  boto3,
  # check inputs
  pytestCheckHook,
  torch,
}:
let
  pname = "iopath";
  version = "0.1.10";
in
buildPythonPackage {
  inherit pname version;
  format = "setuptools";

  disabled = pythonOlder "3.10";

  src = fetchFromGitHub {
    owner = "facebookresearch";
    repo = "iopath";
    tag = "v${version}";
    hash = "sha256-vJV0c+dCFO0wOHahKJ8DbwT2Thx3YjkNLVSpQv9H69g=";
  };

  propagatedBuildInputs = [
    tqdm
    portalocker
  ];

  nativeCheckInputs = [
    pytestCheckHook
    torch
  ];

  disabledTests = [
    # requires network access
    "test_download"
    "test_bad_args"
  ];

  disabledTestPaths = [
    # flakey
    "tests/async_torch_test.py"
    "tests/async_writes_test.py"
  ];

  pythonImportsCheck = [ "iopath" ];

  optional-dependencies = {
    aws = [ boto3 ];
  };

  meta = with lib; {
    description = "Python library that provides common I/O interface across different storage backends";
    homepage = "https://github.com/facebookresearch/iopath";
    changelog = "https://github.com/facebookresearch/iopath/releases/tag/v${version}";
    license = licenses.mit;
    maintainers = with maintainers; [ happysalada ];
  };
}
