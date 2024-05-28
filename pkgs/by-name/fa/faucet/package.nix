{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "faucet";
  version = "1.10.11";

  PBR_VERSION = version;

  src = fetchFromGitHub {
    owner = "faucetsdn";
    repo = "faucet";
    rev = version;
    hash = "sha256-yGak85wv7gp0s7c/OVmmR8JgR8dj7P2y77IPJTFJD1k=";
  };

  # doesn't do anything
  postPatch = ''
    sed -i '/python3-fakencclient/d' requirements.txt
  '';

  nativeBuildInputs = with python3.pkgs; [
    pythonRelaxDepsHook
    setuptools
    wheel
  ];

  # TODO(jared): we shouldn't have to do this
  pythonRelaxDeps = [
    "os_ken"
  ];

  propagatedBuildInputs = with python3.pkgs; [
    beka
    chewie
    eventlet
    influxdb
    networkx
    os-ken
    pbr
    prometheus-client
    pytricia
    ruamel-yaml
  ];

  pythonImportsCheck = [ "faucet" ];

  meta = with lib; {
    description = "FAUCET is an OpenFlow controller for multi table OpenFlow 1.3 switches, that implements layer 2 switching, VLANs, ACLs, and layer 3 IPv4 and IPv6 routing";
    homepage = "https://github.com/faucetsdn/faucet";
    license = licenses.asl20;
    maintainers = with maintainers; [ jmbaur ];
    mainProgram = "faucet";
  };
}
