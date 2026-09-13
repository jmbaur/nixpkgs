{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  makeSetupHook,
  poetry-core,
  attrs,
  immutables,
  prompt-toolkit,
  pyrsistent,
  typing-extensions,
  pygments,
  pytest,
  python,
  nix-update-script,
}:

let
  # Compiles a package's Basilisp namespaces at build time, so that nothing has
  # to be written next to their sources in the read-only store at runtime. Add
  # it to the `nativeBuildInputs` of any package shipping `.lpy` namespaces:
  #
  #   nativeBuildInputs = [ basilisp.precompileHook ];
  #   dependencies = [ basilisp ];
  #
  # Every namespace found under `$out/${python.sitePackages}` is compiled. Set
  # `basilispNamespaces` to compile a specific list instead, or
  # `dontUseBasilispPrecompile` to skip the phase. Skipping it is not fatal —
  # uncompiled namespaces are recompiled on every import instead of once here.
  precompileHook = makeSetupHook {
    name = "basilisp-precompile-hook";
    substitutions = {
      pythonInterpreter = python.pythonOnBuildForHost.interpreter;
      pythonSitePackages = python.sitePackages;
      precompileScript = ./precompile.py;
    };
  } ./precompile-hook.sh;
in
buildPythonPackage (finalAttrs: {
  pname = "basilisp";
  version = "0.5.1";
  pyproject = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "basilisp-lang";
    repo = "basilisp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3q5oWQ1IKVqToYJYogj5ubm0K/7RADRRIKGro2SAC5o=";
  };

  patches = [
    # Both fix the importer's handling of install prefixes it cannot write to,
    # which is every Basilisp package in the store. Not yet reported upstream.
    ./0001-importer-open-bytecode-caches-read-only.patch
    ./0002-importer-do-not-fail-imports-when-the-bytecode-cache.patch
  ];

  build-system = [ poetry-core ];

  nativeBuildInputs = [ precompileHook ];

  dependencies = [
    attrs
    immutables
    prompt-toolkit
    pyrsistent
    typing-extensions
  ];

  optional-dependencies = {
    pygments = [ pygments ];
    pytest = [ pytest ];
  };

  pythonImportsCheck = [
    "basilisp"
  ];

  passthru = {
    inherit precompileHook;
    updateScript = nix-update-script { };
  };

  meta = {
    description = "A Clojure-compatible(-ish) Lisp dialect hosted on Python 3 with seamless Python interop";
    homepage = "https://github.com/basilisp-lang/basilisp";
    changelog = "https://github.com/basilisp-lang/basilisp/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    license = lib.licenses.epl10;
    maintainers = [ lib.maintainers.jmbaur ];
  };
})
