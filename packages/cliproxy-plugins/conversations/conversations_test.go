package conversations

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"testing"

	"cliproxy-plugins/requestitems"
)

// The fixtures are hand-written in the shapes profiled from the live
// archive in November 2026, with content and identifiers redacted.
type proxyFixture struct {
	Request
	Name string          `json:"name"`
	Body json.RawMessage `json:"body"`
}

func load(t *testing.T, name string, v any) {
	t.Helper()
	data, err := os.ReadFile("testdata/" + name)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, v); err != nil {
		t.Fatal(err)
	}
}

// body returns the request body as the client sent it. Truncated bodies are
// fixtures written as JSON strings.
func (f proxyFixture) body() []byte {
	if isString(f.Body) {
		return []byte(str(f.Body))
	}
	return f.Body
}

// stored splits the body the way the archive plugin stores it.
func (f proxyFixture) stored() Request {
	r := f.Request
	split := requestitems.Split(f.body())
	r.RequestEnvelope, r.RequestParts = split.Envelope, split.Parts
	for _, item := range split.Items {
		r.Items = append(r.Items, string(item))
	}
	return r
}

func proxyBatch(t *testing.T) (*Normalizer, []proxyFixture) {
	t.Helper()
	var fixtures []proxyFixture
	load(t, "proxy.json", &fixtures)
	n := NewNormalizer()
	for _, f := range fixtures {
		r := f.stored()
		for _, item := range r.Items {
			archived[requestitems.HashOf([]byte(item))] = item
		}
		n.Request(r)
	}
	return n, fixtures
}

// archived stands in for llm.request_items: the items requests were read
// with, which the normalizer does not write again.
var archived = map[Hash]string{}

// rawOf follows a message's references to the raw JSON it was read from: a
// request item, or for an output, the response body its call names,
// assembled again. The inputs a request's envelope held have none of their
// own.
func rawOf(t *testing.T, b *Batch, m Message) ([]byte, bool) {
	t.Helper()
	switch {
	case m.Output:
		c := callByID(t, b, m.CallID)
		r, ok := storedRequests(t)[c.RequestID]
		if !ok {
			t.Fatalf("call %s names no request", c.CallID)
		}
		outputs := parseResponse(r.SourceFormat, r.ResponseBody).outputs
		for i, id := range c.OutputIDs {
			if id == m.ID {
				return outputs[i], true
			}
		}
		t.Fatalf("output %v is not its call's", m.ID)
	case m.Item != (Hash{}):
		item, ok := archived[m.Item]
		if !ok {
			t.Fatalf("message %v names no item", m.ID)
		}
		return []byte(item), true
	}
	return nil, false
}

func decode(t *testing.T, data []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatalf("decode %q: %v", data, err)
	}
	return v
}

func callByID(t *testing.T, b *Batch, id string) Call {
	t.Helper()
	for _, c := range b.Calls {
		if c.CallID == id {
			return c
		}
	}
	t.Fatalf("no call %s", id)
	return Call{}
}

func texts(path []Message) []string {
	var out []string
	for _, m := range path {
		var parts []string
		for _, b := range m.Blocks {
			parts = append(parts, b.Type+":"+firstNonEmpty(b.Text, b.ToolInput, b.Media))
		}
		prefix := m.Role
		if m.Output {
			prefix += "*"
		}
		out = append(out, prefix+" "+strings.Join(parts, " | "))
	}
	return out
}

// Every request is exactly one call, which names it, and every message's
// reference resolves: an input to an item of the request that first sent
// it, an output to its call's response.
func TestProxyReferencesResolve(t *testing.T) {
	n, fixtures := proxyBatch(t)
	requests := storedRequests(t)
	calls := map[string]int{}
	for _, c := range n.Calls {
		if _, ok := requests[c.RequestID]; !ok || c.Origin != "proxy" {
			t.Fatalf("call %s names no request", c.CallID)
		}
		calls[c.RequestID]++
	}
	for _, f := range fixtures {
		if calls[f.Name] != 1 {
			t.Fatalf("request %s is %d calls", f.Name, calls[f.Name])
		}
	}
	for _, m := range n.Messages {
		raw, _ := rawOf(t, &n.Batch, m)
		if m.Item == (Hash{}) {
			continue
		}
		parts := false
		for _, p := range requests[m.CallID].RequestParts {
			parts = parts || p.Hash == m.Item
		}
		if !parts || requestitems.HashOf(raw) != m.Item {
			t.Fatalf("message %v names item %v, which its call %s did not send", m.ID, m.Item, m.CallID)
		}
	}
}

