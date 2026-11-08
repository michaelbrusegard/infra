{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
}: let
  # The provider is generated from the schema the server serves at
  # /api/schema. Use the enterprise schema: it is a superset of the OSS one,
  # so objects and fields our build exposes as non-enterprise (SCIM) exist.
  stalwartVersion = "1.0.3";
  schema = fetchurl {
    url = "https://raw.githubusercontent.com/stalwartlabs/stalwart/v${stalwartVersion}/resources/schema/schema.json.gz";
    hash = "sha256-2J8FTUsaoyWdFbeGSOr2GxvRP77nkpn6tjPCrSqkg3I=";
  };
in
  buildGoModule {
    pname = "terraform-provider-stalwart";
    # Versioned after the Stalwart release whose schema it is generated from.
    version = stalwartVersion;

    src = fetchFromGitHub {
      owner = "tahacodes";
      repo = "terraform-provider-stalwart";
      rev = "f7d85b3c5b0c8b2fafd31320f0476464584c8b8a";
      hash = "sha256-QwYJdZ1IZz2hS+HC6wm4W6cfKhS0RCYgJzSbPgS3aFs=";
    };
    vendorHash = "sha256-lrSV8cm6G8/FhvN9C/1wqozuxxcsBGypBdFZ18VQPdU=";

    patches = [
      ./patches/0001-fix-generator-target-stalwart-v1.0.3-schema.patch
      ./patches/0002-fix-client-retire-idle-connections.patch
      ./patches/0003-test-run-acceptance-against-stalwart-v1.0.3.patch
      ./patches/0004-fix-provider-never-write-a-masked-secret-back.patch
    ];

    # Upstream commits code generated from its v0.16 schema; regenerate it.
    # The generator needs vendored modules, which the module fetch, which
    # inherits preBuild, does not have yet.
    preBuild = ''
      gzip -dc ${schema} > schema/v${stalwartVersion}.json
      go run ./tools/generator schema/v${stalwartVersion}.json \
        internal/provider/generated.go internal/provider/generated_datasources.go
    '';
    overrideModAttrs = {preBuild = "";};

    subPackages = ["."];
    ldflags = ["-s" "-w" "-X main.version=${stalwartVersion}"];
    # OpenTofu runs the binary from a provider mirror, outside its closure.
    env.CGO_ENABLED = "0";

    # Acceptance tests skip without TF_ACC and a live server.
    checkPhase = ''
      runHook preCheck
      go test ./...
      runHook postCheck
    '';

    meta = {
      description = "OpenTofu provider for the Stalwart ${stalwartVersion} JMAP management API";
      homepage = "https://github.com/tahacodes/terraform-provider-stalwart";
      license = lib.licenses.mit;
      mainProgram = "terraform-provider-stalwart";
    };
  }
