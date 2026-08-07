{
  inputs,
  pkgs,
  ...
}: {
  environment.systemPackages = [
    pkgs.handy
    pkgs.wtype
  ];

  home-manager.sharedModules = [inputs.self.homeManagerModules.handy];

  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660"
  '';
}