func TestProxyConversationTree(t *testing.T) {
	n, _ := proxyBatch(t)
	path := func(leaf Hash) []string { return texts(Path(n.Messages, leaf)) }

	// The second Claude turn resends the first user message, without the
	// cache marker, and the first reply: both are the same nodes.
	first, second := callByID(t, &n.Batch, "claude-1"), callByID(t, &n.Batch, "claude-2")
	want := []string{"user text:The nightly backup job fails; find out why."}
	if got := path(first.InputID); !reflect.DeepEqual(got, want) {
		t.Fatalf("first input %q", got)
	}
	want = append(want,
		"assistant* thinking:I should look at the CronJob logs first. | text:Checking the job logs. | tool_call:{\"command\":\"kubectl logs job/backup\"}",
		"user tool_result:error: pod not found | image:image/png | text:It ran on the old node.",
		"assistant* text:The job is pinned to a node that was removed.")
	if got := path(second.OutputIDs[0]); !reflect.DeepEqual(got, want) {
		t.Fatalf("second conversation\n%q\nwant\n%q", got, want)
	}
	out := Path(n.Messages, second.InputID)
	if out[1].ID != first.OutputIDs[0] || out[1].CallID != "claude-1" || out[1].Model != "claude-opus-5-5" {
		t.Fatalf("resent reply is not the first output: %+v", out[1])
	}
	for _, m := range n.Messages {
		if m.SessionID == first.SessionID && m.ParentID == first.InputID && m.ID != first.OutputIDs[0] {
			t.Fatalf("resent reply branched off: %+v", m)
		}
	}
	if first.UncachedInputTokens != 12 || first.CacheWriteTokens != 3000 || first.OutputTokens != 87 || first.ResponseID != "msg_01A" {
		t.Fatalf("first usage %+v", first)
	}
	// Sub-agents are their own sessions, linked to the parent.
	agent := callByID(t, &n.Batch, "claude-agent")
	if agent.SessionID != "claude:11111111-1111-4111-8111-111111111111:agent:a1b2c3d4e5f6a7b8c" {
		t.Fatalf("agent session %s", agent.SessionID)
	}

	// A Codex request that continues a response sends only new items; its
	// context is the previous call's input and output.
	codex := callByID(t, &n.Batch, "codex-2")
	want = []string{
		"developer text:<permissions instructions>Sandbox: workspace-write.</permissions instructions>",
		"user text:Why does the dashboard show no cost for luna? | image:image/png",
		"assistant* thinking:**Checking the pricing view**",
		"assistant* tool_call:const r = await tools.exec_command({cmd: 'rg luna'});\ntext(r)",
		"tool tool_result:Script running with cell ID g2:102\nWall time 1.0 seconds\nOutput:\ngitops/espresso/apps/clickhouse/configmap.yaml: gpt-6-luna",
		"assistant* text:Luna is priced; the panel filters it out.",
	}
	if got := path(codex.OutputIDs[0]); !reflect.DeepEqual(got, want) {
		t.Fatalf("codex conversation\n%q\nwant\n%q", got, want)
	}
	if codex.SessionID != "codex:01a1da81-0000-7000-8000-000000000001" || codex.ResponseID != "resp_B" {
		t.Fatalf("codex call %+v", codex)
	}
	c1 := callByID(t, &n.Batch, "codex-1")
	if c1.UncachedInputTokens != 1000 || c1.CacheReadTokens != 4000 || c1.ReasoningTokens != 120 {
		t.Fatalf("codex usage %+v", c1)
	}
	// An unarchived previous response starts at a marker, and an
	// interrupted output keeps what streamed.
	orphan := Path(n.Messages, callByID(t, &n.Batch, "codex-orphan").OutputIDs[0])
	if got := texts(orphan); !reflect.DeepEqual(got, []string{"system other:resp_unarchived", "user text:continue",
		`assistant* tool_call:{"plan":[]}`}) {
		t.Fatalf("orphan %q", got)
	}
	sub := callByID(t, &n.Batch, "codex-agent")
	if sub.SessionID != "codex:01a1da81-0000-7000-8000-000000000001:agent:pricing_review" {
		t.Fatalf("codex agent session %s", sub.SessionID)
	}

	// Sessionless chat calls group by their first message.
	chat1, chat2 := callByID(t, &n.Batch, "chat-1"), callByID(t, &n.Batch, "chat-2")
	if chat1.SessionID != chat2.SessionID || !strings.HasPrefix(chat1.SessionID, "proxy:") || chat1.Client != "pi" {
		t.Fatalf("chat sessions %s %s", chat1.SessionID, chat2.SessionID)
	}
	if got := texts(Path(n.Messages, chat1.OutputIDs[0]))[2]; got != `assistant* thinking:Read flake.nix. | text:Reading it. | tool_call:{"path":"flake.nix"}` {
		t.Fatalf("assembled chat output %q", got)
	}
	if chat1.UncachedInputTokens != 100 || chat1.CacheReadTokens != 800 || chat1.ReasoningTokens != 10 {
		t.Fatalf("chat usage %+v", chat1)
	}
	// The reply is sent back without its reasoning and still matches.
	if got := texts(Path(n.Messages, chat2.OutputIDs[0])); len(got) != 5 || !strings.HasPrefix(got[2], "assistant* thinking:") ||
		got[3] != "tool tool_result:inputs = { nixpkgs.url = ...; };" {
		t.Fatalf("chat conversation %q", got)
	}

	truncated := callByID(t, &n.Batch, "truncated")
	if truncated.InputID != (Hash{}) || len(truncated.OutputIDs) != 0 {
		t.Fatalf("truncated call %+v", truncated)
	}
	sessions := map[string]string{}
	for _, s := range n.Sessions {
		sessions[s.SessionID] = s.ParentSessionID
	}
	if sessions[agent.SessionID] != "claude:11111111-1111-4111-8111-111111111111" ||
		sessions[sub.SessionID] != "codex:01a1da81-0000-7000-8000-000000000001" {
		t.Fatalf("sessions %v", sessions)
	}
}

func TestProxyNormalizationIsIdempotent(t *testing.T) {
	a, fixtures := proxyBatch(t)
	b := NewNormalizer()
	for _, f := range fixtures {
		b.Request(f.stored())
	}
	// Feeding the same requests again adds no messages.
	for _, f := range fixtures {
		b.Request(f.stored())
	}
	if len(b.Messages) != len(a.Messages) {
		t.Fatalf("%d messages after a rerun, want %d", len(b.Messages), len(a.Messages))
	}
	ids := map[Hash]bool{}
	for _, m := range a.Messages {
		if ids[m.ID] {
			t.Fatalf("duplicate message %v", m.ID)
		}
		ids[m.ID] = true
	}
}

