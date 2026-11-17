// Package conversations normalizes archived LLM traffic into one canonical
// form: sessions, a tree of messages, and model calls, and exports them for
// training. The tables are in gitops/espresso/apps/clickhouse/configmap.yaml.
//
// The proxy's raw capture is kept for good, and canonical rows reference it
// rather than copy it: a proxy call names its llm.requests row, and a proxy
// message the llm.request_items hash it was read from. The canonical tables
// also hold the rows of a one-off import of agent transcripts, which hold
// their own content; the types describe their columns too.
package conversations

import (
	"bytes"
	"encoding/json"
	"strconv"
	"strings"
	"time"

	"cliproxy-plugins/requestitems"
)

type Hash = requestitems.Hash

// Block is one piece of message content in a dialect-neutral form. Image and
// file data, signatures, and encrypted reasoning are not extracted: a proxy
// message keeps them in its raw item, and a transcript message drops them.
type Block struct {
	// text, thinking, tool_call, tool_result, image, file, compaction,
	// fallback (a model handing the reply to another), other
	Type string `json:"type"`
	// The source dialect's type, such as tool_use, custom_tool_call, or input_image.
	SourceType string `json:"source_type"`
	Text       string `json:"text"`
	ToolName   string `json:"tool_name"`
	// The namespace a Responses API call names its tool in, if any.
	ToolNamespace string `json:"tool_namespace"`
	ToolCallID    string `json:"tool_call_id"`
	// Tool call arguments as JSON, or a custom tool's raw input.
	ToolInput string `json:"tool_input"`
	IsError   bool   `json:"is_error"`
	// Media type of an image or file.
	Media string `json:"media"`
}

// Message is a node in a session's conversation tree. A node's ID covers its
// parent's ID, so a conversation prefix resent on every turn maps to the same
// nodes, while the same content in another context is another node.
type Message struct {
	SessionID string `json:"session_id"`
	ID        Hash   `json:"id"`
	// Zero at a root: the first message, or the first after a compaction.
	ParentID Hash   `json:"parent_id"`
	Seq      uint32 `json:"seq"`
	TS       string `json:"ts"`
	// system, developer, user, assistant, or tool. Messages carrying only
	// tool results are tool messages whatever role the dialect gives them.
	Role string `json:"role"`
	// Produced by the model in CallID, rather than sent to it.
	Output bool   `json:"output"`
	Model  string `json:"model"`
	// The call that produced the message, or first sent it.
	CallID string  `json:"call_id"`
	Blocks []Block `json:"blocks"`
	// The source dialect: anthropic, openai-responses, openai-chat,
	// claude-code, codex, pi, or opencode.
	Format string `json:"format"`
	// For a proxy input, the llm.request_items hash of the request part it
	// was read from, or zero when the request's envelope held it. A proxy
	// output was assembled from its call's response body in llm.requests.
	Item Hash `json:"item"`
	// For a transcript message, the line it came from, by its file's host
	// and path and its ID in the file. Part is empty when the message is the
	// whole line, and otherwise names what inside the line it was built
	// from: the index of a Codex compaction's replacement history item, or
	// the entry a Pi compaction sends again.
	Host string `json:"host"`
	Path string `json:"path"`
	Line string `json:"line"`
	Part string `json:"part"`
	// Ranks the rows written for one node; ReplacingMergeTree keeps the
	// highest. See version.
	Version uint64 `json:"version"`
}

// Call is one model request and its response.
type Call struct {
	CallID      string `json:"call_id"`
	SessionID   string `json:"session_id"`
	ResponseID  string `json:"response_id"`
	StartedAt   string `json:"started_at"`
	CompletedAt string `json:"completed_at"`
	// proxy or transcript
	Origin string `json:"origin"`
	Client string `json:"client"`
	// Where the call comes from: its llm.requests row for the proxy, or the
	// host and path of its transcript file.
	RequestID    string `json:"request_id"`
	Host         string `json:"host"`
	Path         string `json:"path"`
	SourceFormat string `json:"source_format"`
	Model        string `json:"model"`
	// The last input message; its ancestors are the rest of the context.
	InputID   Hash   `json:"input_id"`
	OutputIDs []Hash `json:"output_ids"`
	// Token counts as the response reported them, with cached input split
	// out the way llm.usage_metrics does. Anthropic splits cache writes by
	// their lifetime, which prices them.
	UncachedInputTokens uint64 `json:"uncached_input_tokens"`
	CacheReadTokens     uint64 `json:"cache_read_tokens"`
	CacheWriteTokens    uint64 `json:"cache_write_tokens"`
	CacheWrite5mTokens  uint64 `json:"cache_write_5m_tokens"`
	CacheWrite1hTokens  uint64 `json:"cache_write_1h_tokens"`
	OutputTokens        uint64 `json:"output_tokens"`
	ReasoningTokens     uint64 `json:"reasoning_tokens"`
	// The system prompt and tools a transcript call ran with, as items in
	// llm.request_items, where its transcript recorded them. A proxy call's
	// are in its llm.requests row, apart from Codex's additional tools.
	Context []requestitems.Part `json:"context"`
}

