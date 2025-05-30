{
  lib,
  stdenv,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  setuptools,

  # dependencies
  cloudpickle,
  farama-notifications,
  numpy,
  typing-extensions,
  pythonOlder,
  importlib-metadata,

  # tests
  dill,
  flax,
  jax,
  jaxlib,
  matplotlib,
  mujoco,
  moviepy,
  opencv4,
  pybox2d,
  pygame,
  pytestCheckHook,
  scipy,
}:

buildPythonPackage rec {
  pname = "gymnasium";
  version = "1.1.1";

  pyproject = true;

  src = fetchFromGitHub {
    owner = "Farama-Foundation";
    repo = "gymnasium";
    tag = "v${version}";
    hash = "sha256-5uE6ANOxVCeV5GMDGG+0j5JY2t++jw+mZFFHGl+sTfw=";
  };

  build-system = [ setuptools ];

  dependencies = [
    cloudpickle
    farama-notifications
    numpy
    typing-extensions
  ] ++ lib.optionals (pythonOlder "3.10") [ importlib-metadata ];

  pythonImportsCheck = [ "gymnasium" ];

  nativeCheckInputs = [
    dill
    flax
    jax
    jaxlib
    matplotlib
    moviepy
    mujoco
    opencv4
    pybox2d
    pygame
    pytestCheckHook
    scipy
  ];

  # if `doCheck = true` on Darwin, `jaxlib` is evaluated, which is both
  # marked as broken and throws an error during evaluation if the package is evaluated anyway.
  # disabling checks on Darwin avoids this and allows the package to be built.
  # if jaxlib is ever fixed on Darwin, remove this.
  doCheck = !stdenv.hostPlatform.isDarwin;

  disabledTestPaths = [
    # Unpackaged `mujoco-py` (Openai's mujoco) is required for these tests.
    "tests/envs/mujoco/test_mujoco_custom_env.py"
    "tests/envs/mujoco/test_mujoco_rendering.py"
    "tests/envs/mujoco/test_mujoco_v5.py"

    # Rendering tests failing in the sandbox
    "tests/wrappers/vector/test_human_rendering.py"

    # These tests need to write on the filesystem which cause them to fail.
    "tests/utils/test_save_video.py"
    "tests/wrappers/test_record_video.py"
  ];

  preCheck = ''
    export SDL_VIDEODRIVER=dummy
  '';

  disabledTests = [
    # Fails since jax 0.6.0
    # Fixed on master https://github.com/Farama-Foundation/Gymnasium/commit/94019feee1a0f945b9569cddf62780f4e1a224a5
    # TODO: un-skip at the next release
    "test_all_env_api"
    "test_env_determinism_rollout"
    "test_jax_to_numpy_wrapper"
    "test_pickle_env"
    "test_roundtripping"

    # Succeeds for most environments but `test_render_modes[Reacher-v4]` fails because it requires
    # OpenGL access which is not possible inside the sandbox.
    "test_render_mode"
  ];

  meta = {
    description = "Standard API for reinforcement learning and a diverse set of reference environments (formerly Gym)";
    homepage = "https://github.com/Farama-Foundation/Gymnasium";
    changelog = "https://github.com/Farama-Foundation/Gymnasium/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ GaetanLepage ];
  };
}