// Keys whose strings are conversation content in some dialect.
var contentKeys = map[string]bool{"text": true, "thinking": true, "arguments": true, "input": true,
	"output": true, "content": true, "summary": true, "refusal": true,
	"reasoning_content": true, "error": true}

// Every content string in a raw item must appear in an extracted block, and
// every extracted string must come from the raw item: the columns neither
// drop nor invent content.
func TestBlocksMatchRawItems(t *testing.T) {
	p, _ := proxyBatch(t)
	checked := 0
	for _, m := range p.Messages {
		raw, ok := rawOf(t, &p.Batch, m)
		if !ok || m.Format == "proxy" {
			continue
		}
		var leaves []string
		var walk func(key string, v any)
		walk = func(key string, v any) {
			switch v := v.(type) {
			case map[string]any:
				for k, c := range v {
					walk(k, c)
				}
			case []any:
				for _, c := range v {
					walk(key, c)
				}
			case string:
				if contentKeys[key] && v != "" {
					leaves = append(leaves, v)
				}
			}
		}
		walk("", value(raw))
		var extracted []string
		all := string(raw)
		for _, b := range m.Blocks {
			for _, s := range []string{b.Text, b.ToolInput} {
				if s == "" {
					continue
				}
				extracted = append(extracted, s)
				for _, piece := range strings.Split(s, "\n\n") {
					quoted, _ := json.Marshal(piece)
					if !strings.Contains(all, piece) && !strings.Contains(all, strings.Trim(string(quoted), `"`)) &&
						!jsonContains(raw, piece) {
						t.Fatalf("%s: extracted %q is not in the raw item %s", m.Format, piece, raw)
					}
				}
			}
		}
		joined := strings.Join(extracted, "\n")
		for _, leaf := range leaves {
			if !strings.Contains(joined, leaf) {
				t.Fatalf("%s: content %q missing from blocks %+v", m.Format, leaf, m.Blocks)
			}
		}
		checked++
	}
	if checked < 20 {
		t.Fatalf("checked only %d messages", checked)
	}
}

// jsonContains reports whether s is the compact form of a value inside raw,
// as extracted tool inputs are.
func jsonContains(raw []byte, s string) bool {
	found := false
	var walk func(v any)
	walk = func(v any) {
		if found {
			return
		}
		if b, err := json.Marshal(v); err == nil && string(b) == s {
			found = true
			return
		}
		switch v := v.(type) {
		case map[string]any:
			for _, c := range v {
				walk(c)
			}
		case []any:
			for _, c := range v {
				walk(c)
			}
		}
	}
	walk(value(raw))
	return found
}

// must returns an export that cannot fail.
func must(request map[string]any, err error) map[string]any {
	if err != nil {
		panic(err)
	}
	return request
}

func TestExports(t *testing.T) {
	n, _ := proxyBatch(t)
	path := Path(n.Messages, callByID(t, &n.Batch, "claude-2").OutputIDs[0])
	chat, _ := json.Marshal(must(OpenAIChat(Context{}, path, nil))["messages"])
	want := `[{"content":"The nightly backup job fails; find out why.","role":"user"},` +
		`{"content":"Checking the job logs.","reasoning_content":"I should look at the CronJob logs first.","role":"assistant",` +
		`"tool_calls":[{"function":{"arguments":"{\"command\":\"kubectl logs job/backup\"}","name":"Bash"},"id":"toolu_01","type":"function"}]},` +
		`{"content":"error: pod not found","role":"tool","tool_call_id":"toolu_01"},` +
		`{"content":"It ran on the old node.","role":"user"},` +
		`{"content":"The job is pinned to a node that was removed.","role":"assistant"}]`
	if string(chat) != want {
		t.Fatalf("openai chat\n%s\nwant\n%s", chat, want)
	}

	codex := Path(n.Messages, callByID(t, &n.Batch, "codex-2").OutputIDs[0])
	request := must(AnthropicMessages(Context{}, codex, nil))
	if request["system"] != "<permissions instructions>Sandbox: workspace-write.</permissions instructions>" {
		t.Fatalf("system %q", request["system"])
	}
	messages := request["messages"].([]map[string]any)
	roles := []string{}
	for _, m := range messages {
		roles = append(roles, m["role"].(string))
	}
	// Reasoning and the tool call merge into one assistant turn.
	if !reflect.DeepEqual(roles, []string{"user", "assistant", "user", "assistant"}) {
		t.Fatalf("anthropic roles %v", roles)
	}
	got, _ := json.Marshal(messages[2])
	if string(got) != `{"content":[{"content":"Script running with cell ID g2:102\nWall time 1.0 seconds\nOutput:\ngitops/espresso/apps/clickhouse/configmap.yaml: gpt-6-luna","is_error":false,"tool_use_id":"call_1","type":"tool_result"}],"role":"user"}` {
		t.Fatalf("anthropic tool result %s", got)
	}
}

