package conversations

import (
	"fmt"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// codexFile writes a Codex rollout whose lines are a second apart from start.
func codexFile(host, path, start string, lines ...string) []TranscriptLine {
	var out []TranscriptLine
	for i, l := range lines {
		out = append(out, TranscriptLine{Source: "codex", Host: host, Session: path, ID: strconv.Itoa(i + 1),
			Path: path, Line: l, TS: fmt.Sprintf("%s:%02d.000", start, i)})
	}
	return out
}

func codexUserLine(text string) string {
	return `{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"` + text + `"}]}}`
}

func codexReplyLine(text string) string {
	return `{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"` + text + `"}]}}`
}

func codexUsageLine(id string) string {
	return `{"type":"token_usage_record","payload":{"response_id":"` + id + `","usage":{"input_tokens":10,"output_tokens":5}}}`
}

// forkedFiles returns a parent rollout, a sub-agent forked from it, whose
// file starts with a copy of the parent's reply, and the parent's file
// synced to a second host. The child's path sorts before its parent's, as
// live Codex paths can.
func forkedFiles() [][]TranscriptLine {
	history := []string{codexUserLine("Plan the migration."), codexReplyLine("Plan: three steps."), codexUsageLine("resp_parent")}
	parent := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000a.jsonl",
		"2026-11-12 10:00", append([]string{`{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000a"}}`},
			history...)...)
	child := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T09-00-00-019f6478-0000-7000-8000-00000000000b.jsonl",
		"2026-11-12 10:05", append(append([]string{`{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000b",` +
			`"source":{"subagent":{"thread_spawn":{"parent_thread_id":"019f6478-0000-7000-8000-00000000000a","agent_path":"/root/review"}}}}}`},
			history...), codexUserLine("Review the plan."), codexReplyLine("The plan misses a rollback."), codexUsageLine("resp_child"))...)
	synced := append([]TranscriptLine{}, parent...)
	for i := range synced {
		synced[i].Host = "forte"
	}
	return [][]TranscriptLine{parent, child, synced}
}

// keptRows returns what ClickHouse keeps of runs' calls and messages, in a
// stable order.
func keptRows(runs []*Normalizer) (calls, rows []string) {
	var all []Message
	for _, n := range runs {
		for _, c := range n.Calls {
			calls = append(calls, fmt.Sprintf("%s %s %+v", c.SessionID, c.ResponseID, c))
		}
		for _, e := range n.Events {
			rows = append(rows, fmt.Sprintf("%+v", e))
		}
		for _, s := range n.Sessions {
			rows = append(rows, fmt.Sprintf("%+v", s))
		}
		all = append(all, n.Messages...)
	}
	for _, m := range collapse(all) {
		rows = append(rows, fmt.Sprintf("%+v", m))
	}
	sort.Strings(calls)
	sort.Strings(rows)
	return calls, rows
}

func permutations(n int) [][]int {
	if n == 0 {
		return [][]int{{}}
	}
	var out [][]int
	for _, p := range permutations(n - 1) {
		for i := 0; i <= len(p); i++ {
			out = append(out, append(append(append([]int{}, p[:i]...), n-1), p[i:]...))
		}
	}
	return out
}

// Which file holds a reply's call depends on all files, never on which are
// normalized together or in what order. Any order of the files, and any
// split into runs, gives the same rows: the parent's reply is one call, of
// the first host's copy, and the child's copy is context.
func TestTranscriptReplyOwnershipIgnoresBatches(t *testing.T) {
	files := forkedFiles()
	parent, child := "codex:019f6478-0000-7000-8000-00000000000a", "codex:019f6478-0000-7000-8000-00000000000a:agent:review"
	replies := repliesOf(nil, files...)
	want := ""
	for _, order := range permutations(len(files)) {
		for _, split := range []bool{false, true} {
			var runs []*Normalizer
			for i, f := range order {
				if i == 0 || split {
					runs = append(runs, NewNormalizer())
				}
				runs[len(runs)-1].Transcript(files[f], replies, nil)
			}
			calls, rows := keptRows(runs)
			if len(calls) != 2 || !strings.HasPrefix(calls[0], parent+" resp_parent ") ||
				!strings.HasPrefix(calls[1], child+" resp_child ") {
				t.Fatalf("order %v, split %v: calls %v", order, split, calls)
			}
			for _, n := range runs {
				for _, m := range n.Messages {
					if m.Output && m.SessionID == parent && m.Host != "forte" {
						t.Fatalf("order %v, split %v: %s's copy holds the parent's reply", order, split, m.Host)
					}
				}
			}
			got := strings.Join(append(calls, rows...), "\n")
			if want == "" {
				want = got
			} else if got != want {
				t.Fatalf("order %v, split %v: rows\n%s\nwant\n%s", order, split, got, want)
			}
		}
	}
}

