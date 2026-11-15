package conversations

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"hash"
	"sort"
	"strconv"
	"unicode/utf8"
)

// Claude Code's request logs name each message a request sent by a hash:
// the SHA-256 of the message as JSON, {role, content}, with sorted keys,
// no whitespace, and strings escaped as JSON.stringify escapes them. It
// logs a message as a blob only when it is not one of the file's own
// lines. The others are the file's message lines as the API received
// them, which on 2026-11-14 resolved every reference of the 952 requests
// no reply names, 200,835 with their base requests' messages:
//
//   - a user or assistant line's message, or one with string content sent
//     as a single text block, as Claude Code sends the last message, which
//     it marks for the cache;
//   - an assistant reply, whose streamed blocks are a line each, as one
//     message with the blocks of all its lines;
//   - consecutive user lines, such as a turn's tool results or a prompt
//     queued after them, as one message with all their blocks: the API
//     takes no two user messages in a row.

// sentLine is a message line the file keeps, as Claude Code sent it.
type sentLine struct {
	role    string
	content json.RawMessage
	// The assistant reply the line streams a block of.
	reply string
}

// sentMessages returns the hashes of every message the file's kept lines
// can have been sent as.
func sentMessages(lines []sentLine) map[string]bool {
	out := map[string]bool{}
	add := func(role string, blocks ...[]byte) {
		out[messageHash(role, blocks, nil)] = true
	}
	var replies []string
	reply := map[string][][]byte{}
	var users [][][]byte
	flush := func() {
		// Each run of user lines grows a line at a time, and each
		// request sends the run as long as it was then.
		if len(users) > 1 {
			for _, sum := range prefixHashes("user", users) {
				out[sum] = true
			}
		}
		users = nil
	}
	for _, l := range lines {
		blocks := contentBlocks(l.content)
		if isString(l.content) {
			out[messageHash(l.role, nil, l.content)] = true
		}
		add(l.role, blocks...)
		switch l.role {
		case "assistant":
			flush()
			if l.reply != "" {
				if _, ok := reply[l.reply]; !ok {
					replies = append(replies, l.reply)
				}
				reply[l.reply] = append(reply[l.reply], blocks...)
			}
		case "user":
			users = append(users, blocks)
		}
	}
	flush()
	for _, id := range replies {
		add("assistant", reply[id]...)
	}
	return out
}

// contentBlocks returns the canonical JSON of each block of content, a
// string being one text block.
func contentBlocks(content json.RawMessage) [][]byte {
	if isString(content) {
		return [][]byte{canonicalJSON(json.RawMessage(`{"type":"text","text":` + string(content) + `}`))}
	}
	var out [][]byte
	for _, raw := range array(content) {
		out = append(out, canonicalJSON(raw))
	}
	return out
}

// messageHash returns Claude Code's hash of a message: of its content
// blocks, or of content itself when it is a string.
func messageHash(role string, blocks [][]byte, content json.RawMessage) string {
	h := sha256.New()
	h.Write([]byte(`{"content":`))
	if content != nil {
		h.Write(canonicalJSON(content))
	} else {
		h.Write([]byte(`[`))
		h.Write(bytes.Join(blocks, []byte(",")))
		h.Write([]byte(`]`))
	}
	writeRole(h, role)
	return hex.EncodeToString(h.Sum(nil))
}

// prefixHashes returns the hash of the message of each prefix of parts
// longer than one part, of role, hashing each block once.
func prefixHashes(role string, parts [][][]byte) []string {
	var out []string
	h := sha256.New()
	h.Write([]byte(`{"content":[`))
	first := true
	for i, blocks := range parts {
		for _, b := range blocks {
			if !first {
				h.Write([]byte(","))
			}
			first = false
			h.Write(b)
		}
		if i == 0 {
			continue
		}
		c := h.(hash.Cloner)
		end, _ := c.Clone()
		end.Write([]byte(`]`))
		writeRole(end, role)
		out = append(out, hex.EncodeToString(end.Sum(nil)))
	}
	return out
}

func writeRole(h hash.Hash, role string) {
	h.Write([]byte(`,"role":`))
	h.Write(jsString(role))
	h.Write([]byte(`}`))
}

// canonicalJSON writes raw with sorted keys and no whitespace. Numbers keep
// their text, which Claude Code wrote as JavaScript formats them.
func canonicalJSON(raw json.RawMessage) []byte {
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	var v any
	if d.Decode(&v) != nil {
		return raw
	}
	var buf bytes.Buffer
	writeCanonical(&buf, v)
	return buf.Bytes()
}

func writeCanonical(buf *bytes.Buffer, v any) {
	switch v := v.(type) {
	case map[string]any:
		keys := make([]string, 0, len(v))
		for k := range v {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		buf.WriteByte('{')
		for i, k := range keys {
			if i > 0 {
				buf.WriteByte(',')
			}
			buf.Write(jsString(k))
			buf.WriteByte(':')
			writeCanonical(buf, v[k])
		}
		buf.WriteByte('}')
	case []any:
		buf.WriteByte('[')
		for i, e := range v {
			if i > 0 {
				buf.WriteByte(',')
			}
			writeCanonical(buf, e)
		}
		buf.WriteByte(']')
	case string:
		buf.Write(jsString(v))
	case json.Number:
		buf.WriteString(v.String())
	case bool:
		buf.WriteString(strconv.FormatBool(v))
	default:
		buf.WriteString("null")
	}
}

// jsString quotes s as JSON.stringify does: unlike encoding/json, it
// leaves <, >, &, U+2028 and U+2029 as they are.
func jsString(s string) []byte {
	buf := []byte{'"'}
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		switch {
		case r == '"' || r == '\\':
			buf = append(buf, '\\', byte(r))
		case r == '\b':
			buf = append(buf, `\b`...)
		case r == '\f':
			buf = append(buf, `\f`...)
		case r == '\n':
			buf = append(buf, `\n`...)
		case r == '\r':
			buf = append(buf, `\r`...)
		case r == '\t':
			buf = append(buf, `\t`...)
		case r < 0x20:
			buf = append(buf, fmt.Sprintf(`\u%04x`, r)...)
		default:
			buf = append(buf, s[i:i+size]...)
		}
		i += size
	}
	return append(buf, '"')
}
