{pkgs}:
pkgs.writeShellApplication {
  name = "slack";
  runtimeInputs = with pkgs; [
    curl
    jq
    coreutils
    gnused
  ];
  text = builtins.readFile ./slack.sh;
}
