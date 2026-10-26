import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(importlib.util.find_spec("mcp"), "MCP SDK is checked by the Nix package build")
class MCPTests(unittest.IsolatedAsyncioTestCase):
    async def test_tool_discovery_and_safe_validation_over_stdio(self):
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.stdio import stdio_client

        server = StdioServerParameters(
            command=sys.executable,
            args=[str(Path(__file__).with_name("ai_images.py")), "serve"],
        )
        async with stdio_client(server) as streams:
            async with ClientSession(*streams) as session:
                await session.initialize()
                tools = await session.list_tools()
                self.assertEqual({t.name for t in tools.tools}, {"generate_image", "edit_image"})
                with tempfile.TemporaryDirectory() as directory:
                    target = Path(directory) / "existing.png"
                    target.write_bytes(b"original")
                    # Validation must reject this before sending a live request.
                    result = await session.call_tool("generate_image", {
                        "prompt": "test", "output_path": str(target),
                    })
                    self.assertTrue(result.isError)
                    self.assertIn("already exists", result.content[0].text)
                    self.assertEqual(target.read_bytes(), b"original")
