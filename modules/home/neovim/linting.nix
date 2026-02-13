{
  programs.neovim.spec.linting.keymaps = [
    {
      key = "<leader>cni";
      action = "<cmd>LintInfo<cr>";
      desc = "Lint Info";
    }
  ];
}
