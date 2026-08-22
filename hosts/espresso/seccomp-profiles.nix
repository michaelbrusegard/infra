{
  inputs,
  pkgs,
  ...
}: let
  chromiumSeccompProfile =
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.chromium-seccomp-profile;
in {
  # Chromium creates user and PID namespaces, then chroots the sandbox process.
  # Start with containerd's default profile and permit only those setup calls.
  systemd.tmpfiles.rules = [
    "d /var/lib/kubelet/seccomp/hermes 0755 root root -"
    "C+ /var/lib/kubelet/seccomp/hermes/chromium.json 0444 root root - ${chromiumSeccompProfile}"
  ];
}
