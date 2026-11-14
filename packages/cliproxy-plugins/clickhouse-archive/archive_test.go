package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"cliproxy-plugins/requestitems"
)

// gitops/espresso/tests/ai-usage.py inserts these rows into the real
// ClickHouse schema as the cliproxy user.
var dump = flag.String("dump", "", "write the rows inserted for the body fixtures to this directory")

func TestQueueByteBudgetIncludesRowsWaitingForFlush(t *testing.T) {
	a := newArchive()
	// A slow ClickHouse insert leaves the consumer busy while completed
	// requests accumulate in the channel, before reaching the batch buffer.
	body := strings.Repeat("x", 1<<20)
	for i := 0; i < maxQueueBytes/len(body)+1; i++ {
		a.enqueue("llm.requests", body)
	}
	var total int
	for len(a.rows) > 0 {
		r := <-a.rows
		total += int(r.size)
	}
	if total > maxQueueBytes {
		t.Fatalf("waiting archive rows use %d bytes, exceeding budget %d", total, maxQueueBytes)
	}
}

func TestFlushRetainsByteBudgetUntilInsertSucceeds(t *testing.T) {
	var attempts atomic.Int32
	failed := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.Copy(io.Discard, r.Body)
		if attempts.Add(1) == 1 {
			w.WriteHeader(http.StatusServiceUnavailable)
			close(failed)
		}
	}))
	defer server.Close()
	a := newArchive()
	a.endpoint = server.URL
	a.rows = make(chan row, 1)
	a.enqueue("llm.requests", "first")
	reserved := a.queuedBytes.Load()
	// A full channel must return the second row's reservation.
	a.enqueue("llm.requests", "second")
	if got := a.queuedBytes.Load(); got != reserved {
		t.Fatalf("full channel changed reserved bytes: got %d, want %d", got, reserved)
	}
	a.started.Store(true)
	go a.flushLoop()
	t.Cleanup(a.Shutdown)
	select {
	case <-failed:
	case <-time.After(5 * time.Second):
		t.Fatal("insert was not attempted")
	}
	if got := a.queuedBytes.Load(); got != reserved {
		t.Fatalf("failed insert lost reserved bytes: got %d, want %d", got, reserved)
	}
	// Shutdown retries the failed batch and waits for its successful insert.
	a.Shutdown()
	if got := a.queuedBytes.Load(); got != 0 {
		t.Fatalf("successful insert retained %d reserved bytes", got)
	}
	if got := attempts.Load(); got != 2 {
		t.Fatalf("got %d inserts, want the failure and one successful retry", got)
	}
}

type insert struct {
	table string
	body  string
}

// recorder is a fake ClickHouse that fails the first failures inserts into
// failTable.
type recorder struct {
	mu        sync.Mutex
	inserts   []insert
	failTable string
	failures  int
}

func (rec *recorder) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	table := strings.Fields(r.URL.Query().Get("query"))[2]
	rec.mu.Lock()
	defer rec.mu.Unlock()
	if table == rec.failTable && rec.failures > 0 {
		rec.failures--
		w.WriteHeader(http.StatusServiceUnavailable)
		return
	}
	rec.inserts = append(rec.inserts, insert{table, string(body)})
}

func (rec *recorder) rows(t *testing.T, table string) []map[string]json.RawMessage {
	t.Helper()
	rec.mu.Lock()
	defer rec.mu.Unlock()
	var out []map[string]json.RawMessage
	for _, in := range rec.inserts {
		if in.table != table {
			continue
		}
		scanner := bufio.NewScanner(strings.NewReader(in.body))
		scanner.Buffer(nil, 64<<20)
		for scanner.Scan() {
			var row map[string]json.RawMessage
			if err := json.Unmarshal(scanner.Bytes(), &row); err != nil {
				t.Fatal(err)
			}
			out = append(out, row)
		}
	}
	return out
}

func testArchive(t *testing.T, rec *recorder) *archive {
	t.Helper()
	server := httptest.NewServer(rec)
	t.Cleanup(server.Close)
	a := newArchive()
	a.endpoint = server.URL
	return a
}

func (a *archive) request(id, body string) {
	a.captureRequest(interceptRequest{RequestID: id, Headers: http.Header{}, Body: []byte(body)})
	a.complete(requestCompletion{RequestID: id, Outcome: "success", StatusCode: 200, StartedAt: time.Now(), CompletedAt: time.Now()})
}

// flushOnce inserts everything queued so far, without the background loop.
func (a *archive) flushOnce() {
	a.started.Store(true)
	go a.flushLoop()
	a.Shutdown()
	a.stop, a.done, a.stopOnce = make(chan struct{}), make(chan struct{}), sync.Once{}
}

func hashes(t *testing.T, rows []map[string]json.RawMessage) []string {
	t.Helper()
	var out []string
	for _, row := range rows {
		var h string
		if err := json.Unmarshal(row["hash"], &h); err != nil {
			t.Fatal(err)
		}
		out = append(out, h)
	}
	return out
}

