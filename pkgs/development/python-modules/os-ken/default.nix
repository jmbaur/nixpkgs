{
  buildPythonPackage,
  coverage,
  eventlet,
  fetchFromGitHub,
  hacking,
  lib,
  msgpack,
  ncclient,
  netaddr,
  oslo-config,
  oslotest,
  ovs,
  packaging,
  pbr,
  pycodestyle,
  pylint,
  pytest-cov,
  pytestCheckHook,
  python-subunit,
  pythonOlder,
  routes,
  setuptools,
  stestr,
  testscenarios,
  testtools,
  webob,
}:

buildPythonPackage rec {
  pname = "os-ken";
  version = "2.8.1";

  PBR_VERSION = version;

  disabled = pythonOlder "3.8";


  src = fetchFromGitHub {
    owner = "openstack";
    repo = "os-ken";
    rev = "refs/tags/${version}";
    hash = "sha256-kOf4bzZoKiVpwGKdxUFAFb+ZC1c9sDr1yIp2hiW21J4=";
  };

  patches = [ ./version.patch ];

  build-system = [ setuptools ];

  propagatedBuildInputs = [ pbr ];

  dependencies = [
    eventlet
    msgpack
    ncclient
    netaddr
    oslo-config
    ovs
    packaging
    routes
    webob
  ];

  nativeCheckInputs = [
    coverage
    hacking
    oslotest
    pycodestyle
    pylint
    pytest-cov
    pytestCheckHook
    python-subunit
    stestr
    testscenarios
    testtools
  ];

  # TODO(jared): why do these fail?
  disabledTests = [ "test_parser" ];

  pythonImportsCheck = [ "os_ken" ];

  meta = with lib; {
    description = "A component-based software defined networking framework for OpenStack";
    homepage = "https://github.com/openstack/os-ken";
    license = licenses.asl20;
    maintainers = with maintainers; [ jmbaur ];
  };
}