// A file's lines from after the proxy's handover are the proxy's only when
// the proxy returned their reply. A reply it never returned stays with the
// file that made it, the parent, rather than going with the handover or to
// the child's copy; one it returned is the proxy's, in every file.
func TestTranscriptReplyOwnerCanWriteTheCall(t *testing.T) {
	files := forkedFiles()[:2]
	parent, child := "codex:019f6478-0000-7000-8000-00000000000a", "codex:019f6478-0000-7000-8000-00000000000a:agent:review"
	proxied := &Proxied{}
	proxied.Add(parent, "", "codex", "resp_other", "2026-11-12 10:00:00.000")
	replies := repliesOf(proxied, files...)
	n := NewNormalizer()
	for _, f := range files {
		n.Transcript(f, replies, proxied)
	}
	var calls []string
	for _, c := range n.Calls {
		calls = append(calls, c.SessionID+" "+c.ResponseID)
	}
	sort.Strings(calls)
	if want := []string{parent + " resp_parent", child + " resp_child"}; !reflect.DeepEqual(calls, want) {
		t.Fatalf("calls %v, want %v", calls, want)
	}
	// Once the proxy returned the parent's reply, the reply is the
	// proxy's, and neither file writes it.
	proxied.Add(parent, "", "codex", "resp_parent", "2026-11-12 10:00:00.000")
	replies = repliesOf(proxied, files...)
	n = NewNormalizer()
	for _, f := range files {
		n.Transcript(f, replies, proxied)
	}
	calls = nil
	for _, c := range n.Calls {
		calls = append(calls, c.SessionID+" "+c.ResponseID)
	}
	if want := []string{child + " resp_child"}; !reflect.DeepEqual(calls, want) {
		t.Fatalf("calls %v, want %v", calls, want)
	}
}

// A sub-agent copies the replies it starts from, so its parent's file holds
// their calls even when the copy's time ties with the parent's, or a
// skewed clock puts it first, and the copy's path sorts first.
func TestTranscriptReplyOwnerPrefersTheParent(t *testing.T) {
	parent := "codex:019f6478-0000-7000-8000-00000000000a"
	for _, childStart := range []string{"2026-11-12 10:00", "2026-11-12 09:59"} {
		files := forkedFiles()[:2]
		history := len(files[0])
		for i := range files[1] {
			files[1][i].TS = fmt.Sprintf("%s:%02d.000", childStart, i)
		}
		if childStart == "2026-11-12 10:00" && files[1][history-1].TS != files[0][history-1].TS {
			t.Fatal("the copy does not tie")
		}
		replies := repliesOf(nil, files...)
		n := NewNormalizer()
		for _, f := range files {
			n.Transcript(f, replies, nil)
		}
		var calls []string
		for _, c := range n.Calls {
			calls = append(calls, c.SessionID+" "+c.ResponseID)
		}
		sort.Strings(calls)
		if want := []string{parent + " resp_parent", parent + ":agent:review resp_child"}; !reflect.DeepEqual(calls, want) {
			t.Fatalf("child from %s: calls %v, want %v", childStart, calls, want)
		}
	}
}

