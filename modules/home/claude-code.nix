{
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  programs.claude-code.enable = true;

  home = lib.optionalAttrs (homePersistenceRoot != null) {
    persistence.${homePersistenceRoot} = {
      directories = [
        ".claude"
      ];
      files = [
        ".claude.json"
      ];
    };
  };
}
