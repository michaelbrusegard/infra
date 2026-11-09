package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

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
		total += len(r.json) + 1
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