// An assistant message can hold reasoning, a tool call, its result, and the
// answer, as OpenCode's transcript rows do; the export keeps them in that
// order.
func TestExportsKeepBlockOrder(t *testing.T) {
	path := []Message{
		{ID: Hash{1}, Role: "user", Blocks: []Block{{Type: "text", Text: "What does the worker return?"}}},
		{ID: Hash{2}, Role: "assistant", Output: true, Blocks: []Block{
			{Type: "thinking", Text: "Look up the worker."},
			{Type: "tool_call", ToolName: "execute", ToolCallID: "tool_HD0", ToolInput: `{"code":"return 1"}`},
			{Type: "tool_result", ToolCallID: "tool_HD0", Text: "1"},
			{Type: "text", Text: "The worker returns 1."}}},
	}
	chat, _ := json.Marshal(must(OpenAIChat(Context{}, path, nil))["messages"])
	want := `[{"content":"What does the worker return?","role":"user"},` +
		`{"content":"","reasoning_content":"Look up the worker.","role":"assistant","tool_calls":[{"function":{"arguments":"{\"code\":\"return 1\"}","name":"execute"},"id":"tool_HD0","type":"function"}]},` +
		`{"content":"1","role":"tool","tool_call_id":"tool_HD0"},` +
		`{"content":"The worker returns 1.","role":"assistant"}]`
	if string(chat) != want {
		t.Fatalf("openai chat\n%s\nwant\n%s", chat, want)
	}
	anthropic, _ := json.Marshal(must(AnthropicMessages(Context{}, path, nil))["messages"])
	want = `[{"content":[{"text":"What does the worker return?","type":"text"}],"role":"user"},` +
		`{"content":[{"thinking":"Look up the worker.","type":"thinking"},{"id":"tool_HD0","input":{"code":"return 1"},"name":"execute","type":"tool_use"}],"role":"assistant"},` +
		`{"content":[{"content":"1","is_error":false,"tool_use_id":"tool_HD0","type":"tool_result"}],"role":"user"},` +
		`{"content":[{"text":"The worker returns 1.","type":"text"}],"role":"assistant"}]`
	if string(anthropic) != want {
		t.Fatalf("anthropic\n%s\nwant\n%s", anthropic, want)
	}
}

// A call's export carries what the call ran with beside its messages: the
// system prompt or instructions, and the tools, from its request parts or
// what its response echoed.
func TestExportsCarryCallContext(t *testing.T) {
	n, _ := proxyBatch(t)
	requests := storedRequests(t)
	for _, tc := range []struct {
		call, system string
		tools        []string
	}{
		{"claude-2", "You are Claude Code, Anthropic's official CLI for Claude.", []string{"Bash", "Read"}},
		{"codex-1", "You are Codex", []string{"exec", "update_plan"}},
		// The delta request sent neither; its response echoes the tools in
		// effect, in a namespace, and no instructions.
		{"codex-2", "", []string{"exec", "update_plan"}},
	} {
		c := callByID(t, &n.Batch, tc.call)
		r := requests[c.RequestID]
		var ctx Context
		env := parse([]byte(r.RequestEnvelope))
		for _, field := range []string{"system", "instructions", "tools"} {
			if raw, ok := env[field]; ok {
				ctx.Add(field, raw)
			}
		}
		for i, p := range r.RequestParts {
			ctx.Add(p.Field, []byte(r.Items[i]))
		}
		ctx.Add("response", []byte(r.ResponseBody))
		path := Path(n.Messages, c.OutputIDs[len(c.OutputIDs)-1])
		if err := ForTraining(ctx, path, c.OutputIDs); err != nil {
			t.Fatalf("%s: %v", tc.call, err)
		}
		chat := must(OpenAIChat(ctx, path, nil))
		first := chat["messages"].([]map[string]any)[0]
		if (first["role"] == "system") != (tc.system != "") || !strings.HasPrefix(first["content"].(string), tc.system) {
			t.Fatalf("%s: first message %v", tc.call, first)
		}
		var names []string
		tools, _ := chat["tools"].([]any)
		for _, tool := range tools {
			if fn, ok := tool.(map[string]any)["function"].(map[string]any); ok && fn["parameters"] != nil {
				names = append(names, fn["name"].(string))
			} else if c, ok := tool.(map[string]any)["custom"].(map[string]any); ok {
				names = append(names, c["name"].(string))
			} else {
				names = append(names, "raw:"+tool.(map[string]any)["name"].(string))
			}
		}
		if !reflect.DeepEqual(names, tc.tools) {
			t.Fatalf("%s: openai tools %v", tc.call, names)
		}
		anthropic := must(AnthropicMessages(ctx, path, nil))
		names = nil
		tools, _ = anthropic["tools"].([]any)
		for _, tool := range tools {
			if tool := tool.(map[string]any); tool["input_schema"] != nil {
				names = append(names, tool["name"].(string))
			} else {
				names = append(names, "raw:"+tool["name"].(string))
			}
		}
		if !strings.HasPrefix(anthropic["system"].(string), tc.system) || !reflect.DeepEqual(names, tc.tools) {
			t.Fatalf("%s: anthropic context %v %v", tc.call, anthropic["system"], names)
		}
	}
}

