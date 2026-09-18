{
  lib,
  runCommand,
  python3,
  patch,
  server,
}: let
  source = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      if type == "directory"
      then baseNameOf path != "__pycache__"
      else lib.any (suffix: lib.hasSuffix suffix path) [".py" ".rs" ".patch" ".sieve"];
  };
in
  runCommand "stalwart-native-scim-source-check" {
    nativeBuildInputs = [python3 patch];
    STALWART_SOURCE_DIR = server.src;
  } ''
    python3 ${source}/test_packaging.py -v
    python3 ${source}/integration.py --self-test
    STALWART_RECONCILER_FILE=${./fixtures/legacy-reconciler.yaml} \
      python3 ${source}/test_retirement.py -v
    export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
    python3 ${source}/test_smtp_fixture.py -v
    python3 -m py_compile \
      ${source}/mail.py ${source}/migration.py ${source}/identity.py ${source}/recovery.py \
      ${source}/rate_limit.py ${source}/routing.py ${source}/retirement.py \
      ${source}/smtp_fixture.py ${source}/edge_dns.py
    touch $out
  ''
