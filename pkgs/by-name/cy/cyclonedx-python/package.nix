{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication rec {
  pname = "cyclonedx-python";
  version = "6.1.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "CycloneDX";
    repo = "cyclonedx-python";
    tag = "v${version}";
    hash = "sha256-hC+C85hdlHVhVcMLS9+gEvG+DohyxiBrjCApYnf6O/4=";
  };

  build-system = with python3Packages; [ poetry-core ];

  dependencies =
    with python3Packages;
    [
      chardet
      cyclonedx-python-lib
      packageurl-python
      pip-requirements-parser
      packaging
      tomli
    ]
    ++ cyclonedx-python-lib.optional-dependencies.validation;

  pythonImportsCheck = [ "cyclonedx" ];

  meta = {
    description = "Creates CycloneDX Software Bill of Materials (SBOM) from Python projects";
    homepage = "https://github.com/CycloneDX/cyclonedx-python";
    changelog = "https://github.com/CycloneDX/cyclonedx-python/releases/tag/${src.tag}";
    license = lib.licenses.asl20;
    teams = [ lib.teams.cyberus ];
    mainProgram = "cyclonedx-py";
  };
}
