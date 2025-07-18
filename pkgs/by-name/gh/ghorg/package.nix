{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
}:

buildGoModule rec {
  pname = "ghorg";
  version = "1.11.3";

  src = fetchFromGitHub {
    owner = "gabrie30";
    repo = "ghorg";
    rev = "v${version}";
    sha256 = "sha256-SddkIZCnV6qPFFuFvV8I9P00C6oSKV32Xs6beAYvgs8=";
  };

  doCheck = false;
  vendorHash = null;

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  nativeBuildInputs = [ installShellFiles ];
  postInstall = ''
    installShellCompletion --cmd ghorg \
      --bash <($out/bin/ghorg completion bash) \
      --fish <($out/bin/ghorg completion fish) \
      --zsh <($out/bin/ghorg completion zsh)
  '';

  meta = with lib; {
    description = "Quickly clone an entire org/users repositories into one directory";
    longDescription = ''
      ghorg allows you to quickly clone all of an orgs, or users repos into a
      single directory. This can be useful in many situations including
      - Searching an orgs/users codebase with ack, silver searcher, grep etc..
      - Bash scripting
      - Creating backups
      - Onboarding
      - Performing Audits
    '';
    homepage = "https://github.com/gabrie30/ghorg";
    license = licenses.asl20;
    maintainers = with maintainers; [ vidbina ];
    mainProgram = "ghorg";
  };
}
