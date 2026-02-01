_: {
  programs.mcp = {
    enable = true;
    servers = {
      ark-ui = {
        command = "bunx";
        args = [ "-y" "@ark-ui/mcp"];
      };
      shadcn = {
        command = "bunx";
        args = ["shadcn@latest" "mcp"];
      };
      tanstack = {
        command = "bunx";
        args = [ "-y" "@tanstack/cli" "mcp"];
      };
    };
  };
}
