package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"cliproxy-plugins/plugin"
	"cliproxy-plugins/requestitems"
)

const (
	// Request bodies resend the whole conversation, so they can be large.
	// Anything past this is cut off and the row is marked truncated.
	maxBodyBytes = 32 << 20
	// Rows wait here while ClickHouse is slow or down. Past these limits new
	// rows are dropped: losing archive rows is better than stalling inference.
	queueRows     = 4096
	maxBatchBytes = 16 << 20
	maxQueueBytes = 256 << 20
	flushInterval = 2 * time.Second
	// Recently inserted item hashes, so context a session resends every turn
	// is not sent again. Repeats are mostly seconds apart. A forgotten hash
	// only costs a duplicate that ReplacingMergeTree merges away.
	sentItemsPerGeneration = 1 << 15
	// request.complete is exactly-once, so this only guards against leaks if
	// the host ever skips it.
	staleAfter = time.Hour
)

// Headers clients use for a conversation ID. Rows from one session are
// stored together, so a conversation reads from one place.
var sessionHeaders = []string{"X-Claude-Code-Session-Id", "Session_id", "Conversation_id", "X-Session-Id"}

type archive struct {
	endpoint string
	user     string
	client   *http.Client

	mu      sync.Mutex
	pending map[string]*pendingRequest

	rows chan row
	// Includes rows in the channel and the batches awaiting insertion.
	queuedBytes atomic.Int64
	stop        chan struct{}
	done        chan struct{}
	started     atomic.Bool
	stopOnce    sync.Once

	// Owned by the flush goroutine.
	sent sentItems
}

type pendingRequest struct {
	record    requestRow
	body      []byte
	response  bytes.Buffer
	updatedAt time.Time
}

// A row is either encoded JSON or a request whose body is split and encoded
// in the flush goroutine, off the request path. size is its reservation in
// queuedBytes.
type row struct {
	table   string
	json    []byte
	request *requestRow
	body    []byte
	size    int64
}

// Field names match CLIProxyAPI's pluginapi structs, which it encodes
// without JSON tags.
type interceptRequest struct {
	RequestID      string
	TraceID        string
	SourceFormat   string
	Model          string
	RequestedModel string
	Stream         bool
	Headers        http.Header
	Body           []byte
	StatusCode     int
	ChunkIndex     int
}

type requestCompletion struct {
	RequestID      string
	TraceID        string
	SourceFormat   string
	Model          string
	RequestedModel string
	Stream         bool
	Outcome        string
	StatusCode     int
	Error          string
	StartedAt      time.Time
	CompletedAt    time.Time
}

type usageRecord struct {
	RequestID            string
	TraceID              string
	SessionID            string
	ParentSessionID      string
	Provider             string
	ExecutorType         string
	Model                string
	Alias                string
	ResponseModel        string
	AuthID               string
	AuthType             string
	ReasoningEffort      string
	ServiceTier          string
	EffectiveServiceTier string
	ResponseServiceTier  string
	Stream               bool
	RequestedAt          time.Time
	Latency              time.Duration
	TTFT                 time.Duration
	Failed               bool
	Failure              struct {
		StatusCode int
		Body       string
	}
	Detail struct {
		InputTokens         int64
		OutputTokens        int64
		ReasoningTokens     int64
		CachedTokens        int64
		CacheReadTokens     int64
		CacheCreationTokens int64
		TotalTokens         int64
	}
	ResponseHeaders http.Header
}

type requestRow struct {
	RequestID      string `json:"request_id"`
	TraceID        string `json:"trace_id"`
	SessionID      string `json:"session_id"`
	StartedAt      string `json:"started_at"`
	CompletedAt    string `json:"completed_at"`
	SourceFormat   string `json:"source_format"`
	Model          string `json:"model"`
	RequestedModel string `json:"requested_model"`
	Stream         bool   `json:"stream"`
	Outcome        string `json:"outcome"`
	StatusCode     int    `json:"status_code"`
	Error          string `json:"error"`
	UserAgent      string `json:"user_agent"`
	Truncated      bool   `json:"truncated"`
	// The body is stored as an envelope plus parts referencing
	// llm.request_items.
	RequestEnvelope string              `json:"request_envelope"`
	RequestParts    []requestitems.Part `json:"request_parts"`
	ResponseBody    string              `json:"response_body"`
}

