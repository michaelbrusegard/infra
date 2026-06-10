# No programs.localsend module in nix-darwin; macOS prompts for the
# firewall exception on first launch, so the package is enough.
{pkgs, ...}: {
  environment.systemPackages = [pkgs.localsend];
}
