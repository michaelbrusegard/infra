package conversations

import (
	"fmt"
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
	replies := repliesOf(files...)
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