type itemRow struct {
	Hash requestitems.Hash `json:"hash"`
	Item string            `json:"item"`
}

type usageRow struct {
	RequestID            string            `json:"request_id"`
	TraceID              string            `json:"trace_id"`
	SessionID            string            `json:"session_id"`
	ParentSessionID      string            `json:"parent_session_id"`
	RequestedAt          string            `json:"requested_at"`
	Provider             string            `json:"provider"`
	ExecutorType         string            `json:"executor_type"`
	Model                string            `json:"model"`
	Alias                string            `json:"alias"`
	ResponseModel        string            `json:"response_model"`
	AuthID               string            `json:"auth_id"`
	AuthType             string            `json:"auth_type"`
	ReasoningEffort      string            `json:"reasoning_effort"`
	ServiceTier          string            `json:"service_tier"`
	EffectiveServiceTier string            `json:"effective_service_tier"`
	ResponseServiceTier  string            `json:"response_service_tier"`
	Stream               bool              `json:"stream"`
	Failed               bool              `json:"failed"`
	FailureStatus        int               `json:"failure_status"`
	FailureBody          string            `json:"failure_body"`
	LatencyMS            int64             `json:"latency_ms"`
	TTFTMS               int64             `json:"ttft_ms"`
	InputTokens          int64             `json:"input_tokens"`
	OutputTokens         int64             `json:"output_tokens"`
	ReasoningTokens      int64             `json:"reasoning_tokens"`
	CachedTokens         int64             `json:"cached_tokens"`
	CacheReadTokens      int64             `json:"cache_read_tokens"`
	CacheCreationTokens  int64             `json:"cache_creation_tokens"`
	TotalTokens          int64             `json:"total_tokens"`
	ResponseHeaders      map[string]string `json:"response_headers"`
}

func newArchive() *archive {
	endpoint := os.Getenv("ARCHIVE_CLICKHOUSE_URL")
	if endpoint == "" {
		endpoint = "http://clickhouse.clickhouse.svc.cluster.local:8123"
	}
	user := os.Getenv("ARCHIVE_CLICKHOUSE_USER")
	if user == "" {
		user = "cliproxy"
	}
	return &archive{
		endpoint: strings.TrimRight(endpoint, "/"),
		user:     user,
		client:   &http.Client{Timeout: 30 * time.Second},
		pending:  map[string]*pendingRequest{},
		rows:     make(chan row, queueRows),
		stop:     make(chan struct{}),
		done:     make(chan struct{}),
	}
}

func (a *archive) Handle(method string, raw []byte) ([]byte, bool) {
	switch method {
	case "plugin.register", "plugin.reconfigure":
		if a.started.CompareAndSwap(false, true) {
			go a.flushLoop()
		}
		return plugin.Reply(plugin.Registration("clickhouse-archive", map[string]bool{
			"request_interceptor":                 true,
			"request_interceptor_omit_body_after": true,
			"request_lifecycle_plugin":            true,
			"response_interceptor":                true,
			"response_stream_interceptor":         true,
			"usage_plugin":                        true,
		}))
	case "request.intercept_before":
		var r interceptRequest
		if err := json.Unmarshal(raw, &r); err != nil {
			return plugin.Fail("invalid_request", err)
		}
		a.captureRequest(r)
	case "response.intercept_after":
		var r interceptRequest
		if err := json.Unmarshal(raw, &r); err != nil {
			return plugin.Fail("invalid_request", err)
		}
		a.captureResponse(r)
	case "response.intercept_stream_chunk":
		var r interceptRequest
		if err := json.Unmarshal(raw, &r); err != nil {
			return plugin.Fail("invalid_request", err)
		}
		a.captureChunk(r)
	case "request.complete":
		var r requestCompletion
		if err := json.Unmarshal(raw, &r); err != nil {
			return plugin.Fail("invalid_request", err)
		}
		a.complete(r)
	case "usage.handle":
		var r usageRecord
		if err := json.Unmarshal(raw, &r); err != nil {
			return plugin.Fail("invalid_request", err)
		}
		a.enqueue("llm.usage", newUsageRow(r))
	case "request.intercept_after", "plugin.quiesce", "plugin.shutdown":
	default:
		return plugin.Fail("unknown_method", fmt.Errorf("unknown method %q", method))
	}
	return plugin.Reply(map[string]any{})
}

