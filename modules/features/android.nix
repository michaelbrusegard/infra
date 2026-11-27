{
  flake.modules.homeManager.android =
    {
      pkgs,
      lib,
      homePersistenceRoot ? null,
      ...
    }:
    let
      abi = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64-v8a" else "x86_64";
      image = "system-images;android-36;google_apis_playstore;${abi}";
      sdk =
        ((pkgs.androidenv.override { licenseAccepted = true; }).composeAndroidPackages {
          platformVersions = [ "36" ];
          includeEmulator = true;
          includeSystemImages = true;
          systemImageTypes = [ "google_apis_playstore" ];
          abiVersions = [ abi ];
        }).androidsdk;
      # T3 Code requires cmdline-tools/latest on an SSH device host, but the SDK
      # only has the versioned directory.
      root = pkgs.runCommand "android-sdk-root" { } ''
        mkdir -p $out/cmdline-tools
        for entry in ${sdk}/libexec/android-sdk/*; do
          [ "$(basename "$entry")" = cmdline-tools ] || ln -s "$entry" $out/
        done
        for version in ${sdk}/libexec/android-sdk/cmdline-tools/*; do
          ln -s "$version" $out/cmdline-tools/
          ln -s "$version" $out/cmdline-tools/latest
        done
      '';
    in
    {
      home = {
        # The SDK bundles its own e2fsprogs, which must not shadow the real one.
        packages = [ (lib.lowPrio sdk) ];
        # T3 Code reads this from the login shell to find adb and the emulator.
        sessionVariables = {
          ANDROID_HOME = "${root}";
          # avdmanager otherwise follows XDG_CONFIG_HOME, where the emulator
          # never looks.
          ANDROID_USER_HOME = "$HOME/.android";
        };

        # T3 Code only lists existing AVDs, and an AVD has to live outside the
        # store because the emulator writes to it.
        activation.androidAvd = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if ! ${root}/emulator/emulator -list-avds 2>/dev/null | grep -qx pixel; then
            echo no | run env ANDROID_USER_HOME="$HOME/.android" ${root}/cmdline-tools/latest/bin/avdmanager \
              create avd --name pixel --device pixel_9 --package '${image}'
          fi
        '';
      }
      // lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot}.directories = [ ".android" ];
      };
    };
}
