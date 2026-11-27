{
  lib,
  python3Packages,
  fetchgit,
}:
python3Packages.buildPythonApplication rec {
  pname = "blender-mcp";
  version = "1.0.2-unstable-2026-09-29";
  pyproject = true;

  src = fetchgit {
    url = "https://projects.blender.org/lab/blender_mcp.git";
    rev = "dbbf836ad4b1025f14a2b3b504c43903f39e0b04";
    hash = "sha256-7+v0AzVpDvDqddnDdCObQRirUpo6gF6aMiUFCsyrW3E=";
  };
  sourceRoot = "${src.name}/mcp";

  build-system = [ python3Packages.setuptools ];
  dependencies = with python3Packages; [
    docutils
    mcp
    pyyaml
  ];

  # The half that runs inside Blender, installed as an extension.
  passthru.addon = "${src}/addon/blender_mcp_addon";

  meta = {
    description = "Blender Lab's MCP server for Blender";
    homepage = "https://projects.blender.org/lab/blender_mcp";
    license = lib.licenses.gpl3Plus;
    mainProgram = "blender-mcp";
  };
}
