{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
  in {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        age
        ast-grep
        bind
        fluxcd
        git
        go
        imapsync
        jq
        kubectl
        kubernetes-helm
        kustomize
        kubeconform
        opentofu
        (python3.withPackages (pythonPackages: [
          pythonPackages.requests
          pythonPackages.websocket-client
        ]))
        sops
        yq-go
      ];
    };
  };
}
