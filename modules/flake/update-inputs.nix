{
  perSystem =
    { pkgs, ... }:
    {
      packages.update-inputs = pkgs.writeShellApplication {
        name = "update-inputs";
        runtimeInputs = [
          pkgs.git
          pkgs.python3
        ];
        text = ''exec python3 -I ${../../packages/update-inputs/update_inputs.py} "$@"'';
      };
    };
}
