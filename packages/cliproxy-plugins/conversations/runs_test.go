package conversations

import (
	"bytes"
	"encoding/json"
	"fmt"
	"reflect"
	"sort"
	"strings"
	"testing"
)

func storedRequests(t *testing.T) map[string]Request {
	t.Helper()
	var fixtures []proxyFixture
	load(t, "proxy.json", &fixtures)
	out := map[string]Request{}
	for _, f := range fixtures {
		out[f.Name] = f.stored()
	}
	return out
}

// byStart orders requests the way requests.sql does.
func byStart(requests []Request) []Request {
	out := append([]Request{}, requests...)
	sort.SliceStable(out, func(i, j int) bool {
		return out[i].StartedAt+out[i].RequestID < out[j].StartedAt+out[j].RequestID
	})
	return out
}

// collapse keeps the rows ReplacingMergeTree keeps: the highest version,
// and the last written among equals.
func collapse(messages []Message) map[Hash]Message {
	out := map[Hash]Message{}
	for _, m := range messages {
		if kept, ok := out[m.ID]; !ok || m.Version >= kept.Version {
			out[m.ID] = m
		}
	}
	return out
}

// stateOf returns what state.sql would for the sessions of requests, from
// the rows earlier runs wrote.
func stateOf(b *Batch, requests []Request) []State {
	sessions := map[string]bool{}
	for _, r := range requests {
		sessions[SessionOf(r)] = true
	}
	var out []State
	for _, m := range collapse(b.Messages) {
		if sessions[m.SessionID] {
			out = append(out, State{SessionID: m.SessionID, ID: m.ID, Seq: m.Seq, Version: Uint64(m.Version)})
		}
	}
	for _, c := range b.Calls {
		if sessions[c.SessionID] && c.ResponseID != "" {
			leaf := c.InputID
			if len(c.OutputIDs) > 0 {
				leaf = c.OutputIDs[len(c.OutputIDs)-1]
			}
			out = append(out, State{SessionID: c.SessionID, ID: leaf, ResponseID: c.ResponseID})
		}
	}
	return out
}

// Proxy calls keep every llm.requests column verbatim, so the archive could
// be dropped: request_id is call_id, and the two columns whose names hold
// canonical values are kept as source_session_id and source_model.
func TestProxyCallsKeepEveryRequestColumn(t *testing.T) {
	n, fixtures := proxyBatch(t)
	renamed := map[string]string{"request_id": "call_id", "session_id": "source_session_id", "model": "source_model"}
	for _, f := range fixtures {
		var request, call map[string]json.RawMessage
		data, _ := json.Marshal(f.stored())
		json.Unmarshal(data, &request)
		data, _ = json.Marshal(callByID(t, &n.Batch, f.Name))
		json.Unmarshal(data, &call)
		for column, v := range request {
			// Joined in by requests.sql, not columns of llm.requests.
			if column == "items" || strings.HasPrefix(column, "usage_") {
				continue
			}
			name := column
			if r, ok := renamed[column]; ok {
				name = r
			}
			if !bytes.Equal(call[name], v) {
				t.Fatalf("%s: %s is %s in the call, %s in the request", f.Name, column, call[name], v)
			}
		}
	}
}

// A run restores the nodes and response leaves of the sessions it touches,
// so splitting the requests into two runs anywhere gives the same rows as
// one run, and the second run writes no node again.
func TestRunsSplitAtEveryBoundary(t *testing.T) {
	var fixtures []proxyFixture
	load(t, "proxy.json", &fixtures)
	var requests []Request
	for _, f := range fixtures {
		requests = append(requests, f.stored())
	}
	whole := NewNormalizer()
	for _, r := range byStart(requests) {
		whole.Request(r)
	}
	wantMessages := collapse(whole.Messages)
	wantCalls := map[string]Call{}
	for _, c := range whole.Calls {
		wantCalls[c.CallID] = c
	}
	// Fixture order is not start order, so some splits also deliver an
	// earlier request in the later run, as a late completion does.
	for k := 1; k < len(requests); k++ {
		first := NewNormalizer()
		for _, r := range byStart(requests[:k]) {
			first.Request(r)
		}
		rest := byStart(requests[k:])
		second := NewNormalizer()
		for _, s := range stateOf(&first.Batch, rest) {
			second.Restore(s)
		}
		for _, r := range rest {
			second.Request(r)
		}
		written := map[Hash]bool{}
		for _, m := range first.Messages {
			written[m.ID] = true
		}
		for _, m := range second.Messages {
			if written[m.ID] {
				t.Fatalf("split at %d: the second run wrote %s's node again: %+v", k, m.CallID, m)
			}
		}
		got := collapse(append(append([]Message{}, first.Messages...), second.Messages...))
		if !reflect.DeepEqual(got, wantMessages) {
			for id, m := range wantMessages {
				if !reflect.DeepEqual(got[id], m) {
					t.Fatalf("split at %d: node\n%+v\nwant\n%+v", k, got[id], m)
				}
			}
			t.Fatalf("split at %d: %d nodes, want %d", k, len(got), len(wantMessages))
		}
		for _, c := range append(append([]Call{}, first.Calls...), second.Calls...) {
			if !reflect.DeepEqual(c, wantCalls[c.CallID]) {
				t.Fatalf("split at %d: call\n%+v\nwant\n%+v", k, c, wantCalls[c.CallID])
			}
		}
	}
}

