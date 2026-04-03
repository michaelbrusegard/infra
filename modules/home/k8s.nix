{
  pkgs,
  config,
  ...
}: {
  programs.k9s = {
    enable = true;
    settings = {
      k9s = {
        refreshRate = 2;
        logoless = true;
        crumbsless = true;
        readOnly = true;
        ui = {
          enableMouse = true;
          headFoot = true;
        };
      };
    };
  };

  home = {
    packages = with pkgs; [
      kubectl
      fluxcd
      kubernetes-helm
    ];
    sessionVariables.KUBECONFIG = config.secrets.home.kubeConfigFile;
  };
}
