_: {
  programs.zen-browser.profiles."default" = {
    containersForce = true;
    containers = {
      Work = {
        color = "orange";
        icon = "briefcase";
        id = 1;
      };
      Manafish = {
        color = "blue";
        icon = "dollar";
        id = 2;
      };
    };
  };
}
