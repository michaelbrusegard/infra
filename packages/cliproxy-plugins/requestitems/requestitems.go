// Package requestitems splits archived request bodies into content-addressed
// items. Every turn of a conversation resends all earlier turns, so storing
// each message, tool, and large value once makes the archive grow with new
// content instead of with the square of the conversation length.
//
// The archive plugin and the one-off backfill both use this package, so the
// items, and therefore their hashes, are byte-identical however a row was
// written. ClickHouse's own JSON functions cannot reproduce them: they rewrite
// numbers and escapes.
package requestitems

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"math/big"
	"strconv"
)

// Values at least this long leave the envelope even when they are not arrays,
// such as a long system prompt or instructions string.
const LargeValueBytes = 1024

// A part's encoded size beyond its field name: position, hash and JSON
// punctuation. Bodies whose parts would outweigh both the body and
// smallPartsBytes are kept whole, which bounds how much splitting can grow a
// row; small bodies split normally.
const (
	partOverheadBytes = 64
	smallPartsBytes   = 64 << 10
)

// Hash is the first 16 bytes of an item's SHA-256. ClickHouse reads them as a
// little-endian UInt128, which equals
// reinterpretAsUInt128(substring(SHA256(item), 1, 16)).
type Hash [16]byte

func HashOf(item []byte) Hash {
	sum := sha256.Sum256(item)
	return Hash(sum[:16])
}

// String is the decimal UInt128, the form ClickHouse reads from JSON.
func (h Hash) String() string {
	var be [16]byte
	for i, b := range h {
		be[15-i] = b
	}
	return new(big.Int).SetBytes(be[:]).String()
}

func (h Hash) MarshalJSON() ([]byte, error) {
	return strconv.AppendQuote(nil, h.String()), nil
}

// Part references one item. Position is the index within a top-level array,
// or -1 when the item is the whole value. A body that is not a JSON object is
// a single part with an empty field.
type Part struct {
	Field    string `json:"field"`
	Position int32  `json:"position"`
	Hash     Hash   `json:"hash"`
}

// Body is a request body split into an envelope and its parts. Items[i] holds
// the content of Parts[i].
type Body struct {
	// The JSON object of the remaining top-level keys, in their original
	// order, or empty when the body is not a JSON object.
	Envelope string
	Parts    []Part
	Items    [][]byte
}

// Split splits a body. JSON objects are compacted first: insignificant
// whitespace is the only thing dropped, and every token keeps its original
// bytes. Each top-level array element becomes an item, and so does any other
// value of at least LargeValueBytes. Empty arrays, small values, and keys
// containing escapes stay in the envelope. Anything else, such as a truncated
// body, is kept verbatim as one item. So are objects with a repeated key,
// whose meaning depends on member order, and objects whose parts would
// outweigh the body, such as huge arrays of tiny values.
func Split(body []byte) Body {
	// Rows reach ClickHouse as JSON, which would replace invalid UTF-8 after
	// hashing. Replace it first so a stored item always matches its hash.
	body = bytes.ToValidUTF8(body, []byte("\uFFFD"))
	whole := Body{Parts: []Part{{Position: -1, Hash: HashOf(body)}}, Items: [][]byte{body}}
	var compact bytes.Buffer
	if json.Compact(&compact, body) != nil || compact.Len() == 0 || compact.Bytes()[0] != '{' {
		return whole
	}
	b := compact.Bytes()
	var out Body
	partBytes := 0
	add := func(field []byte, position int, item []byte) {
		out.Parts = append(out.Parts, Part{Field: string(field), Position: int32(position), Hash: HashOf(item)})
		out.Items = append(out.Items, item)
		partBytes += len(field) + partOverheadBytes
	}
	seen := map[string]struct{}{}
	envelope := []byte{'{'}
	for i := 1; b[i] != '}'; {
		keyEnd := valueEnd(b, i)
		field := b[i+1 : keyEnd-1]
		value := b[keyEnd+1 : valueEnd(b, keyEnd+1)]
		end := keyEnd + 1 + len(value)
		var key string
		if json.Unmarshal(b[i:keyEnd], &key) != nil {
			return whole
		}
		if _, dup := seen[key]; dup {
			return whole
		}
		seen[key] = struct{}{}
		switch {
		case bytes.IndexByte(field, '\\') >= 0:
			envelope = appendMember(envelope, b[i:end])
		case value[0] == '[' && len(value) > 2:
			for j, position := 1, 0; ; position++ {
				e := valueEnd(value, j)
				add(field, position, value[j:e])
				if value[e] == ']' {
					break
				}
				j = e + 1
			}
		case len(value) >= LargeValueBytes:
			add(field, -1, value)
		default:
			envelope = appendMember(envelope, b[i:end])
		}
		i = end
		if b[i] == ',' {
			i++
		}
	}
	if partBytes > max(len(body), smallPartsBytes) {
		return whole
	}
	out.Envelope = string(append(envelope, '}'))
	return out
}

func appendMember(envelope, member []byte) []byte {
	if len(envelope) > 1 {
		envelope = append(envelope, ',')
	}
	return append(envelope, member...)
}

// valueEnd returns the index just past the value starting at b[i]. b must be
// valid, compacted JSON.
func valueEnd(b []byte, i int) int {
	switch b[i] {
	case '"':
		for i++; b[i] != '"'; i++ {
			if b[i] == '\\' {
				i++
			}
		}
		return i + 1
	case '{', '[':
		for depth := 0; ; i++ {
			switch b[i] {
			case '"':
				i = valueEnd(b, i) - 1
			case '{', '[':
				depth++
			case '}', ']':
				if depth--; depth == 0 {
					return i + 1
				}
			}
		}
	default:
		for i < len(b) && b[i] != ',' && b[i] != '}' && b[i] != ']' {
			i++
		}
		return i
	}
}

// JSON reassembles the body. The split keys follow the envelope's keys, so
// the result equals the original apart from whitespace and key order. The
// llm.request_bodies view builds the same bytes.
func (b Body) JSON() []byte {
	if b.Envelope == "" {
		if len(b.Items) == 0 {
			return nil
		}
		return b.Items[0]
	}
	out := []byte(b.Envelope[:len(b.Envelope)-1])
	for k, p := range b.Parts {
		if p.Position <= 0 {
			if k > 0 || b.Envelope != "{}" {
				out = append(out, ',')
			}
			out = append(out, '"')
			out = append(out, p.Field...)
			out = append(out, '"', ':')
			if p.Position == 0 {
				out = append(out, '[')
			}
		} else {
			out = append(out, ',')
		}
		out = append(out, b.Items[k]...)
		if p.Position >= 0 && (k == len(b.Parts)-1 || b.Parts[k+1].Position <= 0) {
			out = append(out, ']')
		}
	}
	return append(out, '}')
}
