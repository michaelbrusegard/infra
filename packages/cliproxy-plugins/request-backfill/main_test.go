package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"cliproxy-plugins/requestitems"
)

func TestRunWritesEachItemOnce(t *testing.T) {
	var in bytes.Buffer
	for id, body := range []string{`{"messages":["a","b"]}`, `{"messages":["a","b","c"]}`, `not json`} {
		json.NewEncoder(&in).Encode(input{RequestID: string(rune('0' + id)), RequestBody: body})
	}
	var out bytes.Buffer
	if err := run(&in, &out); err != nil {
		t.Fatal(err)
	}
	var rows, items []string
	scanner := bufio.NewScanner(bytes.NewReader(out.Bytes()))
	for scanner.Scan() {
		var row struct {
			RequestID string `json:"request_id"`
			Items     []struct{ Item string }
		}
		if err := json.Unmarshal(scanner.Bytes(), &row); err != nil {
			t.Fatal(err)
		}
		rows = append(rows, row.RequestID)
		for _, it := range row.Items {
			items = append(items, it.Item)
		}
	}
	if len(rows) != 3 {
		t.Fatalf("got rows %v", rows)
	}
	if got := strings.Join(items, " "); got != `"a" "b" "c" not json` {
		t.Fatalf("items %s", got)
	}
	if !strings.Contains(out.String(), `"body_hash":"`+requestitems.HashOf([]byte(`{"messages":["a","b","c"]}`)).String()+`"`) {
		t.Fatalf("missing body hash in %s", out.String())
	}
}