// A freeform custom tool takes raw text. Each export writes its definition
// and its calls the same way: custom in Chat Completions, and in Anthropic
// Messages, which has no freeform tools, a tool taking the text as input.
func TestExportsConvertCustomToolsConsistently(t *testing.T) {
	n, _ := proxyBatch(t)
	c := callByID(t, &n.Batch, "codex-1")
	r := storedRequests(t)[c.RequestID]
	var ctx Context
	for i, p := range r.RequestParts {
		ctx.Add(p.Field, []byte(r.Items[i]))
	}
	path := Path(n.Messages, c.OutputIDs[len(c.OutputIDs)-1])
	script := `"const r = await tools.exec_command({cmd: 'rg luna'});\ntext(r)"`
	chat := must(OpenAIChat(ctx, path, nil))
	def := chat["tools"].([]any)[0].(map[string]any)
	delete(def["custom"].(map[string]any), "description")
	messages := chat["messages"].([]map[string]any)
	got, _ := json.Marshal([]any{def, messages[len(messages)-1]["tool_calls"]})
	want := `[{"custom":{"format":{"grammar":{"definition":"start: /.+/","syntax":"lark"},"type":"grammar"},"name":"exec"},"type":"custom"},` +
		`[{"custom":{"input":` + script + `,"name":"exec"},"id":"call_1","type":"custom"}]]`
	if string(got) != want {
		t.Fatalf("openai custom tool\n%s\nwant\n%s", got, want)
	}
	anthropic := must(AnthropicMessages(ctx, path, nil))
	tool := anthropic["tools"].([]any)[0].(map[string]any)
	turns := anthropic["messages"].([]map[string]any)
	blocks := turns[len(turns)-1]["content"].([]any)
	got, _ = json.Marshal([]any{tool["input_schema"], blocks[len(blocks)-1]})
	want = `[{"properties":{"input":{"type":"string"}},"required":["input"],"type":"object"},` +
		`{"id":"call_1","input":{"input":` + script + `},"name":"exec","type":"tool_use"}]`
	if string(got) != want {
		t.Fatalf("anthropic custom tool\n%s\nwant\n%s", got, want)
	}
}

func TestRowsEncodeForClickHouse(t *testing.T) {
	n, _ := proxyBatch(t)
	m, _ := json.Marshal(n.Messages[0])
	for _, key := range []string{`"id":"`, `"parent_id":"0"`, `"blocks":[{`, `"item":"`} {
		if !bytes.Contains(m, []byte(key)) {
			t.Fatalf("message row %s lacks %s", m, key)
		}
	}
	calls := n.Calls
	sort.Slice(calls, func(i, j int) bool { return calls[i].CallID < calls[j].CallID })
	c, _ := json.Marshal(calls[0])
	if !bytes.Contains(c, []byte(`"output_ids":["`)) || !bytes.Contains(c, []byte(`"request_id":"`)) {
		t.Fatalf("call row %s", c)
	}
}

// Namespaces flatten into their tools, and a bare name two namespaces define
// is qualified in both the definitions and the calls, so a call keeps the
// schema of the tool it called. A call whose namespace defines no such tool
// fails the export instead of picking one.
func TestExportsQualifyCollidingToolNames(t *testing.T) {
	var ctx Context
	ctx.Add("tools", []byte(`[
		{"type":"namespace","name":"a","tools":[{"type":"function","name":"run","parameters":{"type":"object","required":["path"]}}]},
		{"type":"namespace","name":"b","tools":[{"type":"function","name":"run","parameters":{"type":"object","required":["query"]}},
			{"type":"function","name":"js","parameters":{"type":"object","required":["code"]}}]},
		{"type":"function","name":"exec","parameters":{"type":"object","required":["cmd"]}}]`))
	call := func(namespace, name, input string) []Message {
		return []Message{{Role: "user", Blocks: []Block{{Type: "text", Text: "Search for hello."}}},
			{ID: Hash{1}, Role: "assistant", Output: true, Blocks: []Block{{Type: "tool_call", SourceType: "function_call",
				ToolName: name, ToolNamespace: namespace, ToolCallID: "call_1", ToolInput: input}}}}
	}
	schemas := func(tools []any, schema func(map[string]any) (string, any)) map[string]string {
		out := map[string]string{}
		for _, tool := range tools {
			name, s := schema(tool.(map[string]any))
			b, _ := json.Marshal(s)
			out[name] = string(b)
		}
		return out
	}
	openai := func(t map[string]any) (string, any) {
		f := t["function"].(map[string]any)
		return f["name"].(string), f["parameters"].(map[string]any)["required"]
	}
	anthropic := func(t map[string]any) (string, any) {
		return t["name"].(string), t["input_schema"].(map[string]any)["required"]
	}
	want := map[string]string{"a__run": `["path"]`, "b__run": `["query"]`, "js": `["code"]`, "exec": `["cmd"]`}
	for _, tc := range []struct{ namespace, name, want string }{
		{"b", "run", "b__run"}, {"a", "run", "a__run"}, {"b", "js", "js"}, {"", "exec", "exec"},
	} {
		path := call(tc.namespace, tc.name, `{"query":"hello"}`)
		chat := must(OpenAIChat(ctx, path, nil))
		if got := schemas(chat["tools"].([]any), openai); !reflect.DeepEqual(got, want) {
			t.Fatalf("openai tools %v", got)
		}
		messages := chat["messages"].([]map[string]any)
		called := messages[len(messages)-1]["tool_calls"].([]any)[0].(map[string]any)["function"].(map[string]any)["name"]
		request := must(AnthropicMessages(ctx, path, nil))
		if got := schemas(request["tools"].([]any), anthropic); !reflect.DeepEqual(got, want) {
			t.Fatalf("anthropic tools %v", got)
		}
		turns := request["messages"].([]map[string]any)
		used := turns[len(turns)-1]["content"].([]any)[0].(map[string]any)["name"]
		if called != tc.want || used != tc.want {
			t.Fatalf("call to %s.%s exported as %v and %v, want %s", tc.namespace, tc.name, called, used, tc.want)
		}
	}
	for _, export := range []func(Context, []Message, []Hash) (map[string]any, error){OpenAIChat, AnthropicMessages} {
		if _, err := export(ctx, call("", "run", `{"query":"hello"}`), []Hash{{1}}); err == nil {
			t.Fatal("exported a call to run without the namespace that says which")
		}
	}
	// A namespace that defines no such tool matches none, even when the
	// name is unique.
	var one Context
	one.Add("tools", []byte(`[{"type":"namespace","name":"a","tools":[{"type":"function","name":"run","parameters":{"type":"object"}}]}]`))
	for _, export := range []func(Context, []Message, []Hash) (map[string]any, error){OpenAIChat, AnthropicMessages} {
		if _, err := export(one, call("a", "run", `{}`), nil); err != nil {
			t.Fatal(err)
		}
		for _, namespace := range []string{"b", ""} {
			if _, err := export(one, call(namespace, "run", `{}`), []Hash{{1}}); err == nil {
				t.Fatalf("exported a call to %q with the schema of a.run", qualify(namespace, "run"))
			}
		}
	}
	if err := ForTraining(one, call("b", "run", `{}`), []Hash{{1}}); err == nil {
		t.Fatal("a call to b.run trains on a.run")
	}
	var twice Context
	twice.Add("tools", []byte(`[{"type":"function","name":"run","parameters":{"required":["path"]}},
		{"type":"function","name":"run","parameters":{"required":["query"]}}]`))
	if _, err := OpenAIChat(twice, call("", "run", "{}"), nil); err == nil {
		t.Fatal("exported a tool defined twice differently")
	}
}

