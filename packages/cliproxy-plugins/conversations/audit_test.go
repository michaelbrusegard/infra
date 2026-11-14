package conversations

import (
	"fmt"
	"reflect"
	"sort"
	"strconv"
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

// A Pi compaction is a summarization call, which records its usage: a
// call without outputs, of the model in use, whose input is what it
// summarized.
func TestPiCompactionsKeepTheirUsage(t *testing.T) {
	n, _ := transcriptBatch(t, nil)
	c := callByID(t, &n.Batch, "c1")
	if c.UncachedInputTokens != 180000 || c.CacheReadTokens != 10000 || c.OutputTokens != 900 ||
		c.Model != "gpt-5.6-sol" || len(c.OutputIDs) != 0 || c.StartedAt != "2026-08-25 18:00:00.000" {
		t.Fatalf("compaction call %+v", c)
	}
	var input []string
	for _, m := range Path(n.Messages, c.InputID) {
		input = append(input, m.Line)
	}
	if !reflect.DeepEqual(input, []string{"3", "4", "5"}) {
		t.Fatalf("compaction input %v", input)
	}
}

// An OpenCode sub-agent's session names its parent, which maps into the
// same namespace as every OpenCode session.
func TestOpenCodeSessionsKeepTheirParent(t *testing.T) {
	file := []TranscriptLine{{Source: "opencode", Host: "forte", Session: "ses_child", ID: "session:ses_child",
		Path: ".local/share/opencode/opencode.db", TS: "2026-06-17 20:42:35.341",
		Line: `{"kind":"session","id":"ses_child","session_id":"ses_child","timestamp":"2026-06-17T20:42:35.341Z",` +
			`"title":"Quick context rerun (@explore subagent)","directory":"/tmp","parent_id":"ses_parent"}`}}
	n := NewNormalizer()
	n.Transcript(file, repliesOf(nil, file), nil)
	if len(n.Sessions) != 1 || n.Sessions[0].SessionID != "opencode:ses_child" || n.Sessions[0].ParentSessionID != "opencode:ses_parent" {
		t.Fatalf("sessions %+v", n.Sessions)
	}
}

// claudeFile writes a Claude Code transcript whose lines are a second
// apart from start.
func claudeFile(path, start string, lines ...string) []TranscriptLine {
	var out []TranscriptLine
	for i, l := range lines {
		out = append(out, TranscriptLine{Source: "claude-code", Host: "lungo", Session: path, ID: strconv.Itoa(i + 1),
			Path: path, Line: l, TS: fmt.Sprintf("%s:%02d.000", start, i)})
	}
	return out
}

func claudeUser(uuid, parent, text string) string {
	return fmt.Sprintf(`{"type":"user","uuid":%q,"parentUuid":%q,"message":{"role":"user","content":%q}}`, uuid, parent, text)
}

func claudeReply(uuid, parent, id, ref string) string {
	return fmt.Sprintf(`{"type":"assistant","uuid":%q,"parentUuid":%q,"requestId":"req_%s","requestRef":%q,`+
		`"message":{"id":%q,"role":"assistant","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"toolu_%s",`+
		`"name":"Bash","input":{"command":"ls"}}],"usage":{"input_tokens":10,"output_tokens":5}}}`, uuid, parent, id, ref, id, id)
}

func claudeRequestLog(ref string) []string {
	return []string{`{"type":"api-request-shape","shapeHash":"sh1","shape":{"system":[{"type":"text","text":"You are Claude Code."}],` +
		`"tools":[{"name":"Bash","description":"Run a command.","input_schema":{"type":"object"}}]}}`,
		fmt.Sprintf(`{"type":"api-request","id":%q,"shapeHash":"sh1","keep":0,"tail":[]}`, ref)}
}

// A reply that several files hold is one call, of the file that owns it,
// with the system prompt and tools of its request log wherever a copy
// logged it: a sub-agent's copy of its parent's reply, or a sibling fork's
// copy of a reply both forks start from.
func TestClaudeCodeCallsTakeTheRequestLogOfAnyCopy(t *testing.T) {
	project := ".claude/projects/-Users-michaelbrusegard-Projects-infra/"
	session := "33333333-3333-4333-8333-333333333333"
	shared := []string{claudeUser("u1", "", "Find the failing test."), claudeReply("x1", "u1", "msg_shared", "r_shared")}
	parent := claudeFile(project+session+".jsonl", "2026-11-01 10:00", shared...)
	agent := claudeFile(project+session+"/subagents/agent-a1.jsonl", "2026-11-01 10:00",
		append(append(claudeRequestLog("r_shared"), shared...), claudeUser("u2", "x1", "Look closer."),
			claudeReply("x2", "u2", "msg_agent", "r_shared"))...)
	fork := []string{claudeUser("v1", "", "Fork the review."), claudeReply("y1", "v1", "msg_fork", "r_fork")}
	first := claudeFile(project+session+"/subagents/agent-f1.jsonl", "2026-11-01 11:00", fork...)
	second := claudeFile(project+session+"/subagents/agent-f2.jsonl", "2026-11-01 11:00",
		append(claudeRequestLog("r_fork"), fork...)...)
	files := [][]TranscriptLine{parent, agent, first, second}
	replies := repliesOf(nil, files...)
	n := NewNormalizer()
	for _, f := range files {
		n.Transcript(f, replies, nil)
	}
	var calls []string
	for _, c := range n.Calls {
		var fields []string
		for _, p := range c.Context {
			fields = append(fields, fmt.Sprintf("%s/%d", p.Field, p.Position))
		}
		calls = append(calls, c.SessionID+" "+c.ResponseID+" "+strings.Join(fields, ","))
	}
	sort.Strings(calls)
	want := []string{
		"claude:" + session + " msg_shared system/0,tools/0",
		"claude:" + session + ":agent:a1 msg_agent system/0,tools/0",
		"claude:" + session + ":agent:f1 msg_fork system/0,tools/0",
	}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("calls %q, want %q", calls, want)
	}
}