// A Codex sub-agent's file copies its parent's items, with their provider
// IDs but without the parent's usage records, which older logs lack
// anyway. The copies are matched by item, so each invocation is one call
// and one output tool call, and a copy of a reply the proxy returned is
// the proxy's.
func TestTranscriptCodexCopiesWithoutResponseIDs(t *testing.T) {
	parentID, childID := "019f6478-0000-7000-8000-00000000000a", "019f6478-0000-7000-8000-00000000000b"
	parent, child := "codex:"+parentID, "codex:"+parentID+":agent:review"
	user := codexUserLine("Check the pods.")
	call := `{"type":"response_item","payload":{"type":"function_call","id":"fc_1","name":"exec","arguments":"{}","call_id":"call_1"}}`
	output := `{"type":"response_item","payload":{"type":"function_call_output","call_id":"call_1","output":"2 pods"}}`
	reply := `{"type":"response_item","payload":{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"Two pods."}]}}`
	// Each call's usage follows it in the parent's file only.
	files := func(usage1, usage2 string) [][]TranscriptLine {
		p := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-"+parentID+".jsonl", "2026-11-12 10:00",
			`{"type":"session_meta","payload":{"id":"`+parentID+`"}}`, user, call, usage1, output, reply, usage2)
		c := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T09-00-00-"+childID+".jsonl", "2026-11-12 10:05",
			`{"type":"session_meta","payload":{"id":"`+childID+`","source":{"subagent":{"thread_spawn":`+
				`{"parent_thread_id":"`+parentID+`","agent_path":"/root/review"}}}}}`, user, call, output, reply,
			codexUserLine("Review it."), `{"type":"response_item","payload":{"type":"message","id":"msg_2","role":"assistant",`+
				`"content":[{"type":"output_text","text":"Fine."}]}}`)
		return [][]TranscriptLine{p, c}
	}
	count := func(total int) string {
		return fmt.Sprintf(`{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":%d},`+
			`"last_token_usage":{"output_tokens":5}}}}`, total)
	}
	for _, tc := range []struct {
		name    string
		files   [][]TranscriptLine
		proxied *Proxied
		calls   []string
		tools   int
	}{
		// Older logs record no response IDs.
		{"older logs", files(count(5), count(10)), nil, []string{parent + " 10:00:02", parent + " 10:00:05", child + " 10:05:06"}, 1},
		// The parent's session went through the proxy, which returned its
		// reply; only the parent's file records the response ID.
		{"proxied parent", files(codexUsageLine("resp_1"), codexUsageLine("resp_2")), func() *Proxied {
			p := &Proxied{}
			p.Add(parent, "", "codex", "resp_1", "2026-11-12 10:00:00.000")
			p.Add(parent, "", "codex", "resp_2", "2026-11-12 10:00:04.000")
			return p
		}(), []string{child + " 10:05:06"}, 0},
	} {
		replies := repliesOf(tc.proxied, tc.files...)
		n := NewNormalizer()
		for _, f := range tc.files {
			n.Transcript(f, replies, tc.proxied)
		}
		var calls []string
		for _, c := range n.Calls {
			calls = append(calls, c.SessionID+" "+strings.TrimPrefix(c.StartedAt, "2026-11-12 ")[:8])
		}
		sort.Strings(calls)
		tools := 0
		for _, m := range n.Messages {
			for _, b := range m.Blocks {
				if m.Output && b.Type == "tool_call" {
					tools++
				}
			}
		}
		if !reflect.DeepEqual(calls, tc.calls) || tools != tc.tools {
			t.Fatalf("%s: calls %v and %d output tool calls, want %v and %d", tc.name, calls, tools, tc.calls, tc.tools)
		}
	}
}

// A Codex agent spawned by a sub-agent records the sub-agent's raw thread ID
// as its parent, which is not the sub-agent's session, so their lineages do
// not connect. The nested agent's copy of the sub-agent's reply, tied in
// time and in the lineage that sorts first, still yields to the file that
// records the call's usage, whatever order the files come in.
func TestTranscriptReplyOwnerRecordsTheUsage(t *testing.T) {
	rootID, subID := "019f6478-0000-7000-8000-00000000000b", "019f6478-0000-7000-8000-00000000000a"
	sub := "codex:" + rootID + ":agent:review"
	reply := `{"type":"response_item","payload":{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"Done."}]}}`
	usage := `{"type":"token_usage_record","payload":{"response_id":"resp_sub","usage":{"input_tokens":100,"output_tokens":20}}}`
	subFile := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-"+subID+".jsonl", "2026-11-12 10:00",
		`{"type":"session_meta","payload":{"id":"`+subID+`","source":{"subagent":{"thread_spawn":`+
			`{"parent_thread_id":"`+rootID+`","agent_path":"/root/review"}}}}}`, codexUserLine("Review it."), reply, usage)
	nested := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000c.jsonl",
		"2026-11-12 10:00", `{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000c","source":{"subagent":`+
			`{"thread_spawn":{"parent_thread_id":"`+subID+`","agent_path":"/root/review/deep"}}}}}`, codexUserLine("Review it."), reply)
	if nested[2].TS != subFile[2].TS {
		t.Fatal("the copy does not tie")
	}
	for _, files := range [][][]TranscriptLine{{subFile, nested}, {nested, subFile}} {
		replies := repliesOf(nil, files...)
		n := NewNormalizer()
		for _, f := range files {
			n.Transcript(f, replies, nil)
		}
		if len(n.Calls) != 1 {
			t.Fatalf("%d calls, want 1: %+v", len(n.Calls), n.Calls)
		}
		c := n.Calls[0]
		if c.SessionID != sub || c.ResponseID != "resp_sub" || c.UncachedInputTokens != 100 || c.OutputTokens != 20 {
			t.Fatalf("call %+v, want the sub-agent's with its usage", c)
		}
	}
}

