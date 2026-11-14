// Command request-backfill splits archived request bodies the same way the
// clickhouse-archive plugin does, for the one-off migration of rows written
// before llm.request_items existed. See
// gitops/espresso/apps/clickhouse/migrate-request-items.sh.
//
// It reads JSONEachRow rows of request_id and request_body, and writes each
// row's envelope and parts, the hash of the body the llm.request_bodies view
// should rebuild, and the items not yet written by this process.
package main

import (
	"bufio"
	"encoding/json"
	"io"
	"log"
	"os"

	"cliproxy-plugins/requestitems"
)

type input struct {
	RequestID   string `json:"request_id"`
	RequestBody string `json:"request_body"`
}

type item struct {
	Hash requestitems.Hash `json:"hash"`
	Item string            `json:"item"`
}

type output struct {
	RequestID       string              `json:"request_id"`
	RequestEnvelope string              `json:"request_envelope"`
	RequestParts    []requestitems.Part `json:"request_parts"`
	BodyHash        requestitems.Hash   `json:"body_hash"`
	Items           []item              `json:"items"`
}

func main() {
	log.SetFlags(0)
	if err := run(os.Stdin, os.Stdout); err != nil {
		log.Fatal(err)
	}
}

func run(r io.Reader, w io.Writer) error {
	dec := json.NewDecoder(bufio.NewReaderSize(r, 1<<20))
	out := bufio.NewWriterSize(w, 1<<20)
	enc := json.NewEncoder(out)
	enc.SetEscapeHTML(false)
	written := map[requestitems.Hash]struct{}{}
	for {
		var in input
		if err := dec.Decode(&in); err == io.EOF {
			break
		} else if err != nil {
			return err
		}
		body := requestitems.Split([]byte(in.RequestBody))
		row := output{
			RequestID:       in.RequestID,
			RequestEnvelope: body.Envelope,
			RequestParts:    body.Parts,
			BodyHash:        requestitems.HashOf(body.JSON()),
			Items:           []item{},
		}
		for i, p := range body.Parts {
			if _, ok := written[p.Hash]; !ok {
				written[p.Hash] = struct{}{}
				row.Items = append(row.Items, item{p.Hash, string(body.Items[i])})
			}
		}
		if err := enc.Encode(row); err != nil {
			return err
		}
	}
	return out.Flush()
}
