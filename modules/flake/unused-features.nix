{
  config,
  lib,
  ...
}:
let
  inherit (config.flake) modules;

  namesIn =
    class: graph:
    let
      filesUnder = node: [ node.file ] ++ lib.concatMap filesUnder node.imports;
      nameOf = file: builtins.match ".*#modules\\.${class}\\.(.+)" file;
    in
    lib.concatMap (file: lib.optionals (nameOf file != null) (nameOf file)) (
      lib.concatMap filesUnder graph
    );

  # Home Manager evaluates each user inside the system configuration, which
  # exposes no module graph, so a user's profile is evaluated here on its own.
  # Collecting imports does not evaluate options, so the arguments a real
  # Home Manager evaluation would provide are not needed.
  homeGraph =
    user:
    (lib.evalModules {
      class = "homeManager";
      modules = [ modules.homeManager.${user} ];
    }).graph;

  # The home bundles a system bundle or host hands to every user on it.
  sharedHomeGraph =
    (lib.evalModules {
      class = "homeManager";
      modules = lib.concatMap (system: system.config.home-manager.sharedModules or [ ]) (
        lib.attrValues config.flake.nixosConfigurations ++ lib.attrValues config.flake.darwinConfigurations
      );
    }).graph;

  imported = {
    nixos = lib.concatMap (system: namesIn "nixos" system.graph) (
      lib.attrValues config.flake.nixosConfigurations
    );
    darwin = lib.concatMap (system: namesIn "darwin" system.graph) (
      lib.attrValues config.flake.darwinConfigurations
    );
    homeManager =
      lib.concatMap (user: namesIn "homeManager" (homeGraph user)) (
        lib.unique (lib.concatMap (host: host.users) (lib.attrValues config.hosts))
      )
      ++ namesIn "homeManager" sharedHomeGraph;
  };

  unused = lib.filterAttrs (_: names: names != [ ]) (
    lib.mapAttrs (
      class: defined: lib.subtractLists (imported.${class} or [ ]) (lib.attrNames defined)
    ) modules
  );
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.unused-features =
        if unused == { } then
          pkgs.emptyFile
        else
          pkgs.runCommand "unused-features" { } ''
            cat >&2 <<'EOF'
            These modules are defined but no host or user ends up importing them:
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                class: names: "  flake.modules.${class}: ${lib.concatStringsSep ", " names}"
              ) unused
            )}
            Import each one from a bundle, host or user, or delete its file.
            EOF
            exit 1
          '';
    };
}
