package conversations

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"cliproxy-plugins/requestitems"
)

// Request is a row of llm.requests with the items its parts reference, in
// part order, and the session CLIProxy recorded in llm.usage for it, from
// as many upstream attempts as UsageAttempts. requests.sql sends an item
// only with the first request of a run that uses it, and only items the
// normalizer reads; the others are empty.
type Request struct {
	RequestID            string              `json:"request_id"`
	TraceID              string              `json:"trace_id"`
	SessionID            string              `json:"session_id"`
	StartedAt            string              `json:"started_at"`
	CompletedAt          string              `json:"completed_at"`
	SourceFormat         string              `json:"source_format"`
	Model                string              `json:"model"`
	RequestedModel       string              `json:"requested_model"`
	Stream               bool                `json:"stream"`
	Outcome              string              `json:"outcome"`
	StatusCode           int                 `json:"status_code"`
	Error                string              `json:"error"`
	UserAgent            string              `json:"user_agent"`
	Truncated            bool                `json:"truncated"`
	RequestEnvelope      string              `json:"request_envelope"`
	RequestParts         []requestitems.Part `json:"request_parts"`
	Items                []string            `json:"items"`
	ResponseBody         string              `json:"response_body"`
	UsageSessionID       string              `json:"usage_session_id"`
	UsageParentSessionID string              `json:"usage_parent_session_id"`
	UsageAttempts        Uint64              `json:"usage_attempts"`
}

// Normalizer turns sources into canonical rows. Requests must arrive in
// start order: a Codex request that continues a previous response needs
// that response's messages first. Restore loads what earlier runs left.
type Normalizer struct {
	Batch
	// Requests that continue a response nobody has seen are held back when
	// they started at or after this time, and requests whose usage has not
	// arrived when they completed at or after it, as "2006-01-02
	// 15:04:05.000" in UTC, so a later run can place them once it arrives.
	// Empty holds nothing.
	HoldAfter string
	// Set when a request needed an item that was not sent; see received.
	Err      error
	nodes    map[Hash]node
	after    map[string]Hash
	sessions map[string]struct{}
	// The items read this run, by hash.
	read map[Hash]string
}

// node is what the normalizer knows of a written message.
type node struct {
	seq     uint32
	version uint64
}

func NewNormalizer() *Normalizer {
	return &Normalizer{nodes: map[Hash]node{}, after: map[string]Hash{}, sessions: map[string]struct{}{},
		read: map[Hash]string{}}
}

// State is a row of state.sql, which earlier runs left: a node of a
// session, or with ResponseID set, the leaf a response ended at.
type State struct {
	SessionID  string `json:"session_id"`
	ID         Hash   `json:"id"`
	Seq        uint32 `json:"seq"`
	Version    Uint64 `json:"version"`
	ResponseID string `json:"response_id"`
}

// Restore loads state from earlier runs, so this run extends their trees:
// existing nodes are not written again, and delta requests find the
// response they continue.
func (n *Normalizer) Restore(s State) {
	if s.ResponseID != "" {
		n.after[s.SessionID+"\x00"+s.ResponseID] = s.ID
		return
	}
	if known, ok := n.nodes[s.ID]; !ok || uint64(s.Version) > known.version {
		n.nodes[s.ID] = node{s.Seq, uint64(s.Version)}
	}
}

// The fields holding the conversation; the others, such as system prompts
// and tools, are per-call context that stays in the request.
var conversationFields = map[string]bool{"messages": true, "input": true}

// received returns the bytes of a part that the normalizer reads, which
// requests.sql sends only with the first request of a run to use them.
func (n *Normalizer) received(p requestitems.Part, sent string) []byte {
	if sent != "" {
		n.read[p.Hash] = sent
		return []byte(sent)
	}
	item, ok := n.read[p.Hash]
	if !ok && n.Err == nil {
		n.Err = fmt.Errorf("item %s of field %s was not sent", p.Hash, p.Field)
	}
	return []byte(item)
}