// Codex calls whose first items share a call ID but whose items and
// response IDs differ are distinct calls. The colliding key matches
// neither, so each stays a call, and the collision is reported.
func TestTranscriptItemKeyCollisionsStayDistinct(t *testing.T) {
	call := func(item string) string {
		return `{"type":"response_item","payload":{"type":"function_call","id":"` + item +
			`","name":"exec","arguments":"{}","call_id":"call_1"}}`
	}
	a := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000a.jsonl",
		"2026-11-12 10:00", `{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000a"}}`,
		codexUserLine("Check the pods."), call("fc_1"), codexUsageLine("resp_1"))
	b := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000b.jsonl",
		"2026-11-12 10:00", `{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000b"}}`,
		codexUserLine("Check the nodes."), call("fc_2"), codexUsageLine("resp_2"))
	for _, files := range [][][]TranscriptLine{{a, b}, {b, a}} {
		replies := repliesOf(nil, files...)
		n := NewNormalizer()
		for _, f := range files {
			n.Transcript(f, replies, nil)
		}
		var calls []string
		for _, c := range n.Calls {
			calls = append(calls, c.ResponseID)
		}
		sort.Strings(calls)
		if want := []string{"resp_1", "resp_2"}; !reflect.DeepEqual(calls, want) {
			t.Fatalf("calls %v, want %v", calls, want)
		}
		if got, want := replies.Conflicts(), []string{"item:call_1 resp_1 resp_2"}; !reflect.DeepEqual(got, want) {
			t.Fatalf("conflicts %v, want %v", got, want)
		}
	}
}

// A Codex response's usage record ends it. A remote compaction's response
// writes a usage record and no items before the compacted history, and two
// responses can follow each other with no input between. Each is a call
// of its own with its own usage, rather than the previous call's, and no
// item key names two responses.
func TestTranscriptCodexUsageRecordsEndCalls(t *testing.T) {
	usage := func(id string, input, output int) string {
		return fmt.Sprintf(`{"type":"token_usage_record","payload":{"response_id":%q,"usage":{"input_tokens":%d,"output_tokens":%d}}}`,
			id, input, output)
	}
	reply := func(item, text string) string {
		return `{"type":"response_item","payload":{"type":"message","id":"` + item + `","role":"assistant","content":[{"type":"output_text","text":"` + text + `"}]}}`
	}
	file := codexFile("lungo", ".codex/sessions/2026/11/12/rollout-2026-11-12T10-00-00-019f6478-0000-7000-8000-00000000000a.jsonl",
		"2026-11-12 10:00", `{"type":"session_meta","payload":{"id":"019f6478-0000-7000-8000-00000000000a"}}`,
		codexUserLine("Check the pods."),
		`{"type":"response_item","payload":{"type":"function_call","id":"fc_1","name":"exec","arguments":"{}","call_id":"call_1"}}`,
		usage("resp_1", 100, 20),
		usage("resp_1", 100, 20),
		`{"type":"response_item","payload":{"type":"function_call_output","call_id":"call_1","output":"2 pods"}}`,
		usage("resp_compact", 300, 40),
		`{"type":"compacted","payload":{"replacement_history":[{"type":"message","role":"user","content":[{"type":"input_text","text":"Summary."}]}]}}`,
		reply("msg_2", "Two pods."), usage("resp_2", 50, 7),
		reply("msg_3", "Both ready."), usage("resp_3", 60, 8))
	replies := repliesOf(nil, file)
	n := NewNormalizer()
	n.Transcript(file, replies, nil)
	var calls []string
	for _, c := range n.Calls {
		calls = append(calls, fmt.Sprintf("%s %d/%d %d outputs", c.ResponseID, c.UncachedInputTokens, c.OutputTokens, len(c.OutputIDs)))
	}
	want := []string{"resp_1 100/20 1 outputs", "resp_compact 300/40 0 outputs", "resp_2 50/7 1 outputs", "resp_3 60/8 1 outputs"}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("calls %v, want %v", calls, want)
	}
	if c := replies.Conflicts(); len(c) > 0 {
		t.Fatalf("conflicts %v", c)
	}
}

