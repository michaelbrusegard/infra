lib: dir: let
  entries = builtins.readDir dir;
  processEntry = name: type:
    if type == "regular" && lib.hasSuffix ".nix" name
    then {
      ${lib.removeSuffix ".nix" name} = import (dir + "/${name}");
    }
    else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix")
    then {
      ${name} = import (dir + "/${name}");
    }
    else {};
in
  builtins.foldl' (a: b: a // b) {} (lib.mapAttrsToList processEntry entries)
