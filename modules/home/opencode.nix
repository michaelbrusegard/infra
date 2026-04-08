{pkgs, ...}: {
  programs.opencode = {
    enable = true;
    settings = {
      autoupdate = false;
      theme = "catppuccin";
      plugin = ["oh-my-opencode" "@simonwjackson/opencode-direnv"];
    };
  };
  home.packages = with pkgs; [
    opencode-desktop
  ];
}
