{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types concatStringsSep mapAttrsToList optionalString filter;
  genLua = lib.generators.toLua {};
  cfg = config.programs.neovim.spec;
in {
  options.programs.neovim.spec = {
    globals = mkOption { type = types.attrs; default = {}; };
    options = mkOption { type = types.attrs; default = {}; };
    filetypes = mkOption {
      type = types.submodule {
        options = {
          extensions = mkOption { type = types.attrsOf types.str; default = {}; };
          patterns = mkOption { type = types.attrsOf types.str; default = {}; };
          filenames = mkOption { type = types.attrsOf types.str; default = {}; };
        };
      };
      default = {};
    };
  };

  config.programs.neovim.extraLuaConfig = lib.mkMerge [
    (lib.mkOrder 50 ''
      ${concatStringsSep "\n" (mapAttrsToList (k: v: "vim.g.${k} = ${genLua v}") cfg.globals)}
    '')

    (lib.mkOrder 200 ''
      ${concatStringsSep "\n" (mapAttrsToList (k: v: "vim.o.${k} = ${genLua v}") cfg.options)}
      ${let
        ft = cfg.filetypes;
        fields = filter (x: x != "") [
          (optionalString (ft.extensions != {}) "extension = ${genLua ft.extensions}")
          (optionalString (ft.patterns != {}) "pattern = ${genLua ft.patterns}")
          (optionalString (ft.filenames != {}) "filename = ${genLua ft.filenames}")
        ];
      in if fields != [] then "vim.filetype.add({ ${concatStringsSep ", " fields} })" else ""}
    '')
  ];
}
