{pkgs, ...}: {
  programs.neovim.spec.formatting = {
    enable = true;
    formatOnSave = true;

    formattersByFt = {
      nix = ["alejandra"];
      lua = ["stylua"];
      python = ["ruff_format"];
      sh = ["shfmt"];
    };

    formatters = {
      alejandra = {
        command = "${pkgs.alejandra}/bin/alejandra";
        package = pkgs.alejandra;
      };
      stylua = {
        command = "${pkgs.stylua}/bin/stylua";
        package = pkgs.stylua;
      };
      shfmt = {
        command = "${pkgs.shfmt}/bin/shfmt";
        package = pkgs.shfmt;
      };
      ruff_format = {
        command = "${pkgs.ruff}/bin/ruff";
        args = ["format" "--stdin-filename" "$FILENAME" "-"];
        package = pkgs.ruff;
      };
    };
  };
}
