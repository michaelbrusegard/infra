{
  perSystem = { pkgs, ... }: {
    packages = {
      diff-hosts = pkgs.writeShellApplication {
        name = "diff-hosts";
        runtimeInputs = [
          pkgs.git
          pkgs.python3
        ];
        text = ''exec python3 -I ${../../packages/review-diff/hosts.py} "$@"'';
      };

      diff-manifests = pkgs.writeShellApplication {
        name = "diff-manifests";
        runtimeInputs = [
          pkgs.git
          pkgs.kustomize
          pkgs.python3
          pkgs.yq-go
        ];
        text = ''exec python3 -I ${../../packages/review-diff/manifests.py} "$@"'';
      };
    };
  };
}
