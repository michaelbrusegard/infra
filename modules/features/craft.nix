{
  flake.modules.homeManager.craft =
    {
      config,
      lib,
      pkgs,
      isWsl,
      homePersistenceRoot ? null,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin;
      onLinux = pkgs.stdenv.hostPlatform.isLinux && !isWsl;
      enable = onLinux || isDarwin;

      apps = {
        deckcraft = "DeckCraft";
        designcraft = "DesignCraft";
        effectcraft = "EffectCraft";
        filmcraft = "FilmCraft";
        gridcraft = "GridCraft";
        lightcraft = "LightCraft";
        pdfcraft = "PdfCraft";
        photocraft = "PhotoCraft";
        solidcraft = "SolidCraft";
        soundcraft = "SoundCraft";
        vectorcraft = "VectorCraft";
        wordcraft = "WordCraft";
      };
      cli = app: if isDarwin then pkgs."${app}-cli" else pkgs.${app};

      # What the gateway may start. It reads this list before every call and
      # serves nothing while the file is absent, which makes the file the
      # switch: agents keep one small entry and the apps stay out of context
      # until asked for.
      everyApp = pkgs.writeText "craft-agents-apps.json" (
        builtins.toJSON {
          version = 1;
          apps =
            lib.mapAttrsToList (id: name: {
              inherit id name;
              command = "${cli id}/bin/${id}-cli";
              args = [ "mcp" ];
            }) apps
            ++ [
              {
                id = "blender";
                name = "Blender";
                command = lib.getExe pkgs.blender-mcp;
                args = [ ];
              }
            ];
        }
      );

      # Blender's server talks to an add-on inside the running Blender. The
      # add-on reads its settings from the saved preferences, so it has to be
      # enabled there, and only once the extension repositories are loaded.
      blender = if isDarwin then pkgs.brewCasks.blender else pkgs.blender;
      blenderConfig =
        (if isDarwin then "Library/Application Support/Blender" else ".config/blender")
        + "/${lib.versions.majorMinor blender.version}";
      enableBlenderAddon = pkgs.writeText "enable_mcp.py" ''
        import addon_utils
        import bpy


        def enable():
            bpy.context.preferences.system.use_online_access = True
            addon_utils.enable("bl_ext.user_default.mcp", default_set=True)


        def register():
            bpy.app.timers.register(enable, first_interval=0)


        def unregister():
            pass
      '';
      allowed =
        if isDarwin then
          "${config.home.homeDirectory}/Library/Application Support/ArtCraft/mcp"
        else
          "${config.xdg.configHome}/ArtCraft/mcp";

      craftAgents = pkgs.writeShellApplication {
        name = "craft-agents";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          every=${lib.escapeShellArg "${config.xdg.configHome}/craft-agents/apps.json"}
          allowed=${lib.escapeShellArg allowed}/apps.json

          case "''${1:-status}" in
          on)
            shift
            mkdir -p "$(dirname "$allowed")"
            if (($# == 0)); then
              # A link, so a rebuild keeps pointing agents at current apps.
              ln -sfn "$every" "$allowed"
            else
              for app in "$@"; do
                jq -e --arg app "$app" 'any(.apps[]; .id == $app)' "$every" >/dev/null || {
                  echo "craft-agents: no app named $app" >&2
                  exit 1
                }
              done
              rm -f "$allowed"
              jq '.apps |= map(select(.id as $id | $ARGS.positional | index($id)))' \
                "$every" --args "$@" >"$allowed"
            fi
            ;;
          off)
            rm -f "$allowed"
            ;;
          status) ;;
          *)
            echo "usage: craft-agents [on [app...] | off | status]" >&2
            exit 2
            ;;
          esac

          if [[ -e $allowed ]]; then
            echo "on: $(jq -r '[.apps[].id] | join(" ")' "$allowed")"
          else
            echo "off"
          fi
        '';
      };
    in
    lib.mkIf enable {
      home = {
        file = {
          "${blenderConfig}/extensions/user_default/mcp".source = pkgs.blender-mcp.addon;
          "${blenderConfig}/scripts/startup/enable_mcp.py".source = enableBlenderAddon;
        };

        packages = [
          craftAgents
          pkgs.craft-ai-mcp
        ]
        ++ lib.mapAttrsToList (app: _: cli app) apps
        ++ lib.optionals isDarwin (lib.mapAttrsToList (app: _: pkgs.brewCasks.${app}) apps);
      }
      // lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot}.directories = [
          ".config/ArtCraft"
        ]
        ++ lib.concatMap (app: [
          ".config/${app}"
          ".local/share/${app}"
        ]) (lib.attrNames apps);
      };

      xdg.configFile."craft-agents/apps.json".source = everyApp;

      programs = {
        mcp = {
          enable = true;
          servers.craft = {
            command = lib.getExe pkgs.craft-ai-mcp;
            args = [ "--stdio" ];
          };
        };
        claude-code.enableMcpIntegration = true;
        codex.enableMcpIntegration = true;
        opencode.enableMcpIntegration = true;
      };
    };
}