// Even without restored state, a full-resend client sending a reply back
// cannot replace the reply's row: the output outranks every resent copy.
func TestResendKeepsOutputProvenance(t *testing.T) {
	requests := storedRequests(t)
	first, second := NewNormalizer(), NewNormalizer()
	first.Request(requests["claude-1"])
	second.Request(requests["claude-2"])
	reply := callByID(t, &first.Batch, "claude-1").OutputIDs[0]
	got := collapse(append(append([]Message{}, first.Messages...), second.Messages...))[reply]
	if !got.Output || got.CallID != "claude-1" || got.Model != "claude-opus-5-5" || got.TS != "2026-11-10 09:00:05.000" {
		t.Fatalf("resent reply replaced the output: %+v", got)
	}
	if version(false, "1970-01-01 00:00:00.000") >= version(true, "2100-01-01 00:00:00.000") {
		t.Fatal("an input row outranks an output row")
	}
	if version(true, "2026-11-10 09:00:05.000") <= version(true, "2026-11-10 09:00:06.000") {
		t.Fatal("a later row outranks an earlier one")
	}
}

// A delta request whose previous response is not normalized yet is held
// back while it is recent, and placed once the response arrives. Only an
// old one starts at a missing_context marker.
func TestRecentDeltaRequestsWaitForTheirPreviousResponse(t *testing.T) {
	requests := storedRequests(t)
	early := NewNormalizer()
	early.HoldAfter = "2026-11-10 10:00:00.000"
	if early.Request(requests["codex-2"]) {
		t.Fatal("placed a request before its previous response")
	}
	if len(early.Messages)+len(early.Calls)+len(early.Sessions)+len(early.Items) != 0 {
		t.Fatal("a held request wrote rows")
	}
	later := NewNormalizer()
	later.HoldAfter = early.HoldAfter
	later.Request(requests["codex-1"])
	if !later.Request(requests["codex-2"]) {
		t.Fatal("held a request whose previous response is known")
	}
	path := texts(Path(later.Messages, callByID(t, &later.Batch, "codex-2").OutputIDs[0]))
	if len(path) != 6 || strings.HasPrefix(path[0], "system other:") {
		t.Fatalf("placed request %q", path)
	}
	old := NewNormalizer()
	old.HoldAfter = "2026-11-10 11:00:00.000"
	if !old.Request(requests["codex-2"]) {
		t.Fatal("held an old request")
	}
	if got := texts(Path(old.Messages, callByID(t, &old.Batch, "codex-2").InputID))[0]; got != "system other:resp_A" {
		t.Fatalf("old request starts at %q", got)
	}
}

// The plugin writes a request before CLIProxy writes its usage, whose
// session tells a Claude sub-agent from its parent. A recent request read
// in between is held back, and placed in the sub-agent's session once its
// usage arrives. Only an old one without usage falls back to the header.
func TestRecentRequestsWaitForTheirUsage(t *testing.T) {
	agent := storedRequests(t)["claude-agent"]
	early := agent
	early.UsageSessionID, early.UsageParentSessionID, early.UsageAttempts = "", "", 0
	n := NewNormalizer()
	n.HoldAfter = "2026-11-10 09:00:00.000"
	if n.Request(early) {
		t.Fatalf("placed a request before its usage, in %s", n.Calls[0].SessionID)
	}
	if len(n.Messages)+len(n.Calls)+len(n.Sessions)+len(n.Items) != 0 {
		t.Fatal("a held request wrote rows")
	}
	if !n.Request(agent) || n.Calls[0].SessionID != agent.UsageSessionID {
		t.Fatalf("request with usage placed in %+v", n.Calls)
	}
	// A call that ran longer than the hold is recent by its completion,
	// which is when it and its usage land.
	long := NewNormalizer()
	long.HoldAfter = "2026-11-10 09:00:07.000"
	if early.StartedAt >= long.HoldAfter || long.Request(early) {
		t.Fatal("placed a long request that just completed before its usage")
	}
	old := NewNormalizer()
	old.HoldAfter = "2026-11-10 10:00:00.000"
	if !old.Request(early) || old.Calls[0].SessionID != "claude:11111111-1111-4111-8111-111111111111" {
		t.Fatal("held an old request without usage")
	}
}