var formats = map[string]string{"claude": "anthropic", "openai-response": "openai-responses", "openai": "openai-chat"}

// part is a conversation message of a request, and the hash of the
// request item it was read from, zero when the envelope held it.
type part struct {
	raw  []byte
	item Hash
}

// split reads a request's conversation messages and client metadata.
func (n *Normalizer) split(r Request, env obj) (conversation []part, metadata obj) {
	for i, p := range r.RequestParts {
		sent := ""
		if i < len(r.Items) {
			sent = r.Items[i]
		}
		switch {
		case conversationFields[p.Field] && p.Position >= 0:
			conversation = append(conversation, part{n.received(p, sent), p.Hash})
		case p.Field == "input":
			// A whole input string is one user message.
			conversation = append(conversation, part{[]byte(fmt.Sprintf(`{"role":"user","content":%s}`, n.received(p, sent))), p.Hash})
		case p.Field == "client_metadata":
			metadata = parse(n.received(p, sent))
		}
	}
	if input := env["input"]; isString(input) {
		conversation = append(conversation, part{raw: []byte(fmt.Sprintf(`{"role":"user","content":%s}`, input))})
	}
	if metadata == nil {
		metadata = env.obj("client_metadata")
	}
	return conversation, metadata
}

// SessionOf names the session a request belongs to, so a run can restore
// the state of the sessions it touches before normalizing. Like Request, it
// reads the requests of a run in order.
func (n *Normalizer) SessionOf(r Request) string {
	env := parse([]byte(r.RequestEnvelope))
	conversation, metadata := n.split(r, env)
	session, _ := proxySession(r, env, metadata, conversation)
	return session
}

// Request normalizes one request. It reports false, and writes nothing,
// when the request is held back; see HoldAfter.
func (n *Normalizer) Request(r Request) bool {
	env := parse([]byte(r.RequestEnvelope))
	conversation, metadata := n.split(r, env)
	if n.HoldAfter != "" && r.CompletedAt >= n.HoldAfter && r.UsageAttempts == 0 {
		// The plugin writes a request when it completes, before CLIProxy
		// writes its usage, whose session tells sub-agents apart. Placed now,
		// the request would stay in the header's session for good. The hold
		// runs from completion, since a call can run longer than the hold.
		return false
	}
	recent := n.HoldAfter != "" && r.StartedAt >= n.HoldAfter
	session, parentSession := proxySession(r, env, metadata, conversation)
	var parent Hash
	prev := env.str("previous_response_id")
	known := true
	if prev != "" {
		parent, known = n.after[session+"\x00"+prev]
		if !known && recent {
			return false
		}
	}
	client := clientOf(r.UserAgent)
	n.session(Session{SessionID: session, ParentSessionID: parentSession, Client: client, Origin: "proxy"})
	format := formats[r.SourceFormat]
	if !known {
		// The response this continues was never archived. Its context is
		// unknown, so the chain starts at a marker instead of merging into
		// an unrelated conversation.
		marker := encode(map[string]string{"type": "missing_context", "previous_response_id": prev})
		parent = n.message(session, Hash{}, marker, r.StartedAt, Message{
			Role: "system", CallID: r.RequestID, Format: "proxy",
			Blocks: []Block{{Type: "other", SourceType: "missing_context", Text: prev}},
		})
	}
	var tools []json.RawMessage
	for _, p := range conversation {
		if t, ok := additionalTools(p.raw); ok && format == "openai-responses" {
			// Codex's tool definitions, per-call context rather than a
			// message.
			tools = append(tools, t...)
			continue
		}
		role, blocks := dialectMessage(format, p.raw)
		parent = n.message(session, parent, p.raw, r.StartedAt, Message{
			Role: roleOf(role, blocks), CallID: r.RequestID, Format: format, Blocks: blocks, Item: p.item,
		})
	}
	call := Call{
		CallID: r.RequestID, SessionID: session, StartedAt: r.StartedAt, CompletedAt: r.CompletedAt,
		Origin: "proxy", Client: client, RequestID: r.RequestID, SourceFormat: r.SourceFormat,
		InputID: parent, OutputIDs: []Hash{},
	}
	if len(tools) > 0 {
		// After the request's own tools, which the export reads beside these.
		next := int32(0)
		for _, p := range r.RequestParts {
			if p.Field == "tools" {
				next = max(next, p.Position+1)
			}
		}
		for i, tool := range tools {
			call.Context = append(call.Context, requestitems.Part{Field: "tools", Position: next + int32(i), Hash: n.item(tool)})
		}
	}
	resp := parseResponse(r.SourceFormat, r.ResponseBody)
	call.ResponseID = resp.id
	call.Model = firstNonEmpty(resp.model, r.Model)
	resp.usage.apply(&call)
	for _, raw := range resp.outputs {
		role, blocks := dialectMessage(format, raw)
		parent = n.message(session, parent, raw, r.CompletedAt, Message{
			Role: roleOf(role, blocks), Output: true, Model: call.Model, CallID: r.RequestID,
			Format: format, Blocks: blocks,
		})
		call.OutputIDs = append(call.OutputIDs, parent)
	}
	if resp.id != "" {
		n.after[session+"\x00"+resp.id] = parent
	}
	n.Calls = append(n.Calls, call)
	return true
}

