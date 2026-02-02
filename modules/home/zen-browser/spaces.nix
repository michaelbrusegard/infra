_: {
  programs.zen-browser.profiles."default" = {
    spacesForce = true;
    spaces = {
      "Default" = {
        id = "540f99e5-b487-46f8-9b1a-a91796f0908e";
        icon = "";
        position = 0;
        theme = {
          type = "gradient";
          colors = [
            {
              red = 137;
              green = 180;
              blue = 250;
              algorithm = "floating";
              type = "explicit-lightness";
            }
            {
              red = 180;
              green = 190;
              blue = 254;
              algorithm = "floating";
              type = "explicit-lightness";
            }
          ];
          opacity = 0.7;
          texture = 0.3;
        };
      };
      "Work" = {
        id = "f85f6720-823b-47d2-b5a1-03c2fea59187";
        icon = "";
        position = 1;
        container = 1;
        theme = {
          type = "gradient";
          colors = [
            {
              red = 148;
              green = 226;
              blue = 213;
              algorithm = "floating";
              type = "explicit-lightness";
            }
            {
              red = 116;
              green = 199;
              blue = 236;
              algorithm = "floating";
              type = "explicit-lightness";
            }
          ];
          opacity = 0.7;
          texture = 0.3;
        };
      };
      "Manafish" = {
        id = "49f72204-7a80-4b4b-9c5c-99dfc81e0050";
        icon = "";
        position = 2;
        container = 2;
        theme = {
          type = "gradient";
          colors = [
            {
              red = 250;
              green = 179;
              blue = 135;
              algorithm = "floating";
              type = "explicit-lightness";
            }
            {
              red = 203;
              green = 166;
              blue = 247;
              algorithm = "floating";
              type = "explicit-lightness";
            }
          ];
          opacity = 0.7;
          texture = 0.3;
        };
      };
    };
  };
}
