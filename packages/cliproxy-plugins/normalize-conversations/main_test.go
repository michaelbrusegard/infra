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
	n := conversations.NewNormalizer()
	err := run(dir, n, func(drain func() error) error {
		n.Calls = append(n.Calls, conversations.Call{CallID: "c", OutputIDs: []conversations.Hash{}})
		return drain()
	})
	if err == nil {
		t.Fatal("the run succeeded with its rows lost")
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
