{ inputs, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    let
      actionlintConfig = (pkgs.formats.yaml { }).generate "actionlint.yaml" {
        self-hosted-runner.labels = [ "ubuntu-26.04" ];
        paths =
          pkgs.lib.genAttrs
            [
              ".github/workflows/smtp-edge-image.yaml"
              ".github/workflows/stalwart-image.yaml"
              ".github/workflows/stalwart-provider-image.yaml"
            ]
            (_: {
              ignore = [ "SC2016" ];
            });
      };
    in
    {
      treefmt = {
        projectRootFile = "flake.nix";
        settings = {
          global.excludes = [ "gitops/espresso/flux-system/**" ];
          formatter = {
            actionlint.options = [
              "-config-file"
              "${actionlintConfig}"
            ];
            yamlfmt.excludes = [ "gitops/espresso/apps/smtp-edge/network-policy.yaml" ];
          };
        };
        programs = {
          nixfmt.enable = true;
          statix.enable = true;
          deadnix.enable = true;
          terraform.enable = true;
          actionlint.enable = true;
          yamlfmt = {
            enable = true;
            settings.formatter = {
              type = "basic";
              retain_line_breaks_single = true;
              scan_folded_as_literal = true;
            };
          };
        };
      };
    };
}
