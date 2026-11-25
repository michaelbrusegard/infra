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

type Block struct {
	Type          string `json:"type"`
	SourceType    string `json:"source_type"`
	Text          string `json:"text"`
	ToolName      string `json:"tool_name"`
	ToolNamespace string `json:"tool_namespace"`
	ToolCallID    string `json:"tool_call_id"`
	ToolInput     string `json:"tool_input"`
	IsError       bool   `json:"is_error"`
	Media         string `json:"media"`
}

type Message struct {
	SessionID string  `json:"session_id"`
	ID        Hash    `json:"id"`
	ParentID  Hash    `json:"parent_id"`
	Seq       uint32  `json:"seq"`
	TS        string  `json:"ts"`
	Role      string  `json:"role"`
	Output    bool    `json:"output"`
	Model     string  `json:"model"`
	CallID    string  `json:"call_id"`
	Blocks    []Block `json:"blocks"`
	Format    string  `json:"format"`
	Item      Hash    `json:"item"`
	Host      string  `json:"host"`
	Path      string  `json:"path"`
	Line      string  `json:"line"`
	Part      string  `json:"part"`
	Version   uint64  `json:"version"`
}

type Call struct {
	CallID              string              `json:"call_id"`
	SessionID           string              `json:"session_id"`
	ResponseID          string              `json:"response_id"`
	StartedAt           string              `json:"started_at"`
	CompletedAt         string              `json:"completed_at"`
	Origin              string              `json:"origin"`
	Client              string              `json:"client"`
	RequestID           string              `json:"request_id"`
	Host                string              `json:"host"`
	Path                string              `json:"path"`
	SourceFormat        string              `json:"source_format"`
	Model               string              `json:"model"`
	InputID             Hash                `json:"input_id"`
	OutputIDs           []Hash              `json:"output_ids"`
	UncachedInputTokens uint64              `json:"uncached_input_tokens"`
	CacheReadTokens     uint64              `json:"cache_read_tokens"`
	CacheWriteTokens    uint64              `json:"cache_write_tokens"`
	CacheWrite5mTokens  uint64              `json:"cache_write_5m_tokens"`
	CacheWrite1hTokens  uint64              `json:"cache_write_1h_tokens"`
	OutputTokens        uint64              `json:"output_tokens"`
	ReasoningTokens     uint64              `json:"reasoning_tokens"`
	Context             []requestitems.Part `json:"context"`
}

type Session struct {
	SessionID       string `json:"session_id"`
	ParentSessionID string `json:"parent_session_id"`
	Client          string `json:"client"`
	Origin          string `json:"origin"`
	Host            string `json:"host"`
	Path            string `json:"path"`
	Title           string `json:"title"`
	Cwd             string `json:"cwd"`
}

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

func itemHash(raw []byte) Hash {
	return requestitems.HashOf(bytes.ToValidUTF8(raw, []byte("\uFFFD")))
}

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

type Uint64 uint64

func (u *Uint64) UnmarshalJSON(data []byte) error {
	n, err := strconv.ParseUint(strings.Trim(string(data), `"`), 10, 64)
	*u = Uint64(n)
	return err
}

func nodeID(session string, parent Hash, key string) Hash {
	var seed []byte
	if parent == (Hash{}) {
		seed = append([]byte("root\x00"), session...)
	} else {
		seed = append([]byte("node\x00"), parent[:]...)
	}
	return requestitems.HashOf(append(append(seed, 0), key...))
}

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
	_ = json.Unmarshal(o[key], &v)
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
	_ = json.Unmarshal(raw, &s)
	return s
}

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

func mediaOf(url string) string {
	if rest, ok := strings.CutPrefix(url, "data:"); ok {
		media, _, _ := strings.Cut(rest, ";")
		return media
	}
	return ""
}

func roleOf(role string, blocks []Block) string {
	if len(blocks) == 0 {
		return role
	}
	for _, b := range blocks {
		if b.Type != "tool_result" && (b.ToolCallID == "" || (b.Type != "image" && b.Type != "file")) {
			return role
		}
	}
	return "tool"
}
