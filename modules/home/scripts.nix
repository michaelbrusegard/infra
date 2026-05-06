{
  pkgs,
  lib,
  ...
}: let
  safeRm = pkgs.writeScriptBin "rm" ''
    #!${lib.getExe pkgs.zsh}
    if [ $# -eq 1 ] && [[ "$1" != -* ]]; then
      exec ${lib.getExe' pkgs.trash-cli "trash"} "$1"
    fi
    exec ${lib.getExe' pkgs.uutils-coreutils "uutils-rm"} "$@"
  '';

  toDnxhr = pkgs.writeScriptBin "to-dnxhr" ''
    #!${lib.getExe pkgs.zsh}
    convert_file() {
      local input_file="''$1"
      local dir="''$(${lib.getExe' pkgs.uutils-coreutils "uutils-dirname"} "''$input_file")"
      local base="''$(${lib.getExe' pkgs.uutils-coreutils "uutils-basename"} "''${input_file%.*}")"
      local output_file="''$dir/''$base"_dnxhr.mov
      if [ -f "''$output_file" ]; then
        echo "Skipping: '''$input_file' (output already exists)"
        return
      fi

      echo "Converting: '''$input_file'"
      echo "Output:     '''$output_file'"
      if ${lib.getExe pkgs.ffmpeg} -hide_banner -loglevel error -stats -nostdin -i "''$input_file" -c:v dnxhd -profile:v dnxhr_hq -c:a pcm_s16le -pix_fmt yuv422p "''$output_file"; then
        echo "✓ Conversion successful: ''$input_file"
      else
        echo "✗ Conversion failed: ''$input_file"
        return 1
      fi
    }

    process_path() {
      local path="''$1"
      if [ -f "''$path" ]; then
      if ${lib.getExe pkgs.file} -b --mime-type "''$path" | ${lib.getExe pkgs.ripgrep} -q "^video/"; then
        if [[ "''$path" == *"_dnxhr"* ]]; then
          echo "Skipping: '''$path' (already in DNxHR format)"
        else
          convert_file "''$path"
        fi
        else
          echo "Skipping: '''$path' (not a video file)"
        fi
      elif [ -d "''$path" ]; then
        echo "Processing directory: '''$path'"
        local count=0
        local failed=0
        while IFS= read -r -d ''$'\0' file; do
          if ${lib.getExe pkgs.file} -b --mime-type "''$file" | ${lib.getExe pkgs.ripgrep} -q "^video/"; then
            count=''$((count + 1))
            convert_file "''$file" || failed=''$((failed + 1))
          fi
        done < <(${lib.getExe' pkgs.findutils "find"} "''$path" -type f -print0)
        echo "Directory processing complete:"
        echo "- Total videos processed: ''$count"
        echo "- Successful: ''$((count - failed))"
        echo "- Failed: ''$failed"
      else
        echo "Error: '''$path' is not a valid file or directory"
        return 1
      fi
    }

    if [ -z "''$1" ]; then
      echo "Usage: ''$(basename ''$0) <input_path>"
      echo "Converts video(s) to DNxHR HQ MOV with PCM audio for DaVinci Resolve."
      echo ""
      echo "Input can be either:"
      echo "  - A single video file"
      echo "  - A directory (will process all video files recursively)"
      exit 1
    fi

    process_path "''$1"
  '';
in {
  home.packages = [
    safeRm
    toDnxhr
  ];
}
