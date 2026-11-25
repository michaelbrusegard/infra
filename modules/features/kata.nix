{
  flake.modules.nixos.kata =
    {
      lib,
      pkgs,
      ...
    }:
    let
      kata = pkgs.kata-runtime;
      cloudHypervisor = lib.getExe pkgs.cloud-hypervisor;
      virtiofsd = lib.getExe pkgs.virtiofsd;

      # The packaged Cloud Hypervisor config points at a hypervisor binary that
      # kata-runtime does not ship, and its virtiofsd allowlist names a different
      # build than the daemon it configures.
      overrides = (pkgs.formats.toml { }).generate "10-nixos.toml" {
        hypervisor.clh = {
          path = cloudHypervisor;
          valid_hypervisor_paths = [ cloudHypervisor ];
          virtio_fs_daemon = virtiofsd;
          valid_virtio_fs_daemon_paths = [ virtiofsd ];
        };
      };

      # Kata resolves symlinks before looking for config.d, so the base config and
      # its drop-in have to live in the same real directory.
      config = pkgs.runCommand "kata-config" { } ''
        mkdir -p $out/config.d
        cp ${kata}/share/defaults/kata-containers/configuration-clh.toml $out/configuration.toml
        cp ${overrides} $out/config.d/10-nixos.toml
      '';

      # k3s reads config.toml.tmpl as a containerd v2 template, which is all the
      # services.k3s.containerdConfigTemplate option can write. Use the v3 name.
      containerdTemplate = pkgs.writeText "config-v3.toml.tmpl" ''
        {{ template "base" . }}

        [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata]
          runtime_type = "io.containerd.kata.v2"
          runtime_path = "${kata}/bin/containerd-shim-kata-v2"
          privileged_without_host_devices = true

        [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata.options]
          ConfigPath = "${config}/configuration.toml"
      '';
    in
    {
      boot.kernelModules = [
        "vhost_vsock"
        "vhost_net"
      ];

      systemd.tmpfiles.settings."10-k3s-kata" = {
        "/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl"."L+".argument = "${
          containerdTemplate
        }";
      };

      # k3s renders the template only at startup.
      systemd.services.k3s.restartTriggers = [ containerdTemplate ];
    };
}
