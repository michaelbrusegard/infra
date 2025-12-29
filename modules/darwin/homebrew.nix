{ config, inputs, ... }:

{
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = config.users.primaryUser;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "michaelbrusegard/homebrew-extras" = inputs.homebrew-extras;
      "homebrew-zathura/homebrew-zathura" = inputs.homebrew-zathura;
    };
    mutableTaps = false;
  };
  homebrew = {
    enable = true;
    caskArgs.no_quarantine = true;
    global.brewfile = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    taps = builtins.attrNames config.nix-homebrew.taps;
    casks = [
      "jordanbaird-ice"
      "yabai-indicator"
      "linearmouse"
      "aldente"
      "breaktimer"
      "stolendata-mpv"
      "zathura-cb"
      "zathura-djvu"
      "zathura-pdf-poppler"
      "zathura-ps"
      "altserver"
      "ghostty"
      "vivaldi"
      "burp-suite"
      "element"
      "slack"
      "legcord"
      "obsidian"
      "proton-pass"
      "proton-mail"
      "protonvpn"
      "proton-drive"
      "libreoffice"
      "transmission"
      "inkscape"
      "gimp"
      "scribus"
      "affinity"
      "blender"
      "freecad"
      "orcaslicer"
      "bambu-studio"
      "betaflight-configurator"
      "qgis"
      "notion"
      "audacity"
    ];
    masApps = {
      "Amphetamine" = 937984704;
      "BrightIntosh" = 6452471855;
      "Proton Pass for Safari" = 6502835663;
      "Wipr" = 1662217862;
      "WireGuard" = 1451685025;
      "Keynote" = 409183694;
      "Pages" = 409201541;
      "Numbers" = 409203825;
      "Developer" = 640199958;
      "Xcode" = 497799835;
      "DaVinci Resolve" = 571213070;
    };
  };
  system.activationScripts.zathura.text = ''
    ZATHURA_PREFIX="$(brew --prefix zathura 2>/dev/null || true)"
    [ -z "$ZATHURA_PREFIX" ] && exit 0

    PLUGIN_DIR="$ZATHURA_PREFIX/lib/zathura"
    mkdir -p "$PLUGIN_DIR"

    for plugin in cb djvu pdf-poppler ps; do
      P="$(brew --prefix zathura-$plugin 2>/dev/null)/lib/lib$plugin.dylib"
      [ -f "$P" ] && ln -sf "$P" "$PLUGIN_DIR/"
    done

    curl -fsSL https://raw.githubusercontent.com/homebrew-zathura/homebrew-zathura/master/convert-into-app.sh | sh || true
  '';
}
