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
      else lib.any (suffix: lib.hasSuffix suffix path) [".py" ".rs" ".patch"];
  };
in
  runCommand "stalwart-native-scim-source-check" {
    nativeBuildInputs = [python3 patch];
    STALWART_SOURCE_DIR = server.src;
  } ''
    python3 ${source}/test_packaging.py -v
    python3 ${source}/integration.py --self-test
    PYTHONPYCACHEPREFIX="$TMPDIR/pycache" python3 -m py_compile \
      ${source}/mail.py ${source}/identity.py ${source}/recovery.py
    touch $out
  ''
