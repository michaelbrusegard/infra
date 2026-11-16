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
}: let
  nativeSources = lib.cleanSource ./native;
  sourceHook = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./apply-native.py ./patches/server];
  };
in
  rustPlatform.buildRustPackage (finalAttrs: {
    pname = "stalwart-native-scim";
    version = "1.0.3";

    src = fetchFromGitHub {
      owner = "stalwartlabs";
      repo = "stalwart";
      tag = "v${finalAttrs.version}";
      hash = "sha256-4NUb6Peivb5yG4jZSKUSwYijoF4JTvw4+u2uvN4tGqU=";
    };
    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (finalAttrs) pname version src;
      hash = "sha256-QOdPdcCa5HxckfMiNkgnkGMuOlRGIfMMylQs7QUGI5Q=";
    };

    postPatch = ''
      python3 resources/scripts/ossify.py .
      python3 ${sourceHook}/apply-native.py . ${nativeSources}
    '';

    # Upstream enables enterprise by default. Select storage explicitly; SQLite
    # is required by the edge's recipient directory, RocksDB by both servers.
    buildNoDefaultFeatures = true;
    buildFeatures = ["rocks" "sqlite" "independent-scim"];
    # HTTP, services and directory tests select storage on their dependency.
    checkFeatures = ["store/rocks" "store/sqlite" "independent-scim"];
    # mail-parser 1.0.1 declares rust-version 1.98 but builds with the pinned
    # 1.95 toolchain; the whole v1 workspace is checked with it.
    cargoBuildFlags = ["--package" "stalwart" "--ignore-rust-version"];
    cargoTestFlags = ["--ignore-rust-version" "--package" "http@${finalAttrs.version}" "--package" "directory" "--package" "services" "--package" "jmap" "--lib"];
    checkFlags = ["independent_scim" "catch_all_sender"];
    nativeBuildInputs = [pkg-config protobuf rustPlatform.bindgenHook python3 patch];
    buildInputs = [openssl sqlite zstd];
    env =
      {
        OPENSSL_NO_VENDOR = "1";
        ZSTD_SYS_USE_PKG_CONFIG = "1";
        STALWART_NATIVE_WEBUI_ARCHIVE = callPackage ./webui.nix {};
      }
      # jemalloc otherwise probes the build CPU, producing different binaries
      # on 48- and 57-bit hosts. Its x86-64 cross-build default covers both.
      // lib.optionalAttrs stdenv.hostPlatform.isx86_64 {
        JEMALLOC_SYS_WITH_LG_VADDR = "57";
      };

    meta = {
      description = "Stalwart OSS with independently implemented native SCIM";
      homepage = "https://stalw.art/";
      license = lib.licenses.agpl3Only;
      mainProgram = "stalwart";
      platforms = lib.platforms.linux;
    };
  })