// message adds a node under parent unless one with the same content
// exists, and returns its ID. The node keeps the row with the highest
// version; every call's own bytes stay in its llm.requests row.
func (n *Normalizer) message(session string, parent Hash, raw []byte, ts string, m Message) Hash {
	id, _ := n.node(session, parent, contentKey(m.Format, raw), ts, m, true)
	return id
}

// contentKey identifies a message by what it says, ignoring what changes
// between sends of the same message: Claude Code moves cache_control
// markers every turn, content may be a string or one text block, and a
// response carries metadata such as its ID, usage, and stop reason that the
// client drops when it sends the message back. A model's output and its
// resent copy are then one node.
func contentKey(format string, raw []byte) string {
	m, ok := value(raw).(map[string]any)
	if !ok {
		return requestitems.HashOf(raw).String()
	}
	key := map[string]any{}
	switch format {
	case "anthropic":
		key["role"], key["content"] = m["role"], m["content"]
	case "openai-chat":
		// Clients often drop reasoning when sending a reply back.
		for _, k := range []string{"role", "content", "tool_calls", "tool_call_id", "name"} {
			if v, ok := m[k]; ok && v != nil && v != "" {
				key[k] = v
			}
		}
	default:
		for k, v := range m {
			if k != "id" && k != "status" {
				key[k] = v
			}
		}
	}
	if s, ok := key["content"].(string); ok {
		key["content"] = []any{map[string]any{"type": "text", "text": s}}
	}
	if c, ok := key["content"]; ok {
		key["content"] = stripTransport(c)
	}
	return string(encode(key))
}

// stripTransport removes the fields that only steer caching or decoding
// from content blocks, and from the blocks a tool result nests, which is
// where the dialects put them. Anywhere else, such as in a tool's input,
// the same names are content.
func stripTransport(content any) any {
	blocks, ok := content.([]any)
	if !ok {
		return content
	}
	out := make([]any, len(blocks))
	for i, b := range blocks {
		block, ok := b.(map[string]any)
		if !ok {
			out[i] = b
			continue
		}
		clean := make(map[string]any, len(block))
		for k, v := range block {
			switch k {
			case "cache_control", "logprobs":
			case "content":
				clean[k] = stripTransport(v)
			default:
				clean[k] = v
			}
		}
		out[i] = clean
	}
	return out
}