// Neither export dialect can write a hosted tool's call back: Chat
// Completions has none, and Anthropic's results are only in the raw items.
// So a hosted call, its result, and its definition are left out together,
// and the text the model wrote stays.
func TestExportsLeaveOutHostedToolsTogether(t *testing.T) {
	var ctx Context
	ctx.Add("tools", []byte(`[{"type":"function","name":"exec","parameters":{"type":"object"}},
		{"type":"web_search"},{"type":"tool_search"},{"type":"web_search_20250305","name":"web_search","max_uses":5}]`))
	path := []Message{
		{Role: "user", Blocks: []Block{{Type: "text", Text: "Which ClickHouse release added JSON?"}}},
		{ID: Hash{1}, Role: "assistant", Output: true, Blocks: []Block{
			{Type: "tool_call", SourceType: "web_search_call", ToolName: "web_search", ToolCallID: "ws_1", ToolInput: `{"query":"clickhouse json"}`},
			{Type: "tool_call", SourceType: "server_tool_use", ToolName: "web_search", ToolCallID: "srvtoolu_1", ToolInput: `{"query":"clickhouse json"}`},
			{Type: "tool_result", SourceType: "web_search_tool_result", ToolCallID: "srvtoolu_1", Text: "results"},
			{Type: "tool_call", SourceType: "tool_search_call", ToolName: "tool_search", ToolCallID: "ts_1", ToolInput: `{"query":"shell"}`}}},
		{Role: "tool", Blocks: []Block{{Type: "tool_result", SourceType: "tool_search_output", ToolCallID: "ts_1", Text: "exec"}}},
		{ID: Hash{2}, Role: "assistant", Output: true, Blocks: []Block{{Type: "text", Text: "24.8."},
			{Type: "tool_call", SourceType: "function_call", ToolName: "exec", ToolCallID: "call_1", ToolInput: `{}`}}},
	}
	for name, request := range map[string]map[string]any{
		"openai": must(OpenAIChat(ctx, path, nil)), "anthropic": must(AnthropicMessages(ctx, path, nil))} {
		got, _ := json.Marshal(request)
		for _, hosted := range []string{"web_search", "tool_search", "ws_1", "srvtoolu_1", "ts_1", "results"} {
			if strings.Contains(string(got), hosted) {
				t.Fatalf("%s export keeps %s: %s", name, hosted, got)
			}
		}
		if !strings.Contains(string(got), "24.8.") || !strings.Contains(string(got), "call_1") ||
			len(request["tools"].([]any)) != 1 {
			t.Fatalf("%s export lost the rest: %s", name, got)
		}
	}
	if err := ForTraining(ctx, path, []Hash{{1}, {2}}); err != nil {
		t.Fatal(err)
	}
}

