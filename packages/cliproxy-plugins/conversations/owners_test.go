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

// A file writes no call from the proxy's handover on, so its sighting of a
// reply the proxy never returned cannot hold the call. The child's earlier
// copy, from before any handover, holds it, and its usage still counts.
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
	if want := []string{child + " resp_child", child + " resp_parent"}; !reflect.DeepEqual(calls, want) {
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
	count := `{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"output_tokens":5}}}}`
	for _, tc := range []struct {
		name    string
		files   [][]TranscriptLine
		proxied *Proxied
		calls   []string
		tools   int
	}{
		// Older logs record no response IDs.
		{"older logs", files(count, count), nil, []string{parent + " 10:00:02", parent + " 10:00:05", child + " 10:05:06"}, 1},
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
