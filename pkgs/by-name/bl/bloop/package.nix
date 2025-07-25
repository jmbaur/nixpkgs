{
  stdenv,
  fetchurl,
  autoPatchelfHook,
  installShellFiles,
  makeWrapper,
  jre,
  lib,
  zlib,
}:

stdenv.mkDerivation rec {
  pname = "bloop";
  version = "2.0.10";

  platform =
    if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
      "x86_64-pc-linux"
    else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64 then
      "x86_64-apple-darwin"
    else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then
      "aarch64-apple-darwin"
    else
      throw "unsupported platform";

  bloop-bash = fetchurl {
    url = "https://github.com/scalacenter/bloop/releases/download/v${version}/bash-completions";
    sha256 = "sha256-2mt+zUEJvQ/5ixxFLZ3Z0m7uDSj/YE9sg/uNMjamvdE=";
  };

  bloop-fish = fetchurl {
    url = "https://github.com/scalacenter/bloop/releases/download/v${version}/fish-completions";
    sha256 = "sha256-eFESR6iPHRDViGv+Fk3sCvPgVAhk2L1gCG4LnfXO/v4=";
  };

  bloop-zsh = fetchurl {
    url = "https://github.com/scalacenter/bloop/releases/download/v${version}/zsh-completions";
    sha256 = "sha256-WNMsPwBfd5EjeRbRtc06lCEVI2FVoLfrqL82OR0G7/c=";
  };

  bloop-binary = fetchurl {
    url = "https://github.com/scalacenter/bloop/releases/download/v${version}/bloop-${platform}";
    sha256 =
      if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
        "sha256-GoWHVYIA98YMMmhYj1bBysABBq2UxEcELXqDi+XRnQ4="
      else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64 then
        "sha256-hE54Z2QLlAt4S+LQOAD0jLf1y2/PkKO9JAT2L6M8lWA="
      else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then
        "sha256-8gtaiSilf1yL50QSsy4K686R1J9W5NL1JyB7onMSTOw="
      else
        throw "unsupported platform";
  };

  dontUnpack = true;
  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;
  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    zlib
  ];
  propagatedBuildInputs = [ jre ];

  installPhase = ''
    runHook preInstall

    install -D -m 0755 ${bloop-binary} $out/.bloop-wrapped

    makeWrapper $out/.bloop-wrapped $out/bin/bloop

    #Install completions
    installShellCompletion --name bloop --bash ${bloop-bash}
    installShellCompletion --name _bloop --zsh ${bloop-zsh}
    installShellCompletion --name bloop.fish --fish ${bloop-fish}

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://scalacenter.github.io/bloop/";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    license = licenses.asl20;
    description = "Scala build server and command-line tool to make the compile and test developer workflows fast and productive in a build-tool-agnostic way";
    mainProgram = "bloop";
    platforms = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    maintainers = with maintainers; [
      agilesteel
      kubukoz
      tomahna
    ];
  };
}
