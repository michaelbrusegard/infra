{ catppuccin, ... }: {
  console = {
    enable = true;
    font = "SF Mono";
    keyMap = "us";
    colors = [
      "${catppuccin.colors.mocha.base}"
      "${catppuccin.colors.mocha.red}"
      "${catppuccin.colors.mocha.green}"
      "${catppuccin.colors.mocha.yellow}"
      "${catppuccin.colors.mocha.blue}"
      "${catppuccin.colors.mocha.mauve}"
      "${catppuccin.colors.mocha.teal}"
      "${catppuccin.colors.mocha.text}"
      "${catppuccin.colors.mocha.surface0}"
      "${catppuccin.colors.mocha.peach}"
      "${catppuccin.colors.mocha.sapphire}"
      "${catppuccin.colors.mocha.rosewater}"
      "${catppuccin.colors.mocha.lavender}"
      "${catppuccin.colors.mocha.pink}"
      "${catppuccin.colors.mocha.sky}"
      "${catppuccin.colors.mocha.crust}"
    ];
  };
}
