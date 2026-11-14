package conversations

import (
	"reflect"
	"strings"
	"testing"
)

// Codex writes agent_message items, the messages sub-agents and their
// parent send each other, and additional_tools items, the tool definitions
// sent with every call after them, among its response items. A message
// keeps its text, and calls take the definitions as context, so a call
// exports with its tools, including after a compaction that keeps them.
func TestCodexAgentMessagesAndAdditionalTools(t *testing.T) {
	tools := `{"type":"additional_tools","id":"at_1","role":"developer","tools":[{"type":"namespace","name":"functions",` +
		`"tools":[{"type":"function","name":"exec","description":"Run a command.","parameters":{"type":"object"}}]}]}`
	call := `{"type":"response_item","payload":{"type":"function_call","name":"exec","arguments":"{}","call_id":"call_%s"}}`
	file := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000a.jsonl",
		"2026-11-12 10:00", `{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000a"}}`,
		`{"type":"response_item","payload":`+tools+`}`,
		`{"type":"response_item","payload":{"type":"agent_message","author":"/root/review","recipient":"/root","content":[`+
			`{"type":"input_text","text":"Message Type: FINAL_ANSWER\nSender: /root/review"},`+
			`{"type":"encrypted_content","encrypted_content":"gAAAA"}]}}`,
		strings.Replace(call, "%s", "1", 1), codexUsageLine("resp_1"),
		`{"type":"response_item","payload":{"type":"function_call_output","call_id":"call_1","output":"ok"}}`,
		`{"type":"compacted","payload":{"message":"","replacement_history":[`+tools+`,`+
			`{"type":"message","role":"user","content":[{"type":"input_text","text":"Summary."}]}]}}`,
		strings.Replace(call, "%s", "2", 1), codexUsageLine("resp_2"))
	n := NewNormalizer()
	n.Transcript(file, repliesOf(nil, file), nil)
	if err := n.CoverageError(); err != nil {
		t.Fatal(err)
	}
	var agent *Message
	for i, m := range n.Messages {
		for _, b := range m.Blocks {
			if b.Type == "other" {
				t.Fatalf("message %+v keeps only a type", m)
			}
			if b.SourceType == "input_text" && strings.HasPrefix(b.Text, "Message Type: FINAL_ANSWER") {
				agent = &n.Messages[i]
			}
		}
	}
	if agent == nil || agent.Role != "user" || agent.Output || len(agent.Blocks) != 1 {
		t.Fatalf("agent message %+v", agent)
	}
	items := map[Hash]string{}
	for _, it := range n.Items {
		items[it.Hash] = it.Item
	}
	if len(n.Calls) != 2 {
		t.Fatalf("calls %+v", n.Calls)
	}
	for _, c := range n.Calls {
		var ctx Context
		for _, p := range c.Context {
			ctx.Add(p.Field, []byte(items[p.Hash]))
		}
		path := Path(n.Messages, c.OutputIDs[len(c.OutputIDs)-1])
		if err := ForTraining(ctx, path, c.OutputIDs); err != nil {
			t.Fatalf("call %s: %v", c.ResponseID, err)
		}
		request := must(OpenAIChat(ctx, path, c.OutputIDs))
		if names := toolNames(request); !reflect.DeepEqual(names, []string{"exec"}) {
			t.Fatalf("call %s exports tools %v", c.ResponseID, names)
		}
	}
	if !reflect.DeepEqual(n.Calls[0].Context, n.Calls[1].Context) {
		t.Fatalf("the compaction changed the tools: %+v", n.Calls)
	}
}

func toolNames(request map[string]any) []string {
	var names []string
	tools, _ := request["tools"].([]any)
	for _, tool := range tools {
		t := tool.(map[string]any)
		if f, ok := t["function"].(map[string]any); ok {
			t = f
		}
		names = append(names, t["name"].(string))
	}
	return names
}

// Claude Code's tool search returns tool references, which name the tools
// it loaded.
func TestClaudeCodeToolReferencesKeepTheirNames(t *testing.T) {
	blocks := anthropicContent([]byte(`[{"type":"tool_result","tool_use_id":"toolu_1","content":[` +
		`{"type":"tool_reference","tool_name":"mcp__t3-code__delegate_task"},{"type":"tool_reference","tool_name":"WebFetch"}]}]`))
	if len(blocks) != 1 || blocks[0].Text != "mcp__t3-code__delegate_task\nWebFetch" {
		t.Fatalf("blocks %+v", blocks)
	}
}

// A kind of line or block the import does not know fails it, rather than
// being dropped or kept as an empty other block, since llm.transcripts is
// dropped after the import.
func TestTranscriptImportFailsOnUnknownTypes(t *testing.T) {
	for name, line := range map[string]string{
		"kind":  `{"type":"event_msg","payload":{"type":"brand_new_event"}}`,
		"item":  `{"type":"response_item","payload":{"type":"brand_new_item","content":"x"}}`,
		"block": `{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_audio","data":"x"}]}}`,
	} {
		file := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000a.jsonl",
			"2026-11-12 10:00", `{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000a"}}`, line)
		n := NewNormalizer()
		n.Transcript(file, repliesOf(nil, file), nil)
		if err := n.CoverageError(); err == nil || !strings.Contains(err.Error(), "brand_new") && name != "block" ||
			name == "block" && !strings.Contains(err.Error(), "input_audio") {
			t.Fatalf("%s: error %v", name, err)
		}
	}
}
