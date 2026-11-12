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
      then "1.0.3"
      else "0.16.17";

    src = fetchFromGitHub {
      owner = "stalwartlabs";
      repo = "stalwart";
      tag = "v${finalAttrs.version}";
      hash =
        if nativeScim
        then "sha256-4NUb6Peivb5yG4jZSKUSwYijoF4JTvw4+u2uvN4tGqU="
        else "sha256-tQY5L8tTyVbhIX0VrWbaKfR+Q97coTVoMRRDSHv5Lms=";
    };
    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (finalAttrs) pname version src;
      hash =
        if nativeScim
        then "sha256-QOdPdcCa5HxckfMiNkgnkGMuOlRGIfMMylQs7QUGI5Q="
        else "sha256-EUx/ELV85pdPKzv49SEQ1Q8e/4ism2x3ZrKPqL6uvoE=";
      # stalwartlabs deleted its opentelemetry-rust fork, but the commit 0.16
      # pins is upstream, so fetch it from there. v1 no longer depends on it.
      env = lib.optionalAttrs (!nativeScim) {
        GIT_CONFIG_COUNT = "1";
        GIT_CONFIG_KEY_0 = "url.https://github.com/open-telemetry/opentelemetry-rust.insteadOf";
        GIT_CONFIG_VALUE_0 = "https://github.com/stalwartlabs/opentelemetry-rust";
      };
    };

    postPatch = lib.optionalString nativeScim ''
      python3 resources/scripts/ossify.py .
      python3 ${sourceHook}/apply-native.py . ${nativeSources}
    '';

    # Upstream enables enterprise by default. Select storage explicitly; SQLite
    # is required by the edge's recipient directory, RocksDB by both servers.
    buildNoDefaultFeatures = true;
    buildFeatures = ["rocks" "sqlite"] ++ lib.optional nativeScim "independent-scim";
    # HTTP, services and directory tests select storage on their dependency.
    checkFeatures =
      if nativeScim
      then ["store/rocks" "store/sqlite" "independent-scim"]
      else ["rocks" "sqlite"];
    # mail-parser 1.0.1 declares rust-version 1.98 but builds with the pinned
    # 1.95 toolchain; the whole v1 workspace is checked with it.
    cargoBuildFlags = ["--package" "stalwart"] ++ lib.optional nativeScim "--ignore-rust-version";
    cargoTestFlags =
      if nativeScim
      then ["--ignore-rust-version" "--package" "http@${finalAttrs.version}" "--package" "directory" "--package" "services" "--package" "jmap" "--lib"]
      else ["--package" "stalwart"];
    checkFlags = lib.optionals nativeScim ["independent_scim" "catch_all_sender"];
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
