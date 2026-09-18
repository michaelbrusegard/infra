{
  lib,
  runCommand,
  bash,
  python3,
  shellcheck,
}: let
  source = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      type
      == "directory"
      || lib.any (suffix: lib.hasSuffix suffix path) [".sh" ".py" ".cf"];
  };
in
  runCommand "smtp-edge-source-check" {
    nativeBuildInputs = [bash python3 shellcheck];
  } ''
    cp -r ${source} source
    chmod -R u+w source
    cd source
    bash -n deliver.sh entrypoint.sh
    shellcheck deliver.sh entrypoint.sh
    python3 -B -m unittest discover -p 'test_*.py'
    python3 -m py_compile qualify.py qualify_postfix.py
    touch $out
  ''