// node writes a message under parent, keyed by key, and reports whether it
// wrote a row. An existing node gets another row only when replace is set
// and the new row outranks the written one.
func (n *Normalizer) node(session string, parent Hash, key string, ts string, m Message, replace bool) (Hash, bool) {
	id := nodeID(session, parent, key)
	v := version(m.Output, ts)
	known, ok := n.nodes[id]
	if ok && (!replace || v <= known.version) {
		return id, false
	}
	seq := known.seq
	if !ok && parent != (Hash{}) {
		seq = n.nodes[parent].seq + 1
	}
	n.nodes[id] = node{seq, v}
	m.SessionID, m.ID, m.ParentID, m.Seq, m.TS, m.Version = session, id, parent, seq, ts, v
	if m.Blocks == nil {
		m.Blocks = []Block{}
	}
	n.Messages = append(n.Messages, m)
	return id, true
}

// session adds a session's row once, keyed as llm.sessions orders it, which
// also holds a row per transcript file of a session, by its host and path.
func (n *Normalizer) session(s Session) {
	key := strings.Join([]string{s.SessionID, s.Origin, s.Host, s.Path}, "\x00")
	if _, ok := n.sessions[key]; !ok {
		n.sessions[key] = struct{}{}
		n.Sessions = append(n.Sessions, s)
	}
}

func dialectMessage(format string, raw []byte) (string, []Block) {
	switch format {
	case "anthropic":
		m := parse(raw)
		return m.str("role"), anthropicContent(m["content"])
	case "openai-responses":
		return responsesItem(raw)
	default:
		return chatMessage(raw)
	}
}

// proxySession prefers the session CLIProxy derived for llm.usage, which
// tells sub-agents apart, and otherwise derives one in the same scheme.
// Requests with no session at all group by their first message, so calls
// that extend one conversation still land together.
func proxySession(r Request, env, metadata obj, conversation []part) (string, string) {
	client := clientOf(r.UserAgent)
	if s := r.UsageSessionID; s != "" {
		parent := r.UsageParentSessionID
		if client == "opencode" {
			s, parent = strings.Replace(s, "header:", "opencode:", 1), strings.Replace(parent, "header:", "opencode:", 1)
		}
		return s, parent
	}
	if root := metadata.str("session_id"); root != "" {
		agent := parse([]byte(metadata.str("x-codex-turn-metadata"))).str("agent_name")
		if agent != "" && agent != "/root" {
			return "codex:" + root + ":agent:" + strings.TrimPrefix(agent, "/root/"), "codex:" + root
		}
		return "codex:" + firstNonEmpty(metadata.str("thread_id"), root), ""
	}
	if key := env.str("prompt_cache_key"); key != "" && r.SourceFormat == "openai-response" {
		return "codex:" + key, ""
	}
	if r.SessionID != "" {
		prefix := map[string]string{"claude-code": "claude", "opencode": "opencode"}[client]
		return firstNonEmpty(prefix, "header") + ":" + r.SessionID, ""
	}
	if len(conversation) > 0 {
		h := requestitems.HashOf(conversation[0].raw)
		return fmt.Sprintf("proxy:%x", h[:8]), ""
	}
	return "proxy:" + r.RequestID, ""
}

// clientOf names the agent harness from its user agent.
func clientOf(userAgent string) string {
	ua := strings.ToLower(userAgent)
	switch {
	case strings.HasPrefix(ua, "claude-cli/"):
		return "claude-code"
	case strings.Contains(ua, "codex") || strings.HasPrefix(ua, "t3 code/"):
		return "codex"
	case strings.HasPrefix(ua, "pi/"):
		return "pi"
	case strings.HasPrefix(ua, "opencode/"):
		return "opencode"
	case strings.HasPrefix(ua, "hindsight/"):
		return "hindsight"
	}
	return "other"
}

type usage struct {
	uncached, read, write, write5m, write1h, output, reasoning uint64
}

