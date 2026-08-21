import importlib.util
import json
import sys
import types
import unittest
from pathlib import Path


PLUGIN_PATH = (
    Path(__file__).resolve().parents[1]
    / "plugins"
    / "response-polish"
    / "__init__.py"
)


class _Usage:
    input_tokens = 12
    output_tokens = 8


class _Result:
    text = "Polished text."
    model = "kimi-k2"
    usage = _Usage()


class _Llm:
    def __init__(self):
        self.calls = []

    def complete(self, messages, **kwargs):
        self.calls.append((messages, kwargs))
        return _Result()


class _Context:
    def __init__(self):
        self.llm = _Llm()
        self.tool = None

    def register_tool(self, **kwargs):
        self.tool = kwargs


class ResponsePolishTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.saved_modules = {
            name: sys.modules.get(name) for name in ("tools", "tools.registry")
        }
        registry = types.ModuleType("tools.registry")
        registry.tool_error = lambda message: json.dumps(
            {"success": False, "error": message}
        )
        registry.tool_result = lambda payload: json.dumps(
            {"success": True, "result": payload}
        )
        tools = types.ModuleType("tools")
        tools.registry = registry
        sys.modules["tools"] = tools
        sys.modules["tools.registry"] = registry

        spec = importlib.util.spec_from_file_location("response_polish", PLUGIN_PATH)
        cls.module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(cls.module)

    @classmethod
    def tearDownClass(cls):
        for name, module in cls.saved_modules.items():
            if module is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = module

    def setUp(self):
        self.context = _Context()
        self.module.register(self.context)

    def test_registers_model_neutral_tool_name(self):
        self.assertEqual(self.context.tool["name"], "polish_response")
        self.assertNotIn("kimi", self.context.tool["name"])
        self.assertEqual(self.context.tool["toolset"], "writing")

    def test_routes_only_the_polish_call_to_k2(self):
        raw = self.context.tool["handler"](
            {
                "draft": "A factual draft.",
                "intent": "warm technical explanation",
            }
        )
        payload = json.loads(raw)
        self.assertTrue(payload["success"])
        self.assertEqual(payload["result"]["polished_text"], "Polished text.")
        self.assertEqual(len(self.context.llm.calls), 1)
        messages, kwargs = self.context.llm.calls[0]
        self.assertEqual(kwargs["model"], "kimi-k2")
        self.assertIn("preserving the source exactly", messages[0]["content"])
        self.assertIn("A factual draft.", messages[1]["content"])

    def test_rejects_empty_draft_without_calling_model(self):
        raw = self.context.tool["handler"]({"draft": "  "})
        payload = json.loads(raw)
        self.assertFalse(payload["success"])
        self.assertEqual(self.context.llm.calls, [])


if __name__ == "__main__":
    unittest.main()