// A call makes a training example only with output an export keeps, and
// with every tool that output calls defined in its context. Only the
// call's own outputs count: others on its path are context.
func TestTrainingNeedsOutputAndItsTools(t *testing.T) {
	var tools Context
	tools.Add("tools", []byte(`[{"type":"function","name":"exec","parameters":{"type":"object"}},{"type":"web_search"},
		{"type":"custom","name":"script"}]`))
	user := Message{ID: Hash{1}, Role: "user", Blocks: []Block{{Type: "text", Text: "List the pods."}}}
	interrupted := Message{ID: Hash{7}, Role: "assistant", Output: true, Blocks: []Block{
		{Type: "tool_call", SourceType: "function_call", ToolName: "exec", ToolCallID: "call_2", ToolInput: `{"path":`}}}
	script := Message{ID: Hash{8}, Role: "assistant", Output: true, Blocks: []Block{
		{Type: "tool_call", SourceType: "custom_tool_call", ToolName: "script", ToolCallID: "call_3", ToolInput: `print(1)`}}}
	call := Message{ID: Hash{2}, Role: "assistant", Output: true, Blocks: []Block{
		{Type: "tool_call", SourceType: "function_call", ToolName: "exec", ToolCallID: "call_1", ToolInput: `{}`}}}
	search := Message{ID: Hash{3}, Role: "assistant", Output: true, Blocks: []Block{
		{Type: "tool_call", SourceType: "web_search_call", ToolName: "web_search", ToolCallID: "ws_1"}}}
	answer := Message{ID: Hash{4}, Role: "assistant", Output: true, Blocks: []Block{{Type: "text", Text: "Two pods."}}}
	result := Message{ID: Hash{5}, Role: "tool", Blocks: []Block{{Type: "tool_result", ToolCallID: "call_1"}}}
	for _, tc := range []struct {
		name    string
		ctx     Context
		path    []Message
		outputs []Hash
		ok      bool
	}{
		{"complete", tools, []Message{user, call}, []Hash{call.ID}, true},
		// A failed call that returned nothing ends at its input.
		{"no output", tools, []Message{user}, nil, false},
		{"empty output", tools, []Message{user, {ID: Hash{6}, Role: "assistant", Output: true, Blocks: []Block{{Type: "text"}}}},
			[]Hash{{6}}, false},
		// Only a hosted call, which the export leaves out.
		{"hosted only", tools, []Message{user, search}, []Hash{search.ID}, false},
		// A failed delta call with output but no echo knows no tools.
		{"unknown tools", Context{}, []Message{user, call}, []Hash{call.ID}, false},
		// Earlier outputs are context, not what the example teaches.
		{"earlier call", Context{}, []Message{user, call, result, answer}, []Hash{answer.ID}, true},
		// A failed delta call that sent nothing new and returned nothing
		// ends at the output of the call it continues.
		{"previous output", tools, []Message{user, call}, nil, false},
		// The call it continues ended in a tool call this call's context
		// lacks, and this call answered without input in between.
		{"adjacent earlier output", Context{}, []Message{user, call, answer}, []Hash{answer.ID}, true},
		// An interrupted stream cut the arguments short. A freeform custom
		// tool takes raw text, which is no JSON.
		{"interrupted arguments", tools, []Message{user, interrupted}, []Hash{interrupted.ID}, false},
		{"custom tool", tools, []Message{user, script}, []Hash{script.ID}, true},
	} {
		if err := ForTraining(tc.ctx, tc.path, tc.outputs); (err == nil) != tc.ok {
			t.Fatalf("%s: %v", tc.name, err)
		}
	}
}

// Both exports keep JSON numbers exactly as written, in tool arguments and
// in tool definitions, beyond what a float64 holds.
func TestExportsKeepNumbersExact(t *testing.T) {
	var ctx Context
	ctx.Add("tools", []byte(`[{"type":"function","name":"get","parameters":{"type":"object",`+
		`"properties":{"id":{"type":"integer","maximum":9007199254740993}}}}]`))
	args := `{"id":9007199254740993,"ratio":0.1000000000000000055511151231257827}`
	path := []Message{{Role: "user", Blocks: []Block{{Type: "text", Text: "Get it."}}},
		{ID: Hash{1}, Role: "assistant", Output: true, Blocks: []Block{{Type: "tool_call", SourceType: "function_call",
			ToolName: "get", ToolCallID: "call_1", ToolInput: args}}}}
	for _, tc := range []struct {
		export func(Context, []Message, []Hash) (map[string]any, error)
		want   string
	}{
		{OpenAIChat, `"arguments":` + strconv.Quote(args)},
		{AnthropicMessages, `"input":` + args},
	} {
		var b bytes.Buffer
		enc := json.NewEncoder(&b)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(must(tc.export(ctx, path, nil))); err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(b.String(), tc.want) || !strings.Contains(b.String(), `"maximum":9007199254740993`) {
			t.Fatalf("export changed numbers: %s", b.String())
		}
	}
}

// A call's export teaches only the call's outputs. Earlier assistant turns
// are context: weight 0 in Chat Completions, and never merged into the
// last Anthropic message, which is the call's output alone. An earlier
// interrupted tool call then never becomes a target.
func TestExportsTrainOnlyTheCallsOutputs(t *testing.T) {
	var ctx Context
	ctx.Add("tools", []byte(`[{"type":"function","name":"exec","parameters":{"type":"object"}}]`))
	user := Message{ID: Hash{1}, Role: "user", Blocks: []Block{{Type: "text", Text: "List the pods."}}}
	interrupted := Message{ID: Hash{2}, Role: "assistant", Output: true, Blocks: []Block{
		{Type: "tool_call", SourceType: "function_call", ToolName: "exec", ToolCallID: "call_1", ToolInput: `{"path":`}}}
	result := Message{ID: Hash{3}, Role: "tool", Blocks: []Block{{Type: "tool_result", ToolCallID: "call_1", Text: "bad arguments"}}}
	answer := Message{ID: Hash{4}, Role: "assistant", Output: true, Blocks: []Block{{Type: "text", Text: "Two pods."}}}
	for name, path := range map[string][]Message{
		"after a result": {user, interrupted, result, answer},
		// The call continues the interrupted one without input between.
		"adjacent": {user, interrupted, answer},
	} {
		if err := ForTraining(ctx, path, []Hash{answer.ID}); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		var weights []string
		for _, m := range must(OpenAIChat(ctx, path, []Hash{answer.ID}))["messages"].([]map[string]any) {
			if m["role"] == "assistant" {
				w, _ := json.Marshal(m["weight"])
				weights = append(weights, fmt.Sprintf("%s:%v", w, m["content"]))
			}
		}
		if !reflect.DeepEqual(weights, []string{"0:", "null:Two pods."}) {
			t.Fatalf("%s: openai assistant turns %v", name, weights)
		}
		messages := must(AnthropicMessages(ctx, path, []Hash{answer.ID}))["messages"].([]map[string]any)
		last, _ := json.Marshal(messages[len(messages)-1])
		if string(last) != `{"content":[{"text":"Two pods.","type":"text"}],"role":"assistant"}` {
			t.Fatalf("%s: anthropic last message %s", name, last)
		}
	}
	// Without targets, as for a whole conversation, nothing is weighted.
	chat, _ := json.Marshal(must(OpenAIChat(ctx, []Message{user, interrupted, result, answer}, nil)))
	if strings.Contains(string(chat), "weight") {
		t.Fatalf("conversation export weighted: %s", chat)
	}
}

