package requestitems

import (
	"bytes"
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"
)

type fixture struct {
	Name string
	Body string
}

func fixtures(t *testing.T) []fixture {
	t.Helper()
	data, err := os.ReadFile("testdata/bodies.json")
	if err != nil {
		t.Fatal(err)
	}
	var out []fixture
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

// decode keeps numbers as written, so a rewritten numeral fails the
// comparison.
func decode(t *testing.T, data []byte) any {
	t.Helper()
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var v any
	if err := dec.Decode(&v); err != nil {
		t.Fatalf("decode %q: %v", data, err)
	}
	return v
}

func TestSplitRoundTripsFixtures(t *testing.T) {
	for _, f := range fixtures(t) {
		t.Run(f.Name, func(t *testing.T) {
			body := []byte(f.Body)
			split := Split(body)
			if len(split.Parts) != len(split.Items) {
				t.Fatalf("%d parts for %d items", len(split.Parts), len(split.Items))
			}
			for i, item := range split.Items {
				if split.Parts[i].Hash != HashOf(item) {
					t.Fatalf("part %d hash does not match its item", i)
				}
			}
			joined := split.JSON()
			if split.Envelope == "" {
				if !bytes.Equal(joined, body) {
					t.Fatalf("non-object body changed: %q", joined)
				}
				return
			}
			if !reflect.DeepEqual(decode(t, joined), decode(t, body)) {
				t.Fatalf("reassembled body differs:\n%s", joined)
			}
			// The backfill and the plugin must agree on any body, including
			// one that has already been through a round trip.
			if again := Split(joined); !reflect.DeepEqual(again, split) {
				t.Fatalf("splitting the reassembled body changed it: %+v", again)
			}
		})
	}
}

func TestSplitKeepsTokenBytes(t *testing.T) {
	split := Split([]byte(`{ "a" : [ 1.0 , "\u00e9\/" , { "b" : [ ] } ], "c" : -0, "d" : [ ] }`))
	if split.Envelope != `{"c":-0,"d":[]}` {
		t.Fatalf("envelope %s", split.Envelope)
	}
	want := []string{`1.0`, `"\u00e9\/"`, `{"b":[]}`}
	if len(split.Items) != len(want) {
		t.Fatalf("items %q", split.Items)
	}
	for i, item := range split.Items {
		if string(item) != want[i] {
			t.Fatalf("item %d is %s, want %s", i, item, want[i])
		}
		if p := split.Parts[i]; p.Field != "a" || p.Position != int32(i) {
			t.Fatalf("part %d is %+v", i, p)
		}
	}
	if got := string(split.JSON()); got != `{"c":-0,"d":[],"a":[1.0,"\u00e9\/",{"b":[]}]}` {
		t.Fatalf("reassembled %s", got)
	}
}

func TestSplitMovesOnlyLargeScalars(t *testing.T) {
	short := strings.Repeat("x", LargeValueBytes-3)
	long := strings.Repeat("x", LargeValueBytes-2)
	split := Split([]byte(`{"short":"` + short + `","long":"` + long + `"}`))
	if split.Envelope != `{"short":"`+short+`"}` {
		t.Fatalf("envelope %s", split.Envelope)
	}
	if len(split.Parts) != 1 || split.Parts[0] != (Part{Field: "long", Position: -1, Hash: HashOf([]byte(`"` + long + `"`))}) {
		t.Fatalf("parts %+v", split.Parts)
	}
}

func TestSplitKeepsEscapedKeysInEnvelope(t *testing.T) {
	// The view writes field names without escaping them.
	split := Split([]byte(`{"mess\u0061ges":[1],"a\"b":[2]}`))
	if split.Envelope != `{"mess\u0061ges":[1],"a\"b":[2]}` || len(split.Parts) != 0 {
		t.Fatalf("split into %+v", split)
	}
}

func TestSplitKeepsNonObjectsVerbatim(t *testing.T) {
	for _, body := range []string{"", "  ", "[1, 2]", `"x"`, `{"a":`, `{"a":1} x`} {
		split := Split([]byte(body))
		if split.Envelope != "" || len(split.Parts) != 1 || string(split.Items[0]) != body {
			t.Fatalf("%q split into %+v", body, split)
		}
		if p := split.Parts[0]; p.Field != "" || p.Position != -1 {
			t.Fatalf("%q part %+v", body, p)
		}
	}
}

func TestSplitReplacesInvalidUTF8(t *testing.T) {
	split := Split([]byte("{\"messages\":[\"a\xffb\"]}"))
	if got := string(split.Items[0]); got != "\"a\uFFFDb\"" {
		t.Fatalf("item %q", got)
	}
	if split.Parts[0].Hash != HashOf(split.Items[0]) {
		t.Fatal("hash covers the bytes before replacement")
	}
}

func TestHashMatchesClickHouse(t *testing.T) {
	// SELECT reinterpretAsUInt128(substring(SHA256(item), 1, 16))
	for item, want := range map[string]string{
		"":                "48815046298653952574165987754911248611",
		`{"role":"user"}`: "272458832270458307467492949439356678251",
	} {
		if got := HashOf([]byte(item)).String(); got != want {
			t.Fatalf("hash of %q is %s, want %s", item, got, want)
		}
	}
	data, _ := json.Marshal(Part{Field: "messages", Hash: HashOf(nil)})
	if string(data) != `{"field":"messages","position":0,"hash":"48815046298653952574165987754911248611"}` {
		t.Fatalf("part encodes as %s", data)
	}
}