// Older Codex logs record usage only in token_count events, each the last
// response's counters at a cumulative point. Codex repeats a point it
// already reported, even in the middle of the next response, and a repeat
// is never that response's usage: the response takes the count of its own
// point. Like a usage record, a second point with no output since is a
// call without outputs, so each distinct point counts once, as
// llm.historical_usage counts it.
func TestTranscriptCodexTokenCountsCountEachPointOnce(t *testing.T) {
	count := func(total, input, cached, output int) string {
		return fmt.Sprintf(`{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":%d},`+
			`"last_token_usage":{"input_tokens":%d,"cached_input_tokens":%d,"output_tokens":%d}}}}`, total, input, cached, output)
	}
	record := func(id string, total, input, output int) string {
		return fmt.Sprintf(`{"type":"token_usage_record","payload":{"response_id":%q,"usage":{"input_tokens":%d,"output_tokens":%d},`+
			`"thread_token_usage":{"total_tokens":%d}}}`, id, input, output, total)
	}
	reasoning := func(id string) string {
		return `{"type":"response_item","payload":{"type":"reasoning","id":"` + id + `","summary":[]}}`
	}
	tool := func(id, call string) string {
		return `{"type":"response_item","payload":{"type":"custom_tool_call","id":"` + id + `","status":"completed","call_id":"` + call +
			`","name":"exec","input":"ls"}}`
	}
	output := func(call string) string {
		return `{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"` + call + `","output":"ok"}}`
	}
	for _, tc := range []struct {
		name  string
		lines []string
		calls []string
	}{
		// Lines 99 to 108 of a live rollout: line 104 repeats line 102's
		// point after the next response began.
		{"repeated point", []string{
			reasoning("rs_1"), tool("ctc_1", "call_1"), output("call_1"), count(967038, 76619, 70400, 175),
			reasoning("rs_2"), count(967038, 76619, 70400, 175), reasoning("rs_3"), tool("ctc_3", "call_3"), output("call_3"),
			count(1053815, 86390, 84736, 387),
		}, []string{"76619/175 2 outputs", "86390/387 3 outputs"}},
		{"distinct points", []string{
			codexReplyLine("Two pods."), count(120, 100, 0, 20), count(420, 280, 0, 20), codexReplyLine("Both ready."), count(530, 90, 0, 20),
		}, []string{"100/20 1 outputs", "280/20 0 outputs", "90/20 1 outputs"}},
		// Lines 734 to 751 of a newer live rollout: after a remote
		// compaction, the counts that repeat usage records no longer
		// share their points.
		{"usage records", []string{
			tool("ctc_1", "call_1"), record("resp_1", 13675681, 226073, 636), output("call_1"), count(13675681, 226073, 0, 636),
			record("resp_compact", 13908682, 228018, 4983),
			`{"type":"compacted","payload":{"replacement_history":[{"type":"message","role":"user","content":[{"type":"input_text","text":"Summary."}]}]}}`,
			count(13675681, 0, 0, 0), tool("ctc_2", "call_2"), record("resp_2", 13933730, 25001, 47), output("call_2"),
			count(13700729, 25001, 0, 47),
		}, []string{"226073/636 1 outputs", "228018/4983 0 outputs", "25001/47 1 outputs"}},
		// Threads report their own cumulative totals, which can coincide.
		{"threads share a point", []string{
			codexReplyLine("Two pods."), count(105, 100, 0, 5),
			`{"type":"session_meta","payload":{"id":"019f6a2b-0000-7000-8000-00000000000c"}}`,
			codexReplyLine("Both ready."), count(105, 100, 0, 5),
		}, []string{"100/5 1 outputs", "100/5 1 outputs"}},
		// A count written before its usage record is ignored like the rest.
		{"count before its record", []string{
			tool("ctc_1", "call_1"), count(13675681, 226073, 0, 636), record("resp_1", 13675681, 226073, 636), output("call_1"),
		}, []string{"226073/636 1 outputs"}},
		// A file can mix both: a response with only a count keeps its usage.
		{"count-only response before records", []string{
			codexReplyLine("Two pods."), count(105, 100, 0, 5), tool("ctc_1", "call_1"), record("resp_1", 500, 200, 30), output("call_1"),
			count(500, 200, 0, 30),
		}, []string{"100/5 1 outputs", "200/30 1 outputs"}},
	} {
		file := codexFile("lungo", ".codex/sessions/2026/07/16/rollout-2026-07-16T02-04-50-019f6a2b-0000-7000-8000-00000000000a.jsonl",
			"2026-07-16 09:07", append([]string{`{"type":"session_meta","payload":{"id":"019f6a2b-0000-7000-8000-00000000000a"}}`,
				codexUserLine("Check the pods.")}, tc.lines...)...)
		n := NewNormalizer()
		n.Transcript(file, repliesOf(nil, file), nil)
		var calls []string
		for _, c := range n.Calls {
			calls = append(calls, fmt.Sprintf("%d/%d %d outputs", c.UncachedInputTokens+c.CacheReadTokens, c.OutputTokens, len(c.OutputIDs)))
		}
		if !reflect.DeepEqual(calls, tc.calls) {
			t.Errorf("%s: calls %v, want %v", tc.name, calls, tc.calls)
		}
	}
}

