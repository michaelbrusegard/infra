{
  perSystem =
    { config, pkgs, ... }:
    {
      packages = {
        update-inputs = pkgs.writeShellApplication {
          name = "update-inputs";
          runtimeInputs = [
            pkgs.git
            pkgs.python3
          ];
          text = ''exec python3 -I ${../../packages/update-inputs/update_inputs.py} "$@"'';
        };

        update-gate = pkgs.writeShellApplication {
          name = "update-gate";
          runtimeInputs = [
            pkgs.jq
            pkgs.findutils
          ];
          text = ''
            nix fmt
            ${pkgs.lib.getExe config.packages.verify} "$@"
            servers=$(nix eval "$@" --json .#ci.hosts |
              jq -r '.[] | select(.deployed and .system == "${pkgs.stdenv.hostPlatform.system}") | ".#\(.attribute)"')
            if [[ -n $servers ]]; then
              xargs nix build "$@" --no-link <<<"$servers"
            fi
          '';
        };
      };
    };
}
