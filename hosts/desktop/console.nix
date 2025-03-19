{ catppuccin, ... }: {
  console = {
    enable = true;
    font = "SF Mono";
    keyMap = "us";
    colors = [
      "${catppuccin.flavors.mocha.base}"
      "${catppuccin.flavors.mocha.red}"
      "${catppuccin.flavors.mocha.green}"
      "${catppuccin.flavors.mocha.yellow}"
      "${catppuccin.flavors.mocha.blue}"
      "${catppuccin.flavors.mocha.mauve}"
      "${catppuccin.flavors.mocha.teal}"
      "${catppuccin.flavors.mocha.text}"
      "${catppuccin.flavors.mocha.surface0}"
      "${catppuccin.flavors.mocha.peach}"
      "${catppuccin.flavors.mocha.sapphire}"
      "${catppuccin.flavors.mocha.rosewater}"
      "${catppuccin.flavors.mocha.lavender}"
      "${catppuccin.flavors.mocha.pink}"
      "${catppuccin.flavors.mocha.sky}"
      "${catppuccin.flavors.mocha.crust}"
    ];
  };
}
