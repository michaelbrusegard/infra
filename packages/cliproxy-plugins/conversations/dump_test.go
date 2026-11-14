package conversations

import (
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"testing"

	"cliproxy-plugins/requestitems"
)

// gitops/espresso/tests/llm-conversations.py inserts these source rows into
// the real ClickHouse schema and normalizes them from there.
var dump = flag.String("dump", "", "write the fixtures as source table rows to this directory")

func TestDumpSources(t *testing.T) {
	if *dump == "" {
		t.Skip("no -dump directory")
	}
	var fixtures []proxyFixture
	load(t, "proxy.json", &fixtures)
	var lines []TranscriptLine
	load(t, "transcripts.json", &lines)
	rows := map[string][]any{}
	seen := map[Hash]bool{}
	for _, f := range fixtures {
		r := f.stored()
		for i, p := range r.RequestParts {
			if !seen[p.Hash] {
				seen[p.Hash] = true
				rows["llm.request_items"] = append(rows["llm.request_items"], Item{p.Hash, r.Items[i]})
			}
		}
		rows["llm.requests"] = append(rows["llm.requests"], map[string]any{
			"request_id": r.RequestID, "trace_id": r.TraceID, "session_id": r.SessionID,
			"started_at": r.StartedAt, "completed_at": r.CompletedAt, "source_format": r.SourceFormat,
			"model": r.Model, "requested_model": r.RequestedModel, "stream": r.Stream, "outcome": r.Outcome,
			"status_code": r.StatusCode, "error": r.Error, "user_agent": r.UserAgent, "truncated": r.Truncated,
			"request_envelope": r.RequestEnvelope, "request_parts": nonNil(r.RequestParts),
			"response_body": r.ResponseBody,
		})
		if r.UsageSessionID != "" {
			rows["llm.usage"] = append(rows["llm.usage"], map[string]any{
				"request_id": "usage-" + r.RequestID, "trace_id": r.TraceID, "session_id": r.UsageSessionID,
				"parent_session_id": r.UsageParentSessionID, "requested_at": r.StartedAt,
			})
		}
	}
	for _, l := range lines {
		// ClickHouse derives ts from the line, as it did for the backfill.
		rows["llm.transcripts"] = append(rows["llm.transcripts"], map[string]any{
			"source": l.Source, "host": l.Host, "session": l.Session, "id": l.ID, "path": l.Path, "line": l.Line,
		})
	}
	for table, list := range rows {
		f, err := os.Create(filepath.Join(*dump, table+".jsonl"))
		if err != nil {
			t.Fatal(err)
		}
		enc := json.NewEncoder(f)
		enc.SetEscapeHTML(false)
		for _, row := range list {
			if err := enc.Encode(row); err != nil {
				t.Fatal(err)
			}
		}
		f.Close()
	}
}

func nonNil(parts []requestitems.Part) []requestitems.Part {
	if parts == nil {
		return []requestitems.Part{}
	}
	return parts
}