// A sub-agent of an older log copies its parent's history after a copy of
// its parent's session_meta, with the parent's token counts but not every
// item they follow: two copied counts can follow each other, and a copied
// reply can lack its reasoning, so its first item differs. The parent's
// file holds its points, and the sub-agent only its own.
func TestTranscriptCodexCopiedTokenCountsStayWithTheParent(t *testing.T) {
	count := func(total, input int) string {
		return fmt.Sprintf(`{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":%d},`+
			`"last_token_usage":{"input_tokens":%d,"output_tokens":5}}}}`, total, input)
	}
	parentMeta := `{"type":"session_meta","payload":{"id":"019f6a2b-0000-7000-8000-00000000000a"}}`
	reply := `{"type":"response_item","payload":{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"Plan: three steps."}]}}`
	checked := `{"type":"response_item","payload":{"type":"message","id":"msg_3","role":"assistant","content":[{"type":"output_text","text":"Checked."}]}}`
	parent := codexFile("lungo", ".codex/sessions/2026/07/16/rollout-2026-07-16T09-00-00-019f6a2b-0000-7000-8000-00000000000a.jsonl",
		"2026-07-16 09:00", parentMeta, codexUserLine("Plan the migration."), reply, count(105, 100),
		`{"type":"response_item","payload":{"type":"reasoning","id":"rs_2","summary":[]}}`, count(315, 205), codexUserLine("Check it."),
		`{"type":"response_item","payload":{"type":"reasoning","id":"rs_3","summary":[]}}`, checked, count(600, 280))
	child := codexFile("lungo", ".codex/sessions/2026/07/16/rollout-2026-07-16T09-05-00-019f6a2b-0000-7000-8000-00000000000b.jsonl",
		"2026-07-16 09:05", `{"type":"session_meta","payload":{"id":"019f6a2b-0000-7000-8000-00000000000b","source":{"subagent":`+
			`{"thread_spawn":{"parent_thread_id":"019f6a2b-0000-7000-8000-00000000000a","agent_path":"/root/review"}}}}}`,
		parentMeta, codexUserLine("Plan the migration."), reply, count(105, 100), count(315, 205), codexUserLine("Check it."), checked,
		count(600, 280), codexUserLine("Review the plan."), codexReplyLine("It misses a rollback."), count(1000, 680))
	replies := repliesOf(nil, parent, child)
	n := NewNormalizer()
	for _, f := range [][]TranscriptLine{parent, child} {
		n.Transcript(f, replies, nil)
	}
	var calls []string
	for _, c := range n.Calls {
		calls = append(calls, fmt.Sprintf("%s %d %d outputs", strings.TrimPrefix(c.SessionID, "codex:019f6a2b-0000-7000-8000-"),
			c.UncachedInputTokens, len(c.OutputIDs)))
	}
	want := []string{"00000000000a 100 1 outputs", "00000000000a 205 1 outputs", "00000000000a 280 2 outputs",
		"00000000000a:agent:review 680 1 outputs"}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("calls %v, want %v", calls, want)
	}
}