func (u usage) apply(c *Call) {
	c.UncachedInputTokens, c.CacheReadTokens, c.CacheWriteTokens = u.uncached, u.read, u.write
	c.CacheWrite5mTokens, c.CacheWrite1hTokens = u.write5m, u.write1h
	c.OutputTokens, c.ReasoningTokens = u.output, u.reasoning
}

// openaiUsage reads Responses and Chat Completions usage, whose input
// includes cached tokens.
func openaiUsage(u obj) usage {
	input := u.num("input_tokens") + u.num("prompt_tokens")
	details := firstObj(u.obj("input_tokens_details"), u.obj("prompt_tokens_details"))
	out := firstObj(u.obj("output_tokens_details"), u.obj("completion_tokens_details"))
	read := details.num("cached_tokens")
	return usage{uncached: input - min(read, input), read: read,
		output: u.num("output_tokens") + u.num("completion_tokens"), reasoning: out.num("reasoning_tokens")}
}

// anthropicUsage reads Anthropic usage, whose cache writes split by
// lifetime, and the thinking tokens Claude Code's providers report.
func anthropicUsage(u obj) usage {
	cache := u.obj("cache_creation")
	return usage{uncached: u.num("input_tokens"), read: u.num("cache_read_input_tokens"),
		write: u.num("cache_creation_input_tokens"), write5m: cache.num("ephemeral_5m_input_tokens"),
		write1h: cache.num("ephemeral_1h_input_tokens"), output: u.num("output_tokens"),
		reasoning: u.obj("output_tokens_details").num("thinking_tokens")}
}

func firstObj(objs ...obj) obj {
	for _, o := range objs {
		if o != nil {
			return o
		}
	}
	return obj{}
}

type response struct {
	id, model string
	outputs   [][]byte
	usage     usage
}

// events reads a response body: a JSON object, server-sent events, or the
// JSON lines the archive writes for websocket responses. Each event keeps
// its compacted bytes.
func events(body string) []json.RawMessage {
	var out []json.RawMessage
	add := func(raw []byte) bool {
		var b bytes.Buffer
		if json.Compact(&b, raw) != nil || b.Len() == 0 || b.Bytes()[0] != '{' {
			return false
		}
		out = append(out, b.Bytes())
		return true
	}
	if add([]byte(body)) {
		return out
	}
	scanner := bufio.NewScanner(strings.NewReader(body))
	scanner.Buffer(nil, 64<<20)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		add([]byte(strings.TrimSpace(strings.TrimPrefix(line, "data:"))))
	}
	return out
}

// parseResponse assembles the messages a response produced. The response
// body itself stays in llm.requests, so this only has to be faithful, not
// complete: stream framing, rate limits, and timing remain there. The
// assembled messages are not stored: their blocks are the extracted view,
// and a rebuild assembles them again.
func parseResponse(format, body string) response {
	evs := events(body)
	switch format {
	case "claude":
		return anthropicResponse(evs)
	case "openai-response":
		return responsesResponse(evs)
	case "openai":
		return chatResponse(evs)
	}
	return response{}
}

// value decodes JSON keeping numerals as written, for messages rebuilt from
// stream deltas.
func value(raw json.RawMessage) any {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v any
	dec.Decode(&v)
	return v
}

func encode(v any) []byte {
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	enc.Encode(v)
	return bytes.TrimSuffix(b.Bytes(), []byte("\n"))
}

