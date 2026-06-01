# nixpkgs 26.05's firefox wrapper emits an unquoted
# `touch $out/Applications/<App Name>.app/.../is-packaged-app`, which breaks
# under bash when the app name contains shell metacharacters (e.g. zen's
# "Zen Browser (Beta)") on darwin. Quote the path until the stable channel
# picks up the upstream fix.
_: prev:
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  wrapFirefox = browser: args: let
    wrapped = prev.wrapFirefox browser args;
  in
    wrapped.overrideAttrs (old: {
      buildCommand =
        builtins.replaceStrings
        ["\ntouch $out/" "/is-packaged-app\n"]
        ["\ntouch \"$out/" "/is-packaged-app\"\n"]
        old.buildCommand;
    });
}
