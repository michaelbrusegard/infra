package conversations

import (
	"bytes"
	"encoding/json"
	"os"
	"reflect"
	"sort"
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

func transcriptBatch(t *testing.T, proxiedSince func(string) string) (*Normalizer, [][]TranscriptLine) {
	t.Helper()
	var lines []TranscriptLine
	load(t, "transcripts.json", &lines)
	var files [][]TranscriptLine
	for i, l := range lines {
		if i == 0 || l.Path != lines[i-1].Path || l.Host != lines[i-1].Host || l.Session != lines[i-1].Session {
			files = append(files, nil)
		}
		files[len(files)-1] = append(files[len(files)-1], l)
	}
	n := NewNormalizer()
	for _, f := range files {
		n.Transcript(f, proxiedSince)
	}
	return n, files
}

func itemsOf(b *Batch) map[Hash]string {
	out := map[Hash]string{}
	for h, item := range archived {
		out[h] = item
	}
	for _, it := range b.Items {
		if requestitems.HashOf([]byte(it.Item)) != it.Hash {
			panic("item does not match its hash")
		}
		out[it.Hash] = it.Item
	}
	return out
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

func TestProxyCallsRebuildTheirSources(t *testing.T) {
	n, fixtures := proxyBatch(t)
	items := itemsOf(&n.Batch)
	for _, f := range fixtures {
		c := callByID(t, &n.Batch, f.Name)
		body := requestitems.Body{Envelope: c.RequestEnvelope, Parts: c.RequestParts}
		for _, p := range c.RequestParts {
			item, ok := items[p.Hash]
			if !ok {
				t.Fatalf("%s: part %s has no item", f.Name, p.Field)
			}
			body.Items = append(body.Items, []byte(item))
		}
		rebuilt := body.JSON()
		if c.RequestEnvelope == "" {
			if !bytes.Equal(rebuilt, f.body()) {
				t.Fatalf("%s: body changed: %s", f.Name, rebuilt)
			}
		} else if !reflect.DeepEqual(decode(t, rebuilt), decode(t, f.body())) {
			t.Fatalf("%s: rebuilt body differs:\n%s", f.Name, rebuilt)
		}
		if c.ResponseBody != f.ResponseBody {
			t.Fatalf("%s: response body changed", f.Name)
		}
	}
	for _, m := range n.Messages {
		if _, ok := items[m.Item]; !ok {
			t.Fatalf("message %v has no item", m.ID)
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
	if truncated.InputID != (Hash{}) || len(truncated.RequestParts) != 1 {
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

func TestTranscriptLinesAreKeptExactlyOnce(t *testing.T) {
	n, files := transcriptBatch(t, nil)
	items := itemsOf(&n.Batch)
	type ref struct{ session, line string }
	rows := map[ref]int{}
	for _, m := range n.Messages {
		if items[m.Item] != "" && strings.HasPrefix(items[m.Item], "{") && m.Line != "" {
			rows[ref{m.SessionID, m.Line}]++
		}
	}
	for _, e := range n.Events {
		rows[ref{e.SessionID, e.Line}]++
	}
	sessions := map[string]Session{}
	for _, s := range n.Sessions {
		sessions[s.SessionID] = s
	}
	total := 0
	for _, f := range files {
		// One OpenCode database holds many sessions.
		s := sessions[transcriptSession(f).SessionID]
		for _, l := range f {
			total++
			// Exactly one row references the line verbatim.
			found := 0
			for _, m := range n.Messages {
				if m.SessionID == s.SessionID && m.Line == l.ID && items[m.Item] == l.Line {
					found++
				}
			}
			for _, e := range n.Events {
				if e.SessionID == s.SessionID && e.Line == l.ID && items[e.Item] == l.Line {
					found++
				}
			}
			if found != 1 {
				t.Fatalf("%s line %s is referenced %d times", l.Path, l.ID, found)
			}
		}
		if s.Host != f[0].Host || s.Path != f[0].Path {
			t.Fatalf("session %+v lost the file's host or path", s)
		}
	}
	if total != 52 {
		t.Fatalf("checked %d lines", total)
	}
}

func TestTranscriptConversations(t *testing.T) {
	n, _ := transcriptBatch(t, nil)
	bySession := map[string][]Message{}
	for _, m := range n.Messages {
		bySession[m.SessionID] = append(bySession[m.SessionID], m)
	}
	leaf := func(session string) []string {
		ms := bySession[session]
		return texts(Path(n.Messages, ms[len(ms)-1].ID))
	}

	// Claude Code: the compaction boundary starts a new root, and the
	// attachment is part of the context.
	cc := "claude:22222222-2222-4222-8222-222222222222"
	if got := leaf(cc); !reflect.DeepEqual(got, []string{
		"user compaction:This session is being continued from a previous conversation. Summary: the 502s come from a stale endpoint.",
		"assistant* text:Restarting the endpoint controller fixes it."}) {
		t.Fatalf("claude code after compaction %q", got)
	}
	before := texts(Path(n.Messages, bySession[cc][4].ID))
	if !reflect.DeepEqual(before, []string{
		"user text:Why is the ingress returning 502?",
		"user text:Contents of CLAUDE.md:\n# Engineering collaboration",
		"assistant* thinking:Check the ingress controller logs.",
		"assistant* tool_call:{\"command\":\"kubectl -n ingress logs deploy/traefik\"}",
		"tool tool_result:upstream connect error"}) {
		t.Fatalf("claude code before compaction %q", before)
	}
	streamed := callByID(t, &n.Batch, "req_011")
	if len(streamed.OutputIDs) != 2 || streamed.OutputTokens != 64 || streamed.CacheWriteTokens != 2000 || streamed.Model != "claude-opus-5" {
		t.Fatalf("streamed claude code call %+v", streamed)
	}
	sessions := map[string]Session{}
	for _, s := range n.Sessions {
		sessions[s.SessionID] = s
	}
	if s := sessions[cc]; s.Title != "Debug ingress 502" || s.Cwd != "/Users/michaelbrusegard/Projects/infra" {
		t.Fatalf("claude code session %+v", s)
	}
	if s := sessions[cc+":agent:a77aa77aa77aa77aa"]; s.ParentSessionID != cc {
		t.Fatalf("claude code agent session %+v", s)
	}

	// Codex: outputs between inputs form a call with the next usage record;
	// compaction restarts the context from the replacement history.
	cx := "codex:019f6478-0000-7000-8000-000000000003"
	if got := leaf(cx); !reflect.DeepEqual(got, []string{
		"user text:Add a Renovate rule for flake inputs.", "system compaction:", "user text:Now open a PR."}) {
		t.Fatalf("codex after compaction %q", got)
	}
	var codexCalls []Call
	for _, c := range n.Calls {
		if c.SessionID == cx {
			codexCalls = append(codexCalls, c)
		}
	}
	if len(codexCalls) != 2 || codexCalls[0].UncachedInputTokens != 8000 || codexCalls[0].Model != "gpt-5.5" ||
		codexCalls[1].CacheReadTokens != 8000 || codexCalls[1].ResponseID != "resp_h2" || len(codexCalls[0].OutputIDs) != 2 {
		t.Fatalf("codex calls %+v", codexCalls)
	}
	if s := sessions["codex:019f6478-0000-7000-8000-000000000003:agent:renovate_review"]; s.ParentSessionID != cx {
		t.Fatalf("codex agent session %+v", sessions)
	}

	// Pi: entries that are not messages are skipped in the tree. After a
	// compaction the context is the summary and the entries from
	// firstKeptEntryId on, sent again; the original branch stays.
	pi := "pi:01a039ec-0000-7000-8000-000000000005"
	if got := leaf(pi); !reflect.DeepEqual(got, []string{
		"user compaction:## Goal\nMake the tofu approval test pass.",
		"assistant thinking:Run the script. | tool_call:{\"command\":\"bash gitops/espresso/tests/tofu-approval.sh\"}",
		"tool tool_result:FAIL: unapproved plan",
		"assistant* text:Approved the plan; the test passes."}) {
		t.Fatalf("pi after compaction %q", got)
	}
	var piOriginal Hash
	for _, m := range bySession[pi] {
		if m.Line == "5" {
			piOriginal = m.ID
		}
	}
	if got := texts(Path(n.Messages, piOriginal)); !reflect.DeepEqual(got, []string{
		"user text:Run the tofu approval test.",
		"assistant* thinking:Run the script. | tool_call:{\"command\":\"bash gitops/espresso/tests/tofu-approval.sh\"}",
		"tool tool_result:FAIL: unapproved plan"}) {
		t.Fatalf("pi before compaction %q", got)
	}
	for _, m := range bySession[pi] {
		if m.Role == "tool" && !m.Blocks[0].IsError {
			t.Fatal("pi tool failure lost")
		}
	}

	// OpenCode: older exports keep parts as separate records; newer ones
	// inline them, and records are ordered by time.
	if got := leaf("opencode:ses_10bd0be90ffeFixtureOldAAAA"); !reflect.DeepEqual(got, []string{
		"user text:t3code isnt saving conversations across reboots.",
		"assistant* thinking:**Investigating the state directory** | tool_call:{\"filePath\":\"modules/home/t3code.nix\"} | tool_result:File not found"}) {
		t.Fatalf("opencode %q", got)
	}
	if got := leaf("opencode:ses_e43a828d7ffeFixtureNewBBBB"); !reflect.DeepEqual(got, []string{
		"user text:What does the worker return?",
		"assistant* thinking:Look up the worker. | tool_call:{\"code\":\"return 1\"} | tool_result:1 | text:The worker returns 1."}) {
		t.Fatalf("opencode inline %q", got)
	}
}

// The proxy owns a session from its first proxied call on. The transcript
// keeps what came before as messages and calls, and its later lines as
// events, so earlier history is kept and nothing is counted twice.
func TestTranscriptsOwnHistoryBeforeTheProxy(t *testing.T) {
	session := "claude:11111111-1111-4111-8111-111111111111"
	since := func(s string) string {
		if s == session {
			return "2026-11-10 09:00:00.000"
		}
		return ""
	}
	n, _ := transcriptBatch(t, since)
	var lines []string
	for _, m := range n.Messages {
		if m.SessionID == session {
			lines = append(lines, m.Line)
		}
	}
	if !reflect.DeepEqual(lines, []string{"1"}) {
		t.Fatalf("transcript messages %v, want the line before the proxy", lines)
	}
	var events []string
	for _, e := range n.Events {
		if e.SessionID == session {
			events = append(events, e.Line)
		}
	}
	if !reflect.DeepEqual(events, []string{"2"}) {
		t.Fatalf("transcript events %v, want the line after the proxy", events)
	}
	for _, c := range n.Calls {
		if c.SessionID == session {
			t.Fatalf("transcript call %+v after the proxy took over", c)
		}
	}
	// Other sessions are untouched.
	all, _ := transcriptBatch(t, nil)
	if len(all.Messages) != len(n.Messages)+1 {
		t.Fatalf("%d messages with the boundary, %d without", len(n.Messages), len(all.Messages))
	}
}

// Claude Code writes an entry again when it resumes a session. The node
// keeps the first line, and the repeat stays referenced as an event.
func TestRepeatedTranscriptEntriesKeepEveryLine(t *testing.T) {
	n, _ := transcriptBatch(t, nil)
	items := itemsOf(&n.Batch)
	session := "claude:22222222-2222-4222-8222-222222222222"
	var first, repeat int
	for _, m := range n.Messages {
		if m.SessionID == session && strings.Contains(items[m.Item], `"uuid":"x2"`) {
			first++
		}
	}
	for _, e := range n.Events {
		if e.SessionID == session && e.Type == "repeat" && strings.Contains(items[e.Item], `"slug":"debug-ingress"`) {
			repeat++
		}
	}
	if first != 1 || repeat != 1 {
		t.Fatalf("%d messages and %d repeat events for the repeated entry", first, repeat)
	}
	if c := callByID(t, &n.Batch, "req_011"); len(c.OutputIDs) != 2 {
		t.Fatalf("repeated output counted again: %+v", c.OutputIDs)
	}
}

// contentRoot is the part of a raw item that holds content: transcript
// lines wrap it in their own metadata.
func contentRoot(m Message, raw []byte) any {
	o := parse(raw)
	switch m.Format {
	case "claude-code":
		if r, ok := o["rendered"]; ok {
			return map[string]any{"rendered": value(r)}
		}
		return value(o["message"])
	case "codex":
		return value(o["payload"])
	case "pi":
		if o["message"] == nil {
			return map[string]any{"summary": value(o["summary"])}
		}
		return value(o["message"])
	case "opencode":
		return value(o["data"])
	}
	return value(raw)
}

// Keys whose strings are conversation content in some dialect.
var contentKeys = map[string]bool{"text": true, "thinking": true, "arguments": true, "input": true,
	"output": true, "content": true, "summary": true, "rendered": true, "refusal": true,
	"reasoning_content": true, "error": true}

// Every content string in a raw item must appear in an extracted block, and
// every extracted string must come from the raw item: the columns neither
// drop nor invent content.
func TestBlocksMatchRawItems(t *testing.T) {
	p, _ := proxyBatch(t)
	tr, _ := transcriptBatch(t, nil)
	checked := 0
	for _, b := range []*Batch{&p.Batch, &tr.Batch} {
		items := itemsOf(b)
		for _, m := range b.Messages {
			if m.Format == "proxy" || m.Line != "" && strings.Contains(m.Line, "#") {
				continue
			}
			raw := []byte(items[m.Item])
			if m.Format == "opencode" && len(m.Blocks) > 0 {
				// Older OpenCode parts are separate records.
				if parse(raw).obj("data")["content"] == nil {
					continue
				}
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
			walk("", contentRoot(m, raw))
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
	}
	if checked < 40 {
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

func TestExports(t *testing.T) {
	n, _ := proxyBatch(t)
	path := Path(n.Messages, callByID(t, &n.Batch, "claude-2").OutputIDs[0])
	chat, _ := json.Marshal(OpenAIChat(Context{}, path)["messages"])
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
	request := AnthropicMessages(Context{}, codex)
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

// OpenCode keeps reasoning, a tool call, its result, and the answer in one
// assistant message; the export keeps them in that order.
func TestExportsKeepBlockOrder(t *testing.T) {
	n, _ := transcriptBatch(t, nil)
	var path []Message
	for _, m := range n.Messages {
		if m.SessionID == "opencode:ses_e43a828d7ffeFixtureNewBBBB" {
			path = append(path, m)
		}
	}
	chat, _ := json.Marshal(OpenAIChat(Context{}, path)["messages"])
	want := `[{"content":"What does the worker return?","role":"user"},` +
		`{"content":"","reasoning_content":"Look up the worker.","role":"assistant","tool_calls":[{"function":{"arguments":"{\"code\":\"return 1\"}","name":"execute"},"id":"tool_HD0","type":"function"}]},` +
		`{"content":"1","role":"tool","tool_call_id":"tool_HD0"},` +
		`{"content":"The worker returns 1.","role":"assistant"}]`
	if string(chat) != want {
		t.Fatalf("openai chat\n%s\nwant\n%s", chat, want)
	}
	anthropic, _ := json.Marshal(AnthropicMessages(Context{}, path)["messages"])
	want = `[{"content":[{"text":"What does the worker return?","type":"text"}],"role":"user"},` +
		`{"content":[{"thinking":"Look up the worker.","type":"thinking"},{"id":"tool_HD0","input":{"code":"return 1"},"name":"execute","type":"tool_use"}],"role":"assistant"},` +
		`{"content":[{"content":"1","is_error":false,"tool_use_id":"tool_HD0","type":"tool_result"}],"role":"user"},` +
		`{"content":[{"text":"The worker returns 1.","type":"text"}],"role":"assistant"}]`
	if string(anthropic) != want {
		t.Fatalf("anthropic\n%s\nwant\n%s", anthropic, want)
	}
}

// A call's export carries what the call sent beside its messages: the
// system prompt or instructions, and the tools, from its request parts.
func TestExportsCarryCallContext(t *testing.T) {
	n, _ := proxyBatch(t)
	items := itemsOf(&n.Batch)
	for _, tc := range []struct {
		call, system string
		tools        []string
	}{
		{"claude-2", "You are Claude Code, Anthropic's official CLI for Claude.", []string{"Bash", "Read"}},
		// Freeform custom tools have no schema and are kept as they are.
		{"codex-1", "You are Codex", []string{"raw:exec", "update_plan"}},
	} {
		c := callByID(t, &n.Batch, tc.call)
		var ctx Context
		env := parse([]byte(c.RequestEnvelope))
		for _, field := range []string{"system", "instructions", "tools"} {
			if raw, ok := env[field]; ok {
				ctx.Add(field, raw)
			}
		}
		for _, p := range c.RequestParts {
			ctx.Add(p.Field, []byte(items[p.Hash]))
		}
		path := Path(n.Messages, c.OutputIDs[len(c.OutputIDs)-1])
		chat := OpenAIChat(ctx, path)
		first := chat["messages"].([]map[string]any)[0]
		if first["role"] != "system" || !strings.HasPrefix(first["content"].(string), tc.system) {
			t.Fatalf("%s: first message %v", tc.call, first)
		}
		var names []string
		for _, tool := range chat["tools"].([]any) {
			if fn, ok := tool.(map[string]any)["function"].(map[string]any); ok && fn["parameters"] != nil {
				names = append(names, fn["name"].(string))
			} else {
				names = append(names, "raw:"+tool.(map[string]any)["name"].(string))
			}
		}
		if !reflect.DeepEqual(names, tc.tools) {
			t.Fatalf("%s: openai tools %v", tc.call, names)
		}
		anthropic := AnthropicMessages(ctx, path)
		names = nil
		for _, tool := range anthropic["tools"].([]any) {
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
	if !bytes.Contains(c, []byte(`"output_ids":["`)) || !bytes.Contains(c, []byte(`"request_parts":[{"field":`)) {
		t.Fatalf("call row %s", c)
	}
}

func TestProxyRunsDoNotRewriteArchivedItems(t *testing.T) {
	n, fixtures := proxyBatch(t)
	written := map[Hash]bool{}
	for _, it := range n.Items {
		written[it.Hash] = true
	}
	for _, f := range fixtures {
		for _, p := range f.stored().RequestParts {
			// System prompts and tools are per-call context and never become
			// messages, so the run has no reason to write them.
			if (p.Field == "system" || p.Field == "tools" || p.Field == "instructions") && written[p.Hash] {
				t.Fatalf("%s: archived %s item written again", f.Request.RequestID, p.Field)
			}
		}
	}
}