func anthropicResponse(evs []json.RawMessage) response {
	var r response
	var msg map[string]any
	blocks := map[int]map[string]any{}
	partial := map[int]*strings.Builder{}
	// finish sets a tool block's input from its argument deltas.
	finish := func(i int) {
		p := partial[i]
		if p == nil || blocks[i] == nil {
			return
		}
		if v := value(json.RawMessage(p.String())); v != nil {
			blocks[i]["input"] = v
		} else {
			// An interrupted stream can end inside the arguments.
			blocks[i]["input"] = p.String()
		}
		delete(partial, i)
	}
	var u obj
	for _, raw := range evs {
		e := parse(raw)
		switch e.str("type") {
		case "message":
			// Not streamed: the body is the message.
			r.id, r.model = e.str("id"), e.str("model")
			r.usage = anthropicUsage(e.obj("usage"))
			r.outputs = append(r.outputs, raw)
			return r
		case "message_start":
			m := e.obj("message")
			msg, _ = value(e["message"]).(map[string]any)
			r.id, r.model, u = m.str("id"), m.str("model"), m.obj("usage")
		case "content_block_start":
			i := int(e.num("index"))
			blocks[i], _ = value(e["content_block"]).(map[string]any)
		case "content_block_delta":
			i := int(e.num("index"))
			b := blocks[i]
			if b == nil {
				continue
			}
			d := e.obj("delta")
			switch d.str("type") {
			case "text_delta":
				b["text"] = text(b["text"]) + d.str("text")
			case "thinking_delta":
				b["thinking"] = text(b["thinking"]) + d.str("thinking")
			case "signature_delta":
				b["signature"] = d.str("signature")
			case "input_json_delta":
				if partial[i] == nil {
					partial[i] = &strings.Builder{}
				}
				partial[i].WriteString(d.str("partial_json"))
			case "citations_delta":
				citations, _ := b["citations"].([]any)
				b["citations"] = append(citations, value(d["citation"]))
			}
		case "content_block_stop":
			finish(int(e.num("index")))
		case "message_delta":
			if msg != nil {
				if d, ok := value(e["delta"]).(map[string]any); ok {
					for k, v := range d {
						msg[k] = v
					}
				}
				if du, ok := value(e["usage"]).(map[string]any); ok {
					mu, _ := msg["usage"].(map[string]any)
					if mu == nil {
						mu = map[string]any{}
					}
					for k, v := range du {
						mu[k] = v
					}
					msg["usage"] = mu
					u = parse(encode(mu))
				}
			}
		}
	}
	if msg == nil {
		return r
	}
	// A stream cut off before a block's stop event still streamed its
	// arguments.
	for i := range partial {
		finish(i)
	}
	indexes := make([]int, 0, len(blocks))
	for i := range blocks {
		indexes = append(indexes, i)
	}
	sort.Ints(indexes)
	content := []any{}
	for _, i := range indexes {
		if blocks[i] != nil {
			content = append(content, blocks[i])
		}
	}
	msg["content"] = content
	r.usage = anthropicUsage(u)
	r.outputs = append(r.outputs, encode(msg))
	return r
}

func responsesResponse(evs []json.RawMessage) response {
	var r response
	done := map[int][]byte{}
	added := map[int]map[string]any{}
	var final []json.RawMessage
	for _, raw := range evs {
		e := parse(raw)
		t := e.str("type")
		if resp := e.obj("response"); resp != nil {
			r.id = firstNonEmpty(resp.str("id"), r.id)
			r.model = firstNonEmpty(resp.str("model"), r.model)
			if u := resp.obj("usage"); u != nil {
				r.usage = openaiUsage(u)
			}
			if out := resp.arr("output"); len(out) > 0 {
				final = out
			}
		}
		i := int(e.num("output_index"))
		switch t {
		case "":
			// Not streamed: the body is the response.
			if e.str("object") == "response" {
				r.id, r.model = e.str("id"), e.str("model")
				r.usage = openaiUsage(e.obj("usage"))
				final = e.arr("output")
			}
		case "response.output_item.added":
			added[i], _ = value(e["item"]).(map[string]any)
		case "response.output_item.done":
			done[i] = []byte(e["item"])
		case "response.output_text.delta", "response.function_call_arguments.delta",
			"response.custom_tool_call_input.delta", "response.reasoning_summary_text.delta":
			appendDelta(added[i], t, e)
		}
	}
	if len(done) == 0 && len(added) == 0 {
		for _, raw := range final {
			r.outputs = append(r.outputs, []byte(raw))
		}
		return r
	}
	// Items without a done event were interrupted; keep what streamed.
	for i := range added {
		if _, ok := done[i]; !ok && added[i] != nil {
			done[i] = encode(added[i])
		}
	}
	indexes := make([]int, 0, len(done))
	for i := range done {
		indexes = append(indexes, i)
	}
	sort.Ints(indexes)
	for _, i := range indexes {
		r.outputs = append(r.outputs, done[i])
	}
	return r
}

