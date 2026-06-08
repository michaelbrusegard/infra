{
  lib,
  pkgs,
  ...
}:
lib.mkIf pkgs.stdenv.isLinux {
  programs.wezterm.extraConfig = lib.mkOrder 400 ''
    do
      local passthrough = {}
      for c = string.byte('a'), string.byte('z') do
        table.insert(passthrough, string.char(c))
      end
      for c = string.byte('0'), string.byte('9') do
        table.insert(passthrough, string.char(c))
      end
      for _, sym in ipairs({ ' ', '[', ']', '\\', '-', '/', '_', '^' }) do
        table.insert(passthrough, sym)
      end
      for _, key in ipairs({
        'LeftArrow', 'RightArrow', 'UpArrow', 'DownArrow',
        'Backspace', 'Delete', 'Enter',
      }) do
        table.insert(passthrough, key)
      end

      for _, key in ipairs(passthrough) do
        table.insert(config.keys, {
          key = key,
          mods = 'SUPER',
          action = wezterm.action.SendKey({ key = key, mods = 'CTRL' }),
        })
      end
    end
  '';
}
