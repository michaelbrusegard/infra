package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"cliproxy-plugins/conversations"
)

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
	line := `{"source":"pi","host":"lungo","session":"s","id":"1","path":"s.jsonl","ts":"2026-11-12 10:00:00.000",` +
		`"line":"{\"type\":\"message\",\"id\":\"a\",\"message\":{\"role\":\"user\",\"content\":\"Hi\"}}"}`
	err := run(strings.NewReader(line+"\n"), dir, conversations.NewNormalizer(), &conversations.Proxied{})
	if err == nil {
		t.Fatal("the run succeeded with its rows lost")
	}
}
