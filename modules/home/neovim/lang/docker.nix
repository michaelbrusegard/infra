{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      dockerfile
    ];

    lsp.servers = {
      dockerls.package = pkgs.dockerfile-language-server;
      docker_compose_language_service.package = pkgs.docker-compose-language-service;
    };

    linting.filetypes = {
      dockerfile.hadolint.package = pkgs.hadolint;
    };
  };
}
