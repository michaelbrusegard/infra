base:
let
  contents = builtins.readDir base;
  dirs = builtins.filter (name:
    contents.${name} == "directory" && 
    builtins.pathExists (base + "/${name}/default.nix")
  ) (builtins.attrNames contents);
in
map (name: base + "/${name}") dirs