// Transport fields are dropped only where the dialects put them. The same
// names inside a tool's input are content, so tool calls that differ there
// stay different nodes.
func TestTransportFieldsOnlyAtProtocolLocations(t *testing.T) {
	same := func(format, a, b string) bool { return contentKey(format, []byte(a)) == contentKey(format, []byte(b)) }
	if same("anthropic",
		`{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"path":"p.json","content":{"cache_control":{"type":"ephemeral"}}}}]}`,
		`{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"path":"p.json","content":{}}}]}`) {
		t.Fatal("tool inputs differing in a cache_control key are one node")
	}
	if same("openai-responses",
		`{"type":"web_search_call","id":"ws_1","action":{"type":"search","query":"logprobs","logprobs":true}}`,
		`{"type":"web_search_call","id":"ws_1","action":{"type":"search","query":"logprobs"}}`) {
		t.Fatal("hosted tool actions differing in a logprobs key are one node")
	}
	if !same("anthropic",
		`{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"ok","cache_control":{"type":"ephemeral"}}],"cache_control":{"type":"ephemeral"}}]}`,
		`{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"ok"}]}]}`) {
		t.Fatal("cache markers on blocks and tool result blocks split a node")
	}
	if !same("openai-responses",
		`{"type":"message","role":"assistant","id":"msg_1","status":"completed","content":[{"type":"output_text","text":"hi","annotations":[],"logprobs":[]}]}`,
		`{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hi","annotations":[]}]}`) {
		t.Fatal("a reply and its resent copy are different nodes")
	}
}

// An Anthropic stream cut off before a block's stop event keeps the tool
// arguments that streamed. The expected message is written here, and the
// stream generated from it, so the test does not trust the assembler.
func TestInterruptedAnthropicStreamKeepsArguments(t *testing.T) {
	want := []any{
		map[string]any{"type": "text", "text": "Listing pods."},
		map[string]any{"type": "tool_use", "id": "toolu_X", "name": "Bash",
			"input": map[string]any{"command": "kubectl get pods -A", "timeout": 30}},
	}
	args, _ := json.Marshal(want[1].(map[string]any)["input"])
	var stream []string
	event := func(v map[string]any) {
		b, _ := json.Marshal(v)
		stream = append(stream, "event: "+v["type"].(string)+"\ndata: "+string(b))
	}
	event(map[string]any{"type": "message_start", "message": map[string]any{"id": "msg_X", "type": "message",
		"role": "assistant", "model": "claude-opus-5-5", "content": []any{}, "usage": map[string]any{"input_tokens": 5}}})
	event(map[string]any{"type": "content_block_start", "index": 0, "content_block": map[string]any{"type": "text", "text": ""}})
	for _, s := range []string{"Listing ", "pods."} {
		event(map[string]any{"type": "content_block_delta", "index": 0, "delta": map[string]any{"type": "text_delta", "text": s}})
	}
	event(map[string]any{"type": "content_block_stop", "index": 0})
	event(map[string]any{"type": "content_block_start", "index": 1, "content_block": map[string]any{"type": "tool_use",
		"id": "toolu_X", "name": "Bash", "input": map[string]any{}}})
	var chunks []string
	for i := 0; i < len(args); i += 7 {
		chunks = append(chunks, string(args[i:min(i+7, len(args))]))
		event(map[string]any{"type": "content_block_delta", "index": 1,
			"delta": map[string]any{"type": "input_json_delta", "partial_json": chunks[len(chunks)-1]}})
	}
	// The connection drops here, before content_block_stop and message_stop.
	content := func(stream []string) string {
		r := anthropicResponse(events(strings.Join(stream, "\n\n")))
		if len(r.outputs) != 1 {
			t.Fatalf("%d outputs", len(r.outputs))
		}
		return fmt.Sprint(decode(t, encode(decode(t, r.outputs[0]).(map[string]any)["content"])))
	}
	if got, expected := content(stream), fmt.Sprint(decode(t, encode(want))); got != expected {
		t.Fatalf("content\n%s\nwant\n%s", got, expected)
	}
	// Cut inside the arguments, what streamed is kept as text.
	want[1].(map[string]any)["input"] = strings.Join(chunks[:len(chunks)-1], "")
	if got, expected := content(stream[:len(stream)-1]), fmt.Sprint(decode(t, encode(want))); got != expected {
		t.Fatalf("content cut in the arguments\n%s\nwant\n%s", got, expected)
	}
}
