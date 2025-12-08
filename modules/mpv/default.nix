{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.mpv;
in {
  options.modules.mpv.enable = lib.mkEnableOption "Media player configuration";

  config = lib.mkIf cfg.enable {
    programs.mpv = {
      enable = true;
      package = if isDarwin then
        (pkgs.runCommand "mpv" {} ''
          mkdir -p $out/bin
          ln -s /opt/homebrew/bin/mpv $out/bin/mpv
        '')
      else
        pkgs.mpv;
      config = {
        profile = "gpu-hq";
        vo = if isDarwin then "libmpv" else "gpu-next";
        hwdec = "auto-safe";
        scale = "ewa_lanczossharp";
        cscale = "ewa_lanczossharp";
        video-sync = "display-resample";
        interpolation = true;
        tscale = "oversample";
        audio-file-auto = "fuzzy";
        audio-channels = "stereo";
        volume-max = "200";
        volume = "80";
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
    catppuccin.mpv.enable = true;
  };
}
