package conversations

import (
	"bytes"
	"encoding/json"
	"os"
	"path"
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

func transcriptBatch(t *testing.T, proxied *Proxied) (*Normalizer, [][]TranscriptLine) {
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
	replies := repliesOf(files...)
	for _, f := range files {
		n.Transcript(f, replies, proxied)
	}
	return n, files
}

// repliesOf is the first pass of the transcript import, over every file.
func repliesOf(files ...[]TranscriptLine) *Replies {
	r := &Replies{}
	for _, f := range files {
		r.Add(f)
	}
	return r
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

// Every transcript line is one message or event that references the line
// verbatim and records its file, so its llm.transcripts row rebuilds, with
// the source from the file's session row. No two rows share the key
// ClickHouse replaces by, even for a file synced to a second host, which
// shares its session, line numbers, and times.
func TestTranscriptLinesAreKeptExactlyOnce(t *testing.T) {
	_, files := transcriptBatch(t, nil)
	for _, f := range files {
		if strings.HasSuffix(f[0].Path, "019f6478-0000-7000-8000-000000000004.jsonl") {
			synced := append([]TranscriptLine{}, f...)
			for i := range synced {
				synced[i].Host = "ristretto"
			}
			files = append(files, synced)
		}
	}
	n := NewNormalizer()
	replies := repliesOf(files...)
	for _, f := range files {
		n.Transcript(f, replies, nil)
	}
	items := itemsOf(&n.Batch)
	type file struct{ session, host, path string }
	sources := map[file]string{}
	for _, s := range n.Sessions {
		sources[file{s.SessionID, s.Host, s.Path}] = s.Client
	}
	rebuilt := map[TranscriptLine]int{}
	add := func(f file, line string, item Hash) {
		source, ok := sources[f]
		if !ok {
			t.Fatalf("no session row for %+v", f)
		}
		// The file-name session is the path's, or for an OpenCode database,
		// which holds many sessions, the canonical session's.
		session := strings.TrimSuffix(path.Base(f.path), ".jsonl")
		if source == "opencode" {
			session = strings.TrimPrefix(f.session, "opencode:")
		}
		rebuilt[TranscriptLine{Source: source, Host: f.host, Session: session, ID: line, Path: f.path, Line: items[item]}]++
	}
	ids := map[Hash]bool{}
	for _, m := range n.Messages {
		if ids[m.ID] {
			t.Fatalf("two rows for message %v", m.ID)
		}
		ids[m.ID] = true
		// Compaction items and the context Pi sends again are messages from
		// inside a line, as line#item.
		if !strings.Contains(m.Line, "#") {
			add(file{m.SessionID, m.Host, m.Path}, m.Line, m.Item)
		}
	}
	keys := map[[5]string]bool{}
	for _, e := range n.Events {
		key := [5]string{e.SessionID, e.TS, e.Host, e.Path, e.Line}
		if keys[key] {
			t.Fatalf("two events share the key %q", key)
		}
		keys[key] = true
		add(file{e.SessionID, e.Host, e.Path}, e.Line, e.Item)
	}
	total := 0
	for _, f := range files {
		for _, l := range f {
			total++
			l.TS = ""
			if rebuilt[l] != 1 {
				t.Fatalf("%s line %s on %s is rebuilt %d times", l.Path, l.ID, l.Host, rebuilt[l])
			}
			delete(rebuilt, l)
		}
	}
	if len(rebuilt) > 0 {
		t.Fatalf("rows that are no line: %v", rebuilt)
	}
	if total != 59 {
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
	proxied := &Proxied{}
	proxied.Add(session, "", "claude-code", "", "2026-11-10 09:00:00.000")
	n, _ := transcriptBatch(t, proxied)
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

// Pi calls through the proxy carry no session, so CLIProxy names one the
// transcript cannot derive. The replies both recorded, matched by response
// ID, put the transcript in the proxy's session, which then owns its calls.
func TestTranscriptsShareTheProxySessionOfTheirReplies(t *testing.T) {
	p, _ := proxyBatch(t)
	n, _ := transcriptBatch(t, proxiedBy(&p.Batch))
	session := callByID(t, &p.Batch, "chat-1").SessionID
	var lines []string
	for _, m := range n.Messages {
		if m.SessionID == session {
			lines = append(lines, m.Line)
		}
	}
	// The prompt came before the proxy's first call; the replies are the
	// proxy's, so they are events here.
	if !reflect.DeepEqual(lines, []string{"2"}) {
		t.Fatalf("transcript messages %v in %s, want the prompt before the proxy", lines, session)
	}
	for _, c := range n.Calls {
		if c.SessionID == session || strings.HasPrefix(c.ResponseID, "chatcmpl-") {
			t.Fatalf("transcript call %+v counted again", c)
		}
	}
	for _, s := range n.Sessions {
		if strings.HasPrefix(s.SessionID, "pi:01a1c000") {
			t.Fatalf("transcript kept its own session %+v", s)
		}
	}
}

// proxiedBy returns what -proxied passes for the proxy's rows.
func proxiedBy(b *Batch) *Proxied {
	parents := map[string]string{}
	for _, s := range b.Sessions {
		if s.Origin == "proxy" {
			parents[s.SessionID] = s.ParentSessionID
		}
	}
	p := &Proxied{}
	for _, c := range b.Calls {
		p.Add(c.SessionID, parents[c.SessionID], c.Client, c.ResponseID, c.StartedAt)
	}
	return p
}

// Several files can continue one proxy session. Each keeps a session row
// with its host and path, so no file's source is lost.
func TestTranscriptsSharingASessionKeepEverySource(t *testing.T) {
	p, _ := proxyBatch(t)
	var lines []TranscriptLine
	load(t, "transcripts.json", &lines)
	var pi []TranscriptLine
	for _, l := range lines {
		if strings.Contains(l.Path, "01a1c000") {
			pi = append(pi, l)
		}
	}
	copied := append([]TranscriptLine{}, pi...)
	for i := range copied {
		copied[i].Host = "forte"
	}
	n := NewNormalizer()
	proxied := proxiedBy(&p.Batch)
	replies := repliesOf(pi, copied)
	n.Transcript(pi, replies, proxied)
	n.Transcript(copied, replies, proxied)
	session := callByID(t, &p.Batch, "chat-1").SessionID
	var hosts []string
	for _, s := range n.Sessions {
		if s.SessionID == session && s.Path == pi[0].Path {
			hosts = append(hosts, s.Host)
		}
	}
	if !reflect.DeepEqual(hosts, []string{"lungo", "forte"}) {
		t.Fatalf("session rows for hosts %v, want both files", hosts)
	}
}

// A forked sub-agent's file starts with a copy of its parent's history,
// replies included. A copied reply does not make the file its parent's: it
// keeps its own session and parent, the copy is context sent to the model
// with no call, and the sub-agent's own reply is its call, unless the proxy
// has it. A reply another file recorded first is a copy the same way.
func TestSubAgentTranscriptsKeepTheirOwnSession(t *testing.T) {
	parent, child := "codex:019f6478-0000-7000-8000-00000000000a", "codex:019f6478-0000-7000-8000-00000000000a:agent:review"
	file := func(id string, lines ...string) []TranscriptLine {
		var out []TranscriptLine
		for i, l := range lines {
			out = append(out, TranscriptLine{Source: "codex", Host: "lungo", Session: "rollout-" + id, ID: strconv.Itoa(i + 1),
				Path: ".codex/sessions/2026/11/12/rollout-" + id + ".jsonl", Line: l,
				TS: "2026-11-12 10:00:0" + strconv.Itoa(i) + ".000"})
		}
		return out
	}
	user := func(text string) string {
		return `{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"` + text + `"}]}}`
	}
	reply := func(text string) string {
		return `{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"` + text + `"}]}}`
	}
	usage := func(id string) string {
		return `{"type":"token_usage_record","payload":{"response_id":"` + id + `","usage":{"input_tokens":10,"output_tokens":5}}}`
	}
	history := []string{user("Plan the migration."), reply("Plan: three steps."), usage("resp_parent")}
	parentFile := file("2026-11-12T09-59-00-019f6478-0000-7000-8000-00000000000a", append([]string{
		`{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000a"}}`}, history...)...)
	childFile := file("2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000b", append(append([]string{
		`{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000b","source":{"subagent":{"thread_spawn":` +
			`{"parent_thread_id":"019f6478-0000-7000-8000-00000000000a","agent_path":"/root/review"}}}}}`},
		history...), user("Review the plan."), reply("The plan misses a rollback."), usage("resp_child"))...)

	for _, tc := range []struct {
		name    string
		files   [][]TranscriptLine
		proxied func(p *Proxied)
		calls   []string
	}{
		// Only the parent went through the proxy.
		{"parent proxied", [][]TranscriptLine{childFile}, func(p *Proxied) {
			p.Add(parent, "", "codex", "resp_parent", "2026-11-12 09:59:00.000")
		}, []string{"resp_child"}},
		// Both did: the replies disagree, and the proxy owns the child's
		// from its first call on.
		{"both proxied", [][]TranscriptLine{childFile}, func(p *Proxied) {
			p.Add(parent, "", "codex", "resp_parent", "2026-11-12 09:59:00.000")
			p.Add(child, parent, "codex", "resp_child", "2026-11-12 10:00:05.000")
		}, nil},
		// Neither did; the parent's file holds the reply first.
		{"no proxy", [][]TranscriptLine{parentFile, childFile}, nil, []string{"resp_parent", "resp_child"}},
	} {
		n := NewNormalizer()
		var proxied *Proxied
		if tc.proxied != nil {
			proxied = &Proxied{}
			tc.proxied(proxied)
		}
		replies := repliesOf(tc.files...)
		for _, f := range tc.files {
			n.Transcript(f, replies, proxied)
		}
		var sessions []string
		for _, s := range n.Sessions {
			if s.Path == childFile[0].Path {
				sessions = append(sessions, s.SessionID+" < "+s.ParentSessionID)
			}
		}
		if !reflect.DeepEqual(sessions, []string{child + " < " + parent}) {
			t.Fatalf("%s: child file in sessions %v", tc.name, sessions)
		}
		var calls []string
		for _, c := range n.Calls {
			calls = append(calls, c.ResponseID)
		}
		if !reflect.DeepEqual(calls, tc.calls) {
			t.Fatalf("%s: calls %v, want %v", tc.name, calls, tc.calls)
		}
		copies := 0
		for _, m := range n.Messages {
			if m.SessionID != child || m.Line != "3" {
				continue
			}
			copies++
			if m.Output || m.CallID != "" || collapse(n.Messages)[m.ID].Output {
				t.Fatalf("%s: the copied reply is an output: %+v", tc.name, m)
			}
		}
		if copies != 1 {
			t.Fatalf("%s: %d messages for the copied reply", tc.name, copies)
		}
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
	chat, _ := json.Marshal(must(OpenAIChat(Context{}, path))["messages"])
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
	request := must(AnthropicMessages(Context{}, codex))
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
	chat, _ := json.Marshal(must(OpenAIChat(Context{}, path))["messages"])
	want := `[{"content":"What does the worker return?","role":"user"},` +
		`{"content":"","reasoning_content":"Look up the worker.","role":"assistant","tool_calls":[{"function":{"arguments":"{\"code\":\"return 1\"}","name":"execute"},"id":"tool_HD0","type":"function"}]},` +
		`{"content":"1","role":"tool","tool_call_id":"tool_HD0"},` +
		`{"content":"The worker returns 1.","role":"assistant"}]`
	if string(chat) != want {
		t.Fatalf("openai chat\n%s\nwant\n%s", chat, want)
	}
	anthropic, _ := json.Marshal(must(AnthropicMessages(Context{}, path))["messages"])
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
	items := itemsOf(&n.Batch)
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
		ctx.Add("response", []byte(c.ResponseBody))
		path := Path(n.Messages, c.OutputIDs[len(c.OutputIDs)-1])
		if err := ForTraining(ctx, path, c.OutputIDs); err != nil {
			t.Fatalf("%s: %v", tc.call, err)
		}
		chat := must(OpenAIChat(ctx, path))
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
		anthropic := must(AnthropicMessages(ctx, path))
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
	var ctx Context
	for _, p := range c.RequestParts {
		ctx.Add(p.Field, []byte(itemsOf(&n.Batch)[p.Hash]))
	}
	path := Path(n.Messages, c.OutputIDs[len(c.OutputIDs)-1])
	script := `"const r = await tools.exec_command({cmd: 'rg luna'});\ntext(r)"`
	chat := must(OpenAIChat(ctx, path))
	def := chat["tools"].([]any)[0].(map[string]any)
	delete(def["custom"].(map[string]any), "description")
	messages := chat["messages"].([]map[string]any)
	got, _ := json.Marshal([]any{def, messages[len(messages)-1]["tool_calls"]})
	want := `[{"custom":{"format":{"grammar":{"definition":"start: /.+/","syntax":"lark"},"type":"grammar"},"name":"exec"},"type":"custom"},` +
		`[{"custom":{"input":` + script + `,"name":"exec"},"id":"call_1","type":"custom"}]]`
	if string(got) != want {
		t.Fatalf("openai custom tool\n%s\nwant\n%s", got, want)
	}
	anthropic := must(AnthropicMessages(ctx, path))
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
		chat := must(OpenAIChat(ctx, path))
		if got := schemas(chat["tools"].([]any), openai); !reflect.DeepEqual(got, want) {
			t.Fatalf("openai tools %v", got)
		}
		messages := chat["messages"].([]map[string]any)
		called := messages[len(messages)-1]["tool_calls"].([]any)[0].(map[string]any)["function"].(map[string]any)["name"]
		request := must(AnthropicMessages(ctx, path))
		if got := schemas(request["tools"].([]any), anthropic); !reflect.DeepEqual(got, want) {
			t.Fatalf("anthropic tools %v", got)
		}
		turns := request["messages"].([]map[string]any)
		used := turns[len(turns)-1]["content"].([]any)[0].(map[string]any)["name"]
		if called != tc.want || used != tc.want {
			t.Fatalf("call to %s.%s exported as %v and %v, want %s", tc.namespace, tc.name, called, used, tc.want)
		}
	}
	for _, export := range []func(Context, []Message) (map[string]any, error){OpenAIChat, AnthropicMessages} {
		if _, err := export(ctx, call("", "run", `{"query":"hello"}`)); err == nil {
			t.Fatal("exported a call to run without the namespace that says which")
		}
	}
	// A namespace that defines no such tool matches none, even when the
	// name is unique.
	var one Context
	one.Add("tools", []byte(`[{"type":"namespace","name":"a","tools":[{"type":"function","name":"run","parameters":{"type":"object"}}]}]`))
	for _, export := range []func(Context, []Message) (map[string]any, error){OpenAIChat, AnthropicMessages} {
		if _, err := export(one, call("a", "run", `{}`)); err != nil {
			t.Fatal(err)
		}
		for _, namespace := range []string{"b", ""} {
			if _, err := export(one, call(namespace, "run", `{}`)); err == nil {
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
	if _, err := OpenAIChat(twice, call("", "run", "{}")); err == nil {
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
		"openai": must(OpenAIChat(ctx, path)), "anthropic": must(AnthropicMessages(ctx, path))} {
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
		export func(Context, []Message) (map[string]any, error)
		want   string
	}{
		{OpenAIChat, `"arguments":` + strconv.Quote(args)},
		{AnthropicMessages, `"input":` + args},
	} {
		var b bytes.Buffer
		enc := json.NewEncoder(&b)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(must(tc.export(ctx, path))); err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(b.String(), tc.want) || !strings.Contains(b.String(), `"maximum":9007199254740993`) {
			t.Fatalf("export changed numbers: %s", b.String())
		}
	}
}
