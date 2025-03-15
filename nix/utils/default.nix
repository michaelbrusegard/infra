inputs:
{
  mkSystem = import ./mk-system.nix inputs;
  importDirsFrom = import ./import-dirs.nix inputs;
};
