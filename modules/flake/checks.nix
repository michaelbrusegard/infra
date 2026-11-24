{inputs, ...}: {
  # Stalwart takes over an hour to compile on a hosted runner, so its build
  # runs in the Stalwart Image workflow, a required check. The source check
  # reads only the patched source.
  perSystem = {
    config,
    pkgs,
    lib,
    ...
  }: {
    checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      inherit (config.packages) ai-images;
      smtp-edge = pkgs.callPackage ../../packages/smtp-edge/source-check.nix {};
      smtp-backup = pkgs.callPackage ../../packages/smtp-backup/test.nix {
        smtpBackupModule = inputs.self.modules.nixos.smtp-backup;
      };
      stalwart-native-scim-source = pkgs.callPackage ../../packages/stalwart-oss/source-check.nix {
        server = config.packages.stalwart-native-scim;
      };
    };
  };
}
