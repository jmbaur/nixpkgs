{
  buildPythonPackage,
  lib,
  netaddr,
  openvswitch,
  pyftpdlib,
  pyparsing,
  pytestCheckHook,
  pythonOlder,
  scapy,
  setuptools,
  tftpy,
}:

buildPythonPackage rec {
  pname = "ovs";
  inherit (openvswitch) src version;

  sourceRoot = "${openvswitch.name}/python";

  disabled = pythonOlder "3.8";

  build-system = [ setuptools ];

  buildInputs = [ openvswitch ];

  nativeCheckInputs = [
    pytestCheckHook
    netaddr
    pyftpdlib
    pyparsing
    scapy
    tftpy
  ];

  pythonImportsCheck = [ "ovs" ];

  meta = with lib; {
    description = "Python library for working with Open vSwitch";
    changelog = "https://www.openvswitch.org/releases/NEWS-${version}.txt";
    license = licenses.asl20;
    maintainers = with maintainers; [ jmbaur ];
  };
}
