{pkgs, ...}: {
  programs.neovim = {
    extraPackages = with pkgs; [
      ripgrep
      ast-grep
      fd
      grpcurl
      websocat
      ghostscript
      imagemagick
      mermaid-cli
      jq
      libxml2
    ];
    withNodeJs = true;
  };
}