func TestItemsAreInsertedOnceAndBeforeTheirRequests(t *testing.T) {
	rec := &recorder{}
	a := testArchive(t, rec)
	a.request("first", `{"model":"m","messages":["a","b"]}`)
	a.flushOnce()
	// The next turn resends both messages and adds one.
	a.request("second", `{"model":"m","messages":["a","b","c"]}`)
	a.flushOnce()
	var tables []string
	for _, in := range rec.inserts {
		tables = append(tables, in.table)
	}
	want := []string{"llm.request_items", "llm.requests", "llm.request_items", "llm.requests"}
	if !reflect.DeepEqual(tables, want) {
		t.Fatalf("insert order %v, want %v", tables, want)
	}
	c := requestitems.HashOf([]byte(`"c"`)).String()
	if got := hashes(t, rec.rows(t, "llm.request_items")); len(got) != 3 || got[2] != c {
		t.Fatalf("inserted items %v, want a, b, then only c", got)
	}
	rows := rec.rows(t, "llm.requests")
	if string(rows[1]["request_envelope"]) != `"{\"model\":\"m\"}"` {
		t.Fatalf("envelope %s", rows[1]["request_envelope"])
	}
	if _, ok := rows[1]["request_body"]; ok {
		t.Fatal("request row still carries the raw body")
	}
	if got := a.queuedBytes.Load(); got != 0 {
		t.Fatalf("%d bytes still reserved", got)
	}
}

func TestFailedItemsInsertHoldsBackRequests(t *testing.T) {
	rec := &recorder{failTable: "llm.request_items", failures: 1}
	a := testArchive(t, rec)
	a.request("first", `{"messages":["a"]}`)
	a.enqueue("llm.usage", map[string]string{"request_id": "first"})
	a.started.Store(true)
	go a.flushLoop()
	t.Cleanup(a.Shutdown)
	deadline := time.Now().Add(5 * time.Second)
	for len(rec.rows(t, "llm.usage")) == 0 {
		if time.Now().After(deadline) {
			t.Fatal("usage row was not inserted")
		}
		time.Sleep(10 * time.Millisecond)
	}
	// Unrelated tables still flush, but the request waits for its items.
	if rows := rec.rows(t, "llm.requests"); len(rows) != 0 {
		t.Fatalf("request row inserted before its items: %v", rows)
	}
	if a.queuedBytes.Load() == 0 {
		t.Fatal("held-back rows lost their reservation")
	}
	// Shutdown retries both, items first.
	a.Shutdown()
	if len(rec.inserts) != 3 || rec.inserts[1].table != "llm.request_items" || rec.inserts[2].table != "llm.requests" {
		t.Fatalf("inserts %v", rec.inserts)
	}
	if got := a.queuedBytes.Load(); got != 0 {
		t.Fatalf("%d bytes still reserved", got)
	}
}

func TestFailedItemsAreNotMarkedSent(t *testing.T) {
	// A hash may only be skipped once its item is stored.
	rec := &recorder{failTable: "llm.request_items", failures: 1}
	a := testArchive(t, rec)
	a.request("first", `{"messages":["a"]}`)
	a.started.Store(true)
	go a.flushLoop()
	a.Shutdown()
	if len(rec.inserts) != 0 || a.sent.has(requestitems.HashOf([]byte(`"a"`))) {
		t.Fatalf("failed item marked as sent; inserts %v", rec.inserts)
	}
}

func TestSentItemsKeepReusedHashes(t *testing.T) {
	var s sentItems
	hash := func(i int) requestitems.Hash {
		return requestitems.HashOf([]byte{byte(i), byte(i >> 8), byte(i >> 16)})
	}
	s.add(hash(-1))
	for i := 0; i < 2*sentItemsPerGeneration; i++ {
		s.add(hash(i))
		// A hash in use moves forward with each generation.
		if !s.has(hash(-1)) {
			t.Fatalf("reused hash forgotten after %d others", i)
		}
	}
	if s.has(hash(0)) {
		t.Fatal("set is unbounded")
	}
	if len(s.current)+len(s.previous) > 2*sentItemsPerGeneration {
		t.Fatalf("holding %d hashes", len(s.current)+len(s.previous))
	}
}

func TestRequestRowsMatchTheBackfill(t *testing.T) {
	data, err := os.ReadFile("../requestitems/testdata/bodies.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct{ Name, Body string }
	if err := json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	rec := &recorder{}
	a := testArchive(t, rec)
	for _, f := range fixtures {
		a.request(f.Name, f.Body)
	}
	a.flushOnce()
	items := map[string]bool{}
	for _, h := range hashes(t, rec.rows(t, "llm.request_items")) {
		if items[h] {
			t.Fatalf("item %s inserted twice", h)
		}
		items[h] = true
	}
	rows := rec.rows(t, "llm.requests")
	if len(rows) != len(fixtures) {
		t.Fatalf("%d rows for %d fixtures", len(rows), len(fixtures))
	}
	for i, f := range fixtures {
		split := requestitems.Split([]byte(f.Body))
		envelope, _ := json.Marshal(split.Envelope)
		parts, _ := json.Marshal(split.Parts)
		if !bytes.Equal(rows[i]["request_envelope"], envelope) || !bytes.Equal(rows[i]["request_parts"], parts) {
			t.Fatalf("%s: row differs from the backfill's split", f.Name)
		}
		for _, p := range split.Parts {
			if !items[p.Hash.String()] {
				t.Fatalf("%s: item %s never inserted", f.Name, p.Hash)
			}
		}
	}
	if *dump != "" {
		for _, table := range []string{"llm.request_items", "llm.requests"} {
			var out bytes.Buffer
			for _, in := range rec.inserts {
				if in.table == table {
					out.WriteString(in.body)
				}
			}
			if err := os.WriteFile(filepath.Join(*dump, table+".jsonl"), out.Bytes(), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
}