func (a *archive) captureRequest(r interceptRequest) {
	if r.RequestID == "" {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	p := a.pendingLocked(r.RequestID)
	p.record.TraceID = r.TraceID
	p.record.SourceFormat = r.SourceFormat
	p.record.Model = r.Model
	p.record.RequestedModel = r.RequestedModel
	p.record.Stream = r.Stream
	p.record.UserAgent = r.Headers.Get("User-Agent")
	for _, h := range sessionHeaders {
		if v := r.Headers.Get(h); v != "" {
			p.record.SessionID = v
			break
		}
	}
	body := r.Body
	if len(body) > maxBodyBytes {
		body = body[:maxBodyBytes]
		p.record.Truncated = true
	}
	p.body = body
}

func (a *archive) captureResponse(r interceptRequest) {
	a.mu.Lock()
	defer a.mu.Unlock()
	p := a.pending[r.RequestID]
	if p == nil {
		return
	}
	p.response.Reset()
	a.appendResponseLocked(p, r.Body)
}

func (a *archive) captureChunk(r interceptRequest) {
	// Negative indexes are header-only initialization calls.
	if r.ChunkIndex < 0 {
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if p := a.pending[r.RequestID]; p != nil {
		a.appendResponseLocked(p, r.Body)
		if len(r.Body) > 0 && r.Body[len(r.Body)-1] != '\n' {
			a.appendResponseLocked(p, []byte{'\n'})
		}
	}
}

func (a *archive) appendResponseLocked(p *pendingRequest, body []byte) {
	p.updatedAt = time.Now()
	if room := maxBodyBytes - p.response.Len(); len(body) > room {
		body = body[:max(room, 0)]
		p.record.Truncated = true
	}
	p.response.Write(body)
}

func (a *archive) complete(r requestCompletion) {
	a.mu.Lock()
	p := a.pending[r.RequestID]
	delete(a.pending, r.RequestID)
	a.mu.Unlock()
	// Model listings and other non-model requests complete without passing
	// the request interceptor.
	if p == nil {
		return
	}
	rec := p.record
	rec.TraceID = firstNonEmpty(r.TraceID, rec.TraceID)
	rec.SourceFormat = firstNonEmpty(r.SourceFormat, rec.SourceFormat)
	rec.Model = firstNonEmpty(r.Model, rec.Model)
	rec.RequestedModel = firstNonEmpty(r.RequestedModel, rec.RequestedModel)
	rec.Stream = r.Stream || rec.Stream
	rec.Outcome = r.Outcome
	rec.StatusCode = r.StatusCode
	rec.Error = r.Error
	rec.StartedAt = clickhouseTime(r.StartedAt)
	rec.CompletedAt = clickhouseTime(r.CompletedAt)
	rec.ResponseBody = p.response.String()
	// The body is split later, so reserve its raw size plus the rest.
	size := int64(len(p.body) + len(rec.ResponseBody) + len(rec.Error) + 1024)
	if a.reserve("llm.requests", size) {
		a.send(row{table: "llm.requests", request: &rec, body: p.body, size: size})
	}
}

func (a *archive) pendingLocked(id string) *pendingRequest {
	p := a.pending[id]
	if p == nil {
		p = &pendingRequest{record: requestRow{RequestID: id}}
		a.pending[id] = p
	}
	p.updatedAt = time.Now()
	return p
}

func (a *archive) dropStale() {
	cutoff := time.Now().Add(-staleAfter)
	a.mu.Lock()
	defer a.mu.Unlock()
	for id, p := range a.pending {
		if p.updatedAt.Before(cutoff) {
			delete(a.pending, id)
			log.Printf("clickhouse-archive: dropped request %s without completion", id)
		}
	}
}

func newUsageRow(r usageRecord) usageRow {
	headers := make(map[string]string, len(r.ResponseHeaders))
	for k, v := range r.ResponseHeaders {
		headers[strings.ToLower(k)] = strings.Join(v, ", ")
	}
	return usageRow{
		RequestID:            r.RequestID,
		TraceID:              r.TraceID,
		SessionID:            r.SessionID,
		ParentSessionID:      r.ParentSessionID,
		RequestedAt:          clickhouseTime(r.RequestedAt),
		Provider:             r.Provider,
		ExecutorType:         r.ExecutorType,
		Model:                r.Model,
		Alias:                r.Alias,
		ResponseModel:        r.ResponseModel,
		AuthID:               r.AuthID,
		AuthType:             r.AuthType,
		ReasoningEffort:      r.ReasoningEffort,
		ServiceTier:          r.ServiceTier,
		EffectiveServiceTier: r.EffectiveServiceTier,
		ResponseServiceTier:  r.ResponseServiceTier,
		Stream:               r.Stream,
		Failed:               r.Failed,
		FailureStatus:        r.Failure.StatusCode,
		FailureBody:          r.Failure.Body,
		LatencyMS:            r.Latency.Milliseconds(),
		TTFTMS:               r.TTFT.Milliseconds(),
		InputTokens:          r.Detail.InputTokens,
		OutputTokens:         r.Detail.OutputTokens,
		ReasoningTokens:      r.Detail.ReasoningTokens,
		CachedTokens:         r.Detail.CachedTokens,
		CacheReadTokens:      r.Detail.CacheReadTokens,
		CacheCreationTokens:  r.Detail.CacheCreationTokens,
		TotalTokens:          r.Detail.TotalTokens,
		ResponseHeaders:      headers,
	}
}

// enqueue never blocks: hooks run on the request path.
func (a *archive) enqueue(table string, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		log.Printf("clickhouse-archive: encode %s row: %v", table, err)
		return
	}
	size := int64(len(data) + 1)
	if a.reserve(table, size) {
		a.send(row{table: table, json: data, size: size})
	}
}

func (a *archive) reserve(table string, size int64) bool {
	for {
		queued := a.queuedBytes.Load()
		if size > maxQueueBytes-queued {
			log.Printf("clickhouse-archive: backlog full, dropped %s row", table)
			return false
		}
		if a.queuedBytes.CompareAndSwap(queued, queued+size) {
			return true
		}
	}
}

func (a *archive) send(r row) {
	select {
	case a.rows <- r:
	default:
		a.queuedBytes.Add(-r.size)
		log.Printf("clickhouse-archive: queue full, dropped %s row", r.table)
	}
}

// Items go first: a request row only lands after every item it references.
var flushOrder = []string{"llm.request_items", "llm.requests", "llm.usage"}

func (a *archive) flushLoop() {
	defer close(a.done)
	ticker := time.NewTicker(flushInterval)
	defer ticker.Stop()
	batches := map[string]*bytes.Buffer{}
	// Hashes in the items batch, marked sent once it is inserted.
	unsent := map[requestitems.Hash]struct{}{}
	failing := false
	write := func(table string, data []byte) int {
		buf := batches[table]
		if buf == nil {
			buf = &bytes.Buffer{}
			batches[table] = buf
		}
		buf.Write(data)
		buf.WriteByte('\n')
		return len(data) + 1
	}
	add := func(r row) {
		if r.request == nil {
			write(r.table, r.json)
			return
		}
		items, request, ok := a.encodeRequest(r, unsent)
		size := int64(len(request) + 1)
		for _, item := range items {
			size += int64(len(item.json) + 1)
		}
		// Swap the reservation for the bytes this row really batches, and
		// drop it rather than exceed the budget when splitting grew it.
		if !ok || (size > r.size && !a.reserve("llm.requests", size-r.size)) {
			a.queuedBytes.Add(-r.size)
			return
		}
		if size < r.size {
			a.queuedBytes.Add(size - r.size)
		}
		for _, item := range items {
			unsent[item.hash] = struct{}{}
			write("llm.request_items", item.json)
		}
		write("llm.requests", request)
	}
	full := func() bool {
		for _, buf := range batches {
			if buf.Len() >= maxBatchBytes {
				return true
			}
		}
		return false
	}
	flush := func() {
		failing = false
		for _, table := range flushOrder {
			buf := batches[table]
			if buf == nil {
				continue
			}
			if table == "llm.requests" && batches["llm.request_items"] != nil {
				// Their items failed to insert; retry both together.
				continue
			}
			if err := a.insert(table, buf.Bytes()); err != nil {
				log.Printf("clickhouse-archive: insert into %s: %v", table, err)
				failing = true
				continue
			}
			a.queuedBytes.Add(-int64(buf.Len()))
			// Release the backing allocation as well as its byte budget.
			delete(batches, table)
			if table == "llm.request_items" {
				for h := range unsent {
					a.sent.add(h)
				}
				clear(unsent)
			}
		}
	}
	for {
		select {
		case r := <-a.rows:
			add(r)
			// After a failed insert, only the ticker retries.
			if !failing && full() {
				flush()
			}
		case <-ticker.C:
			flush()
			a.dropStale()
		case <-a.stop:
			for {
				select {
				case r := <-a.rows:
					add(r)
				default:
					flush()
					return
				}
			}
		}
	}
}

type encodedItem struct {
	hash requestitems.Hash
	json []byte
}

// encodeRequest splits a request body and encodes the request row together
// with any of its items not already stored or batched. Nothing is batched
// yet, so the caller can still drop the row.
func (a *archive) encodeRequest(r row, unsent map[requestitems.Hash]struct{}) ([]encodedItem, []byte, bool) {
	body := requestitems.Split(r.body)
	rec := *r.request
	rec.RequestEnvelope = body.Envelope
	rec.RequestParts = body.Parts
	data, err := json.Marshal(rec)
	if err != nil {
		log.Printf("clickhouse-archive: encode llm.requests row: %v", err)
		return nil, nil, false
	}
	var items []encodedItem
	// A body can repeat an item, such as two identical messages.
	seen := map[requestitems.Hash]struct{}{}
	for i, part := range body.Parts {
		if _, ok := seen[part.Hash]; ok {
			continue
		}
		seen[part.Hash] = struct{}{}
		if _, ok := unsent[part.Hash]; ok || a.sent.has(part.Hash) {
			continue
		}
		item, err := json.Marshal(itemRow{Hash: part.Hash, Item: string(body.Items[i])})
		if err != nil {
			log.Printf("clickhouse-archive: encode llm.request_items row: %v", err)
			return nil, nil, false
		}
		items = append(items, encodedItem{hash: part.Hash, json: item})
	}
	return items, data, true
}

// sentItems is a set with two generations: when the current one fills up,
// it replaces the previous one, so hashes still in use survive the turnover.
type sentItems struct {
	current, previous map[requestitems.Hash]struct{}
}

func (s *sentItems) has(h requestitems.Hash) bool {
	if _, ok := s.current[h]; ok {
		return true
	}
	if _, ok := s.previous[h]; ok {
		s.add(h)
		return true
	}
	return false
}

func (s *sentItems) add(h requestitems.Hash) {
	if s.current == nil || len(s.current) >= sentItemsPerGeneration {
		s.previous, s.current = s.current, make(map[requestitems.Hash]struct{}, sentItemsPerGeneration)
	}
	s.current[h] = struct{}{}
}

func (a *archive) insert(table string, body []byte) error {
	query := url.Values{"query": {"INSERT INTO " + table + " FORMAT JSONEachRow"}}
	req, err := http.NewRequest(http.MethodPost, a.endpoint+"/?"+query.Encode(), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("X-ClickHouse-User", a.user)
	resp, err := a.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		var msg bytes.Buffer
		msg.ReadFrom(resp.Body)
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(msg.String()))
	}
	return nil
}

func (a *archive) Shutdown() {
	a.stopOnce.Do(func() { close(a.stop) })
	if !a.started.Load() {
		return
	}
	select {
	case <-a.done:
	case <-time.After(10 * time.Second):
		log.Printf("clickhouse-archive: gave up flushing on shutdown")
	}
}

func clickhouseTime(t time.Time) string {
	if t.IsZero() {
		t = time.Unix(0, 0)
	}
	return t.UTC().Format("2006-01-02 15:04:05.000")
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
