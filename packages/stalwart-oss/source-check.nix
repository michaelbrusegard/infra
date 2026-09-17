{
  lib,
  runCommand,
  python3,
  patch,
  server,
}: let
  edgePolicy = lib.cleanSourceWith {
    src = ../../gitops/espresso/apps/stalwart-edge;
    filter = path: type:
      if type == "directory"
      then baseNameOf path != "__pycache__"
      else lib.any (suffix: lib.hasSuffix suffix path) [".py" ".sql"];
  };
  source = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      if type == "directory"
      then baseNameOf path != "__pycache__"
      else lib.any (suffix: lib.hasSuffix suffix path) [".py" ".rs" ".patch"];
  };
in
  runCommand "stalwart-native-scim-source-check" {
    nativeBuildInputs = [python3 patch];
    STALWART_SOURCE_DIR = server.src;
  } ''
    python3 ${source}/test_packaging.py -v
    python3 ${source}/integration.py --self-test
    STALWART_RECONCILER_FILE=${../../gitops/espresso/apps/stalwart/reconciler.yaml} \
      python3 ${source}/test_retirement.py -v
    export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
    python3 ${edgePolicy}/test_policy.py -v
    python3 ${edgePolicy}/test_readiness.py -v
    python3 ${source}/test_edge_bootstrap.py -v
    PYTHONPATH=${source} python3 - <<'PY'
    import pathlib
    import unittest
    import edge
    edge.POLICY_PATH = pathlib.Path('${edgePolicy}/policy.py')
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromName('test_edge'))
    if not result.wasSuccessful():
        raise SystemExit(1)
    PY
    python3 -m py_compile \
      ${source}/mail.py ${source}/migration.py ${source}/identity.py ${source}/recovery.py \
      ${source}/rate_limit.py ${source}/routing.py ${source}/retirement.py \
      ${source}/edge.py ${source}/edge_bootstrap.py
    touch $out
  ''
