{ pkgs, lib, isWsl, ... }:

let
  mpvDarwin =
    pkgs.runCommand "mpv-homebrew-wrapper" { } ''
      mkdir -p $out/bin
      ln -s /opt/homebrew/bin/mpv $out/bin/mpv
    '';
in
{
  programs.mpv = lib.mkIf (!isWsl) {
    enable = true;

    package =
      if pkgs.stdenv.isDarwin then mpvDarwin else pkgs.mpv;

    config = {
      profile = "gpu-hq";
      vo = if pkgs.stdenv.isDarwin then "libmpv" else "gpu-next";
      hwdec = "auto-safe";

      scale = "ewa_lanczossharp";
      cscale = "ewa_lanczossharp";
      tscale = "oversample";

      video-sync = "display-resample";
      interpolation = true;

      audio-file-auto = "fuzzy";
      audio-channels = "stereo";

      volume = "80";
      volume-max = "200";

      sub-auto = "fuzzy";
      sub-file-paths = "sub:subtitles:Subtitles";

      osd-level = "1";
      osd-duration = "2000";
      osd-font-size = "32";

      screenshot-format = "png";
      screenshot-png-compression = "8";
      screenshot-directory = "$HOME/Pictures/screenshots";

      cache = "yes";
      cache-secs = "60";

      ytdl-format = "bestvideo[height<=?1080]+bestaudio/best";
    };

    bindings = {
      WHEEL_UP = "add volume 5";
      WHEEL_DOWN = "add volume -5";
      l = "seek 5";
      h = "seek -5";
      j = "seek -60";
      k = "seek 60";
    };
  };
}