// appendDelta applies a streamed delta to an item that never completed.
func appendDelta(item map[string]any, t string, e obj) {
	if item == nil {
		return
	}
	delta := e.str("delta")
	switch t {
	case "response.function_call_arguments.delta":
		item["arguments"] = text(item["arguments"]) + delta
	case "response.custom_tool_call_input.delta":
		item["input"] = text(item["input"]) + delta
	default:
		key, index := "content", int(e.num("content_index"))
		if t == "response.reasoning_summary_text.delta" {
			key, index = "summary", int(e.num("summary_index"))
		}
		parts, _ := item[key].([]any)
		for len(parts) <= index {
			kind := "output_text"
			if key == "summary" {
				kind = "summary_text"
			}
			parts = append(parts, map[string]any{"type": kind, "text": ""})
		}
		if part, ok := parts[index].(map[string]any); ok {
			part["text"] = text(part["text"]) + delta
		}
		item[key] = parts
	}
}

func chatResponse(evs []json.RawMessage) response {
	var r response
	msg := map[string]any{}
	var calls []map[string]any
	streamed := false
	for _, raw := range evs {
		e := parse(raw)
		r.id = firstNonEmpty(e.str("id"), r.id)
		r.model = firstNonEmpty(e.str("model"), r.model)
		if u := e.obj("usage"); u != nil {
			r.usage = openaiUsage(u)
		}
		choices := e.arr("choices")
		if len(choices) == 0 {
			continue
		}
		c := parse(choices[0])
		if m := c["message"]; m != nil {
			// Not streamed.
			r.outputs = append(r.outputs, []byte(m))
			continue
		}
		d := c.obj("delta")
		if d == nil {
			continue
		}
		streamed = true
		for k, raw := range d {
			switch k {
			case "content", "reasoning_content", "reasoning":
				if s := str(raw); s != "" {
					msg[k] = text(msg[k]) + s
				}
			case "tool_calls":
				for _, tc := range array(raw) {
					t := parse(tc)
					i := int(t.num("index"))
					for len(calls) <= i {
						calls = append(calls, map[string]any{"function": map[string]any{"name": "", "arguments": ""}})
					}
					call := calls[i]
					for _, key := range []string{"id", "type"} {
						if v := t.str(key); v != "" {
							call[key] = v
						}
					}
					fn := call["function"].(map[string]any)
					f := t.obj("function")
					if name := f.str("name"); name != "" {
						fn["name"] = name
					}
					fn["arguments"] = text(fn["arguments"]) + f.str("arguments")
				}
			case "role":
				msg["role"] = str(raw)
			}
		}
	}
	if streamed {
		if msg["role"] == nil {
			msg["role"] = "assistant"
		}
		if len(calls) > 0 {
			msg["tool_calls"] = calls
		}
		r.outputs = append(r.outputs, encode(msg))
	}
	return r
}

// text reads a string being assembled from deltas, empty before the first.
func text(v any) string {
	s, _ := v.(string)
	return s
}

// additionalTools reads the tool definitions of a Codex additional_tools
// item, which may hold namespaces of tools.
func additionalTools(raw json.RawMessage) ([]json.RawMessage, bool) {
	it := parse(raw)
	if it.str("type") != "additional_tools" {
		return nil, false
	}
	return it.arr("tools"), true
}
