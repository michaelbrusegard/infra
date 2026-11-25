package conversations

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestCodexAgentMessages(t *testing.T) {
	role, blocks := responsesItem([]byte(`{"type":"agent_message","author":"/root/review","recipient":"/root","content":[` +
		`{"type":"input_text","text":"Message Type: FINAL_ANSWER\nSender: /root/review"},` +
		`{"type":"encrypted_content","encrypted_content":"gAAAA"}]}`))
	if role != "user" || len(blocks) != 1 || blocks[0].Type != "text" ||
		!strings.HasPrefix(blocks[0].Text, "Message Type: FINAL_ANSWER") {
		t.Fatalf("agent message %s %+v", role, blocks)
	}
}

func TestCodexToolSearchResults(t *testing.T) {
	found := `[{"type":"namespace","name":"mcp__voice","tools":[{"type":"function","name":"speak","parameters":{"type":"object"}}]}]`
	role, blocks := responsesItem([]byte(`{"type":"tool_search_output","call_id":"ts_1","status":"completed","tools":` + found + `}`))
	if role != "tool" || len(blocks) != 1 || blocks[0].Type != "tool_result" || blocks[0].Text != found {
		t.Fatalf("tool search result %s %+v", role, blocks)
	}
}

func TestClaudeCodeToolReferencesKeepTheirNames(t *testing.T) {
	blocks := anthropicContent([]byte(`[{"type":"tool_result","tool_use_id":"toolu_1","content":[` +
		`{"type":"tool_reference","tool_name":"mcp__t3-code__delegate_task"},{"type":"tool_reference","tool_name":"WebFetch"}]}]`))
	if len(blocks) != 1 || blocks[0].Text != "mcp__t3-code__delegate_task\nWebFetch" {
		t.Fatalf("blocks %+v", blocks)
	}
}

func TestProxyAdditionalToolsAreContext(t *testing.T) {
	tool := `{"type":"function","name":"exec","parameters":{"type":"object"}}`
	f := proxyFixture{
		Request: Request{
			RequestID: "codex-tools", StartedAt: "2026-11-12 10:00:00.000",
			CompletedAt: "2026-11-12 10:00:01.000", SourceFormat: "openai-response", UserAgent: "codex_cli_rs/0.200.0",
			ResponseBody: `{"type":"response.completed","response":{"id":"resp_T","object":"response","model":"gpt-6.1-sol","output":[` +
				`{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}]}]}}`,
		},
		Body: json.RawMessage(`{"model":"gpt-6.1-sol","tools":[{"type":"web_search"}],"input":[` +
			`{"type":"additional_tools","id":"at_1","role":"developer","tools":[{"type":"namespace","name":"functions","tools":[` + tool + `]}]},` +
			`{"type":"message","role":"user","content":[{"type":"input_text","text":"Run it."}]}]}`),
	}
	n := NewNormalizer()
	n.Request(f.stored())
	for _, m := range n.Messages {
		for _, b := range m.Blocks {
			if b.Type == "other" {
				t.Fatalf("message %+v keeps only a type", m)
			}
		}
	}
	if got := texts(Path(n.Messages, n.Calls[0].OutputIDs[0])); !reflect.DeepEqual(got, []string{"user text:Run it.", "assistant* text:Done."}) {
		t.Fatalf("path %v", got)
	}
	c := n.Calls[0].Context
	if len(c) != 1 || c[0].Field != "tools" || c[0].Position != 1 || len(n.Items) != 1 ||
		n.Items[0].Hash != c[0].Hash || !strings.Contains(n.Items[0].Item, `"name":"functions"`) {
		t.Fatalf("context %+v, items %+v", c, n.Items)
	}
}

func TestAnthropicSearchResultsAndFallbacks(t *testing.T) {
	blocks := anthropicContent([]byte(`[{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-4-8"},` +
		`"trigger":{"type":"refusal","category":"cyber"}},{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[` +
		`{"type":"web_search_result","title":"Signal stats","url":"https://example.com/signal","encrypted_content":"Eq"}]}]`))
	if len(blocks) != 2 || blocks[0].Type != "fallback" || !strings.Contains(blocks[0].Text, `"to":{"model":"claude-opus-4-8"}`) ||
		blocks[1].Type != "tool_result" || blocks[1].Text != "Signal stats\nhttps://example.com/signal" {
		t.Fatalf("blocks %+v", blocks)
	}
}
