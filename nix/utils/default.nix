inputs:
{
  mkSystem = import ./mk-system.nix inputs;
  importDirs = import ./import-dirs.nix inputs;
};
