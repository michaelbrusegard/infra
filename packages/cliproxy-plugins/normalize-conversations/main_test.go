package main

import (
	"compress/gzip"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"cliproxy-plugins/conversations"
)

const line = `{"source":"pi","host":"lungo","session":"s","id":"1","path":"s.jsonl","ts":"2026-11-12 10:00:00.000",` +
	`"line":"{\"type\":\"message\",\"id\":\"a\",\"message\":{\"role\":\"user\",\"content\":\"Hi\"}}"}` + "\n"

func transcripts(t *testing.T, dir string) error {
	t.Helper()
	in := filepath.Join(t.TempDir(), "transcripts.jsonl")
	if err := os.WriteFile(in, []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}
	n := conversations.NewNormalizer()
	return run(dir, n, func(drain func() error) error {
		return normalizeTranscripts(in, n, &conversations.Proxied{}, drain)
	})
}

// A run whose output cannot be written fails, even when every row fits in
// the buffers and the write error only shows when they are flushed.
func TestRunFailsWhenOutputIsLost(t *testing.T) {
	if _, err := os.Stat("/dev/full"); err != nil {
		t.Skip("no /dev/full")
	}
	dir := t.TempDir()
	for _, table := range tables {
		if err := os.Symlink("/dev/full", filepath.Join(dir, table+".jsonl")); err != nil {
			t.Fatal(err)
		}
	}
	if transcripts(t, dir) == nil {
		t.Fatal("the run succeeded with its rows lost")
	}
}

// ClickHouse's HTTP interface sends the transcript lines gzip-compressed,
// and the normalizer reads them as they arrived, without a decompressed copy.
func TestTranscriptsReadGzip(t *testing.T) {
	plain := t.TempDir()
	if err := transcripts(t, plain); err != nil {
		t.Fatal(err)
	}
	in := filepath.Join(t.TempDir(), "transcripts.jsonl.gz")
	f, err := os.Create(in)
	if err != nil {
		t.Fatal(err)
	}
	z := gzip.NewWriter(f)
	z.Write([]byte(line))
	if err := z.Close(); err != nil {
		t.Fatal(err)
	}
	f.Close()
	compressed := t.TempDir()
	n := conversations.NewNormalizer()
	if err := run(compressed, n, func(drain func() error) error {
		return normalizeTranscripts(in, n, &conversations.Proxied{}, drain)
	}); err != nil {
		t.Fatal(err)
	}
	for _, table := range tables {
		a, _ := os.ReadFile(filepath.Join(plain, table+".jsonl"))
		b, _ := os.ReadFile(filepath.Join(compressed, table+".jsonl"))
		if string(a) != string(b) {
			t.Fatalf("%s differs:\n%s\n%s", table, a, b)
		}
	}
	if a, _ := os.ReadFile(filepath.Join(plain, "llm.messages.jsonl")); len(a) == 0 {
		t.Fatal("no messages")
	}
}

// The call query marks its rows with a call row, so a call is checked as a
// training example even with no context, such as a transcript call whose
// transcript records no tools, and even with no outputs.
func TestCallExportsAreCheckedWithoutContext(t *testing.T) {
	bash := `{"field":"","seq":0,"id":"1","role":"user","blocks":[{"type":"text","text":"List files."}]}` + "\n" +
		`{"field":"","seq":1,"id":"2","role":"assistant","output":true,"call_output":true,"blocks":` +
		`[{"type":"tool_call","tool_name":"Bash","tool_call_id":"t1","tool_input":"{\"command\":\"ls\"}"}]}` + "\n"
	for name, rows := range map[string]string{
		"no tools":   `{"field":"call"}` + "\n" + bash,
		"no outputs": `{"field":"call"}` + "\n" + `{"field":"","seq":0,"id":"1","role":"user","blocks":[{"type":"text","text":"Hi"}]}` + "\n",
		"no rows":    `{"field":"call"}` + "\n",
	} {
		var out strings.Builder
		if err := exportConversation(strings.NewReader(rows), &out, "openai"); err == nil {
			t.Fatalf("%s: exported %s", name, out.String())
		}
	}
	// A conversation is no call, and exports as it is.
	var out strings.Builder
	if err := exportConversation(strings.NewReader(bash), &out, "openai"); err != nil {
		t.Fatal(err)
	}
}