// Session holds the attributes of a session that do not change as it grows.
// Times and models are aggregated from its messages and calls.
type Session struct {
	SessionID       string `json:"session_id"`
	ParentSessionID string `json:"parent_session_id"`
	Client          string `json:"client"`
	// proxy or transcript: the one source a session's messages come from.
	Origin string `json:"origin"`
	Host   string `json:"host"`
	Path   string `json:"path"`
	Title  string `json:"title"`
	Cwd    string `json:"cwd"`
}

// Batch collects normalized rows. Its items are only call context that the
// request did not store as items, such as Codex's additional tools; proxy
// rows otherwise reference the items the archive holds.
type Batch struct {
	Sessions []Session
	Messages []Message
	Calls    []Call
	Items    []Item
	items    map[Hash]bool
}

type Item struct {
	Hash Hash   `json:"hash"`
	Item string `json:"item"`
}

// item stores bytes as an item, once, and returns their hash. Invalid UTF-8
// is replaced first, as requestitems does, because ClickHouse would replace
// it on insert and the item would no longer match its hash.
func (b *Batch) item(raw []byte) Hash {
	raw = bytes.ToValidUTF8(raw, []byte("\uFFFD"))
	h := itemHash(raw)
	if b.items == nil {
		b.items = map[Hash]bool{}
	}
	if !b.items[h] {
		b.items[h] = true
		b.Items = append(b.Items, Item{h, string(raw)})
	}
	return h
}

// itemHash is the hash an item of these bytes has in llm.request_items.
func itemHash(raw []byte) Hash {
	return requestitems.HashOf(bytes.ToValidUTF8(raw, []byte("\uFFFD")))
}

// version ranks the rows written for one node, highest first: a model's
// output over a copy sent back as input, then the earliest sighting. The row
// ClickHouse keeps then does not depend on the order or the runs in which
// calls were normalized, so a later resend cannot replace the call, model,
// and time that produced a message.
func version(output bool, ts string) uint64 {
	var ms uint64
	if t, err := time.Parse(time.DateTime, ts); err == nil && t.UnixMilli() > 0 {
		ms = uint64(t.UnixMilli())
	}
	v := uint64(1<<63-1) - ms
	if output {
		v |= 1 << 63
	}
	return v
}

// Uint64 reads a UInt64 that ClickHouse may write quoted.
type Uint64 uint64

func (u *Uint64) UnmarshalJSON(data []byte) error {
	n, err := strconv.ParseUint(strings.Trim(string(data), `"`), 10, 64)
	*u = Uint64(n)
	return err
}

// nodeID derives a message ID from its parent and a key: the content key
// for proxy messages, which dedupes resent prefixes, or the transcript's own
// entry ID. Roots derive from the session instead.
func nodeID(session string, parent Hash, key string) Hash {
	var seed []byte
	if parent == (Hash{}) {
		seed = append([]byte("root\x00"), session...)
	} else {
		seed = append([]byte("node\x00"), parent[:]...)
	}
	return requestitems.HashOf(append(append(seed, 0), key...))
}

// obj is a JSON object whose values keep their source bytes.
type obj map[string]json.RawMessage

func parse(raw []byte) obj {
	var o obj
	if json.Unmarshal(raw, &o) != nil {
		return nil
	}
	return o
}

func (o obj) str(key string) string {
	var s string
	if json.Unmarshal(o[key], &s) != nil {
		return ""
	}
	return s
}

func (o obj) obj(key string) obj { return parse(o[key]) }

func (o obj) arr(key string) []json.RawMessage { return array(o[key]) }

func (o obj) num(key string) uint64 {
	var n float64
	if json.Unmarshal(o[key], &n) != nil || n < 0 {
		return 0
	}
	return uint64(n)
}

func (o obj) boolean(key string) bool {
	var v bool
	json.Unmarshal(o[key], &v)
	return v
}

func array(raw json.RawMessage) []json.RawMessage {
	var a []json.RawMessage
	if json.Unmarshal(raw, &a) != nil {
		return nil
	}
	return a
}

func isString(raw json.RawMessage) bool {
	raw = bytes.TrimSpace(raw)
	return len(raw) > 0 && raw[0] == '"'
}

func str(raw json.RawMessage) string {
	var s string
	json.Unmarshal(raw, &s)
	return s
}

// compactJSON returns a JSON value as compact text, or a JSON string's
// contents, for tool inputs that are either.
func compactJSON(raw json.RawMessage) string {
	if len(raw) == 0 || string(raw) == "null" {
		return ""
	}
	if isString(raw) {
		return str(raw)
	}
	var b bytes.Buffer
	if json.Compact(&b, raw) != nil {
		return string(raw)
	}
	return b.String()
}

// mediaOf reads the media type of a data URL.
func mediaOf(url string) string {
	if rest, ok := strings.CutPrefix(url, "data:"); ok {
		media, _, _ := strings.Cut(rest, ";")
		return media
	}
	return ""
}

// roleOf gives messages made only of tool results the tool role.
func roleOf(role string, blocks []Block) string {
	if len(blocks) == 0 {
		return role
	}
	for _, b := range blocks {
		if b.Type != "tool_result" && !(b.ToolCallID != "" && (b.Type == "image" || b.Type == "file")) {
			return role
		}
	}
	return "tool"
}
