{ colors, ... }: {
  console = {
    enable = true;
    font = "SF Mono";
    keyMap = "us";
    colors = [
      "${colors.mocha.base}"
      "${colors.mocha.red}"
      "${colors.mocha.green}"
      "${colors.mocha.yellow}"
      "${colors.mocha.blue}"
      "${colors.mocha.mauve}"
      "${colors.mocha.teal}"
      "${colors.mocha.text}"
      "${colors.mocha.surface0}"
      "${colors.mocha.peach}"
      "${colors.mocha.sapphire}"
      "${colors.mocha.rosewater}"
      "${colors.mocha.lavender}"
      "${colors.mocha.pink}"
      "${colors.mocha.sky}"
      "${colors.mocha.crust}"
    ];
  };
}
