{ utils, ... }:

{
  imports =
    utils.importDirsFrom ./programs ++
    utils.importDirsFrom ./terminal;
}