// Only the exported call's own tool calls must match its definitions.
// Earlier calls were made under definitions that may have changed since,
// such as an MCP server renamed between turns: they keep their own name,
// qualified by their namespace, and never fail the export.
func TestExportsKeepHistoricalToolNames(t *testing.T) {
	var ctx Context
	ctx.Add("tools", []byte(`[{"type":"namespace","name":"new","tools":[{"type":"function","name":"run","parameters":{"type":"object"}}]},
		{"type":"namespace","name":"other","tools":[{"type":"function","name":"run","parameters":{"type":"object"}}]}]`))
	path := []Message{{ID: Hash{1}, Role: "user", Blocks: []Block{{Type: "text", Text: "Run it twice."}}},
		{ID: Hash{2}, Role: "assistant", Output: true, Blocks: []Block{{Type: "tool_call", SourceType: "function_call",
			ToolName: "run", ToolNamespace: "old", ToolCallID: "call_1", ToolInput: `{}`}}},
		{ID: Hash{3}, Role: "tool", Blocks: []Block{{Type: "tool_result", ToolCallID: "call_1", Text: "ok"}}},
		{ID: Hash{4}, Role: "assistant", Output: true, Blocks: []Block{{Type: "tool_call", SourceType: "function_call",
			ToolName: "run", ToolNamespace: "new", ToolCallID: "call_2", ToolInput: `{}`}}}}
	if err := ForTraining(ctx, path, []Hash{{4}}); err != nil {
		t.Fatal(err)
	}
	chat, _ := json.Marshal(must(OpenAIChat(ctx, path, []Hash{{4}}))["messages"])
	anthropic, _ := json.Marshal(must(AnthropicMessages(ctx, path, []Hash{{4}}))["messages"])
	for name, got := range map[string]string{"openai": string(chat), "anthropic": string(anthropic)} {
		if !strings.Contains(got, `"name":"old__run"`) || !strings.Contains(got, `"name":"new__run"`) {
			t.Fatalf("%s export names %s", name, got)
		}
	}
	// The same call as the target still has to match.
	for _, export := range []func(Context, []Message, []Hash) (map[string]any, error){OpenAIChat, AnthropicMessages} {
		if _, err := export(ctx, path[:2], []Hash{{2}}); err == nil {
			t.Fatal("exported a target calling old.run, which its context does not define")
		}
	}
	if err := ForTraining(ctx, path[:2], []Hash{{2}}); err == nil {
		t.Fatal("trained on a call to old.run, which its context does not define")
	}
}

// Historical calls to tools that no current definition has, in any
// namespace, keep their namespaces too, so two removed tools of the same
// name stay apart.
func TestExportsKeepRemovedToolNamespaces(t *testing.T) {
	var ctx Context
	ctx.Add("tools", []byte(`[{"type":"function","name":"read","parameters":{"type":"object"}}]`))
	call := func(id Hash, namespace, callID string) Message {
		return Message{ID: id, Role: "assistant", Output: true, Blocks: []Block{{Type: "tool_call", SourceType: "function_call",
			ToolName: "run", ToolNamespace: namespace, ToolCallID: callID, ToolInput: `{}`}}}
	}
	result := func(id Hash, callID string) Message {
		return Message{ID: id, Role: "tool", Blocks: []Block{{Type: "tool_result", ToolCallID: callID, Text: "ok"}}}
	}
	path := []Message{{ID: Hash{1}, Role: "user", Blocks: []Block{{Type: "text", Text: "Run both, then read."}}},
		call(Hash{2}, "old_a", "call_1"), result(Hash{3}, "call_1"), call(Hash{4}, "old_b", "call_2"), result(Hash{5}, "call_2"),
		{ID: Hash{6}, Role: "assistant", Output: true, Blocks: []Block{{Type: "tool_call", SourceType: "function_call",
			ToolName: "read", ToolCallID: "call_3", ToolInput: `{}`}}}}
	if err := ForTraining(ctx, path, []Hash{{6}}); err != nil {
		t.Fatal(err)
	}
	chat, _ := json.Marshal(must(OpenAIChat(ctx, path, []Hash{{6}}))["messages"])
	anthropic, _ := json.Marshal(must(AnthropicMessages(ctx, path, []Hash{{6}}))["messages"])
	for name, got := range map[string]string{"openai": string(chat), "anthropic": string(anthropic)} {
		if !strings.Contains(got, `"name":"old_a__run"`) || !strings.Contains(got, `"name":"old_b__run"`) ||
			!strings.Contains(got, `"name":"read"`) {
			t.Fatalf("%s export names %s", name, got)
		}
	}
}
