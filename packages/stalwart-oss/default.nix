{
  lib,
  callPackage,
  rustPlatform,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  protobuf,
  openssl,
  sqlite,
  zstd,
  python3,
  patch,
  nativeScim ? false,
}: let
  nativeSources = lib.cleanSource ./native;
  sourceHook = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./apply-native.py ./patches/server];
  };
in
  rustPlatform.buildRustPackage (finalAttrs: {
    pname =
      if nativeScim
      then "stalwart-native-scim"
      else "stalwart-oss";
    version =
      if nativeScim
      then "0.16.21"
      else "0.16.17";

    src = fetchFromGitHub {
      owner = "stalwartlabs";
      repo = "stalwart";
      tag = "v${finalAttrs.version}";
      hash =
        if nativeScim
        then "sha256-EZ7cuHToVzs/pubGtvXRzgHjmJ8DV7OrIuXnlmQyy1s="
        else "sha256-tQY5L8tTyVbhIX0VrWbaKfR+Q97coTVoMRRDSHv5Lms=";
    };
    cargoHash =
      if nativeScim
      then "sha256-kDWeqY9Ye8tQXYrYNk0W6lhwvHk0Mk6Bkpdmua2UlPE="
      else "sha256-EUx/ELV85pdPKzv49SEQ1Q8e/4ism2x3ZrKPqL6uvoE=";

    postPatch = lib.optionalString nativeScim ''
      python3 resources/scripts/ossify.py .
      python3 ${sourceHook}/apply-native.py . ${nativeSources}
    '';

    # Upstream enables enterprise by default. Select storage explicitly; SQLite
    # is required by the edge's recipient directory, RocksDB by both servers.
    buildNoDefaultFeatures = true;
    buildFeatures = ["rocks" "sqlite"] ++ lib.optional nativeScim "independent-scim";
    # Tests select HTTP and services; storage features live on their dependency.
    checkFeatures =
      if nativeScim
      then ["store/rocks" "store/sqlite" "independent-scim"]
      else ["rocks" "sqlite"];
    cargoBuildFlags = ["--package" "stalwart"];
    cargoTestFlags =
      if nativeScim
      then ["--package" "http@${finalAttrs.version}" "--package" "services" "--package" "directory" "--lib" "independent_scim"]
      else ["--package" "stalwart"];
    nativeBuildInputs = [pkg-config protobuf rustPlatform.bindgenHook] ++ lib.optionals nativeScim [python3 patch];
    buildInputs = [openssl sqlite zstd];
    env =
      {
        OPENSSL_NO_VENDOR = "1";
        ZSTD_SYS_USE_PKG_CONFIG = "1";
      }
      # jemalloc otherwise probes the build CPU, producing different binaries
      # on 48- and 57-bit hosts. Its x86-64 cross-build default covers both.
      // lib.optionalAttrs (nativeScim && stdenv.hostPlatform.isx86_64) {
        JEMALLOC_SYS_WITH_LG_VADDR = "57";
      }
      // lib.optionalAttrs nativeScim {
        STALWART_NATIVE_WEBUI_ARCHIVE = callPackage ./webui.nix {};
      };

    meta = {
      description =
        if nativeScim
        then "Stalwart OSS with independently implemented native SCIM"
        else "Upstream Stalwart with Enterprise features disabled";
      homepage = "https://stalw.art/";
      license = lib.licenses.agpl3Only;
      mainProgram = "stalwart";
      platforms = lib.platforms.linux;
    };
  })
