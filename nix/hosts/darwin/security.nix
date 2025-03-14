{ ... }: {
    security.sudo.extraConfig = ''
      %admin ALL=(root) NOPASSWD: ${pkgs.kanata}/bin/kanata" --cfg ${cfg.configPath} --nodelay
    '';
};
