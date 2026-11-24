{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "1.8.0";

  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-Rc6iHrXSZR1VFRtu0oXi7mzpJwPv8PwJm4Q1e69rLtY=";
    };
    x86_64-linux = {
      platform = "linux-x64-gnu";
      hash = "sha256-gOKS/Rva/KXFuEuwjKlRINeSh715E5+LaL0lPeThyDk=";
    };
    aarch64-linux = {
      platform = "linux-arm64-gnu";
      hash = "sha256-qqWxME9VrvzAFaqJ66q4OdUq68XEqAGTzZ6GNiMb45A=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
    or (throw "vite-plus: unsupported system ${stdenv.hostPlatform.system}");

  cliTarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-${source.platform}/-/vite-plus-cli-${source.platform}-${version}.tgz";
    inherit (source) hash;
  };
in
  stdenv.mkDerivation {
    pname = "vite-plus";
    inherit version;

    src = cliTarball;

    sourceRoot = ".";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall

      install -Dm755 package/vp "$out/bin/vp"

      runHook postInstall
    '';

    meta = {
      license = lib.licenses.mit;
      mainProgram = "vp";
      platforms = lib.attrNames sources;
    };
  }
