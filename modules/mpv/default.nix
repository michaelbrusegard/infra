{ config, lib, pkgs, ... }:

let
  cfg = config.modules.mpv;
in {
  options.modules.mpv.enable = lib.mkEnableOption "Media player configuration";

  config = lib.mkIf cfg.enable {
    programs.mpv = {
      enable = true;
      config = {
        profile = "gpu-hq";
        vo = "gpu";
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
      scripts = with pkgs.mpvScripts; [
        sponsorblock
        uosc
        thumbfast
      ] ++ lib.optionals (!isDarwin) [
        mpris
      ];
    };
    catppuccin.mpv = {
      enable = true;
      accent = "blue";
    };
  };
}
