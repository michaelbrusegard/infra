{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types concatStringsSep mapAttrsToList optionalString filter;

  nvimLib = import ./lib.nix {inherit lib;};
  inherit (nvimLib) toLua;
in {
  options.programs.neovim = {
    options = mkOption {
      type = types.attrs;
      default = {};
    };

    globals = mkOption {
      type = types.attrs;
      default = {};
    };

    filetypes = mkOption {
      type = types.submodule {
        options = {
          extensions = mkOption {
            type = types.attrsOf types.str;
            default = {};
          };
          patterns = mkOption {
            type = types.attrsOf types.str;
            default = {};
          };
          filenames = mkOption {
            type = types.attrsOf types.str;
            default = {};
          };
        };
      };
      default = {};
    };
  };

  config.programs.neovim.extraLuaConfig = lib.mkOrder 100 ''
    ${concatStringsSep "\n" (mapAttrsToList (k: v: "vim.g.${k} = ${toLua v}") config.programs.neovim.globals)}
    ${concatStringsSep "\n" (mapAttrsToList (k: v: "vim.o.${k} = ${toLua v}") config.programs.neovim.options)}
    ${let
      ft = config.programs.neovim.filetypes;
      fields = filter (x: x != "") [
        (optionalString (ft.extensions != {}) "extension = ${toLua ft.extensions}")
        (optionalString (ft.patterns != {}) "pattern = ${toLua ft.patterns}")
        (optionalString (ft.filenames != {}) "filename = ${toLua ft.filenames}")
      ];
    in
      optionalString (fields != []) ''
        vim.filetype.add({
          ${concatStringsSep ",\n  " fields}
        })
      ''}
  '';
}
