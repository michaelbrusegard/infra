{pkgs, ...}: let
  fetchSpell = lang: type: hash:
    pkgs.fetchurl {
      url = "https://ftp.nluug.nl/pub/vim/runtime/spell/${lang}.utf-8.${type}";
      sha256 = hash;
    };
in {
  xdg.configFile = {
    "nvim/spell/nb.utf-8.spl".source = fetchSpell "nb" "spl" "1kzz8fr6fi18499m3qnidw9xrv0mnbpyi3p3nx5lynms33rai29w";
    "nvim/spell/nb.utf-8.sug".source = fetchSpell "nb" "sug" "0a0yw7bfzcn7j7wmxy90cpj1hdzkj63w51g9xf5vj1vfdws0cmq6";
  };
}
