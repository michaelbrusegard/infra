{ pkgs }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    supabase-cli
  ];
}
