// Command normalize-conversations is the prototype normalizer described in
// docs/llm-conversations.md. It reads source rows as JSONEachRow and writes
// the canonical rows for each table into a directory, one JSONEachRow file
// per table.
//
// With -requests, input rows are llm.requests rows with their items, in
// start order, from requests.sql. A run first prints the sessions they
// touch with -sessions, then passes those sessions' state from state.sql
// with -state. Otherwise input rows are llm.transcripts rows from
// transcripts.sql, and -proxied names a file of the proxy's calls, each a
// session ID, its parent session and client, a response ID, and a start
// time, tab-separated.
//
// With -export openai or -export anthropic, it instead reads one call or
// conversation, as the call and conversation queries in the design doc
// return them, and prints it for training.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"cliproxy-plugins/conversations"
)

func main() {
	log.SetFlags(0)
	requests := flag.Bool("requests", false, "read llm.requests rows instead of transcript lines")
	sessions := flag.Bool("sessions", false, "print the sessions the requests touch, for state.sql")
	state := flag.String("state", "", "file of state.sql rows from earlier runs")
	hold := flag.Duration("hold", 10*time.Minute, "hold back requests that continue an unseen response and started this recently, or lack usage and completed this recently")
	proxied := flag.String("proxied", "", "file of the proxy's calls: session, parent session, client, response ID, and start")
	out := flag.String("out", ".", "directory for the output files")
	export := flag.String("export", "", "print a call or conversation as openai or anthropic messages")
	flag.Parse()
	var err error
	switch {
	case *export != "":
		err = exportConversation(os.Stdin, os.Stdout, *export)
	case *sessions:
		err = printSessions(os.Stdin, os.Stdout)
	case *requests:
		n := conversations.NewNormalizer()
		if *hold > 0 {
			n.HoldAfter = time.Now().UTC().Add(-*hold).Format("2006-01-02 15:04:05.000")
		}
		if err = restore(n, *state); err == nil {
			err = run(os.Stdin, *out, n, nil)
		}
	default:
		p := &conversations.Proxied{}
		if *proxied != "" {
			var data []byte
			if data, err = os.ReadFile(*proxied); err != nil {
				log.Fatal(err)
			}
			for _, line := range strings.Split(string(data), "\n") {
				if f := strings.Split(line, "\t"); len(f) == 5 {
					p.Add(f[0], f[1], f[2], f[3], f[4])
				}
			}
		}
		err = run(os.Stdin, *out, conversations.NewNormalizer(), p)
	}
	if err != nil {
		log.Fatal(err)
	}
}

func eachRow[T any](r io.Reader, f func(T) error) error {
	dec := json.NewDecoder(bufio.NewReaderSize(r, 1<<20))
	for {
		var row T
		if err := dec.Decode(&row); err == io.EOF {
			return nil
		} else if err != nil {
			return err
		}
		if err := f(row); err != nil {
			return err
		}
	}
}

// printSessions prints the sessions of the requests as a ClickHouse array,
// for the sessions parameter of state.sql.
func printSessions(r io.Reader, w io.Writer) error {
	seen := map[string]bool{}
	var quoted []string
	err := eachRow(r, func(req conversations.Request) error {
		if s := conversations.SessionOf(req); !seen[s] {
			seen[s] = true
			quoted = append(quoted, "'"+strings.NewReplacer(`\`, `\\`, `'`, `\'`).Replace(s)+"'")
		}
		return nil
	})
	if err != nil {
		return err
	}
	_, err = fmt.Fprintf(w, "[%s]\n", strings.Join(quoted, ","))
	return err
}

func restore(n *conversations.Normalizer, path string) error {
	if path == "" {
		return nil
	}
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return eachRow(f, func(s conversations.State) error { n.Restore(s); return nil })
}

var tables = []string{"llm.request_items", "llm.sessions", "llm.messages", "llm.calls", "llm.events"}

// run normalizes requests when proxied is nil, and transcript lines
// otherwise.
func run(r io.Reader, dir string, n *conversations.Normalizer, proxied *conversations.Proxied) error {
	files := map[string]*bufio.Writer{}
	for _, table := range tables {
		f, err := os.Create(filepath.Join(dir, table+".jsonl"))
		if err != nil {
			return err
		}
		defer f.Close()
		w := bufio.NewWriterSize(f, 1<<20)
		defer w.Flush()
		files[table] = w
	}
	// Rows are written as each unit is normalized, so memory holds only the
	// normalizer's index of nodes and items.
	drain := func() error {
		b := &n.Batch
		for _, err := range []error{writeRows(files["llm.request_items"], b.Items),
			writeRows(files["llm.sessions"], b.Sessions), writeRows(files["llm.messages"], b.Messages),
			writeRows(files["llm.calls"], b.Calls), writeRows(files["llm.events"], b.Events)} {
			if err != nil {
				return err
			}
		}
		b.Items, b.Sessions, b.Messages, b.Calls, b.Events = nil, nil, nil, nil, nil
		return nil
	}
	if proxied == nil {
		held := 0
		err := eachRow(r, func(req conversations.Request) error {
			if !n.Request(req) {
				held++
			}
			return drain()
		})
		if held > 0 {
			log.Printf("held back %d recent requests whose usage or previous response is not archived yet", held)
		}
		return err
	}
	var file []conversations.TranscriptLine
	flush := func() error {
		n.Transcript(file, proxied)
		file = file[:0]
		return drain()
	}
	err := eachRow(r, func(line conversations.TranscriptLine) error {
		if len(file) > 0 && (line.Source != file[0].Source || line.Host != file[0].Host ||
			line.Session != file[0].Session || line.Path != file[0].Path) {
			if err := flush(); err != nil {
				return err
			}
		}
		file = append(file, line)
		return nil
	})
	if err != nil {
		return err
	}
	return flush()
}

func writeRows[T any](w *bufio.Writer, rows []T) error {
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	for _, row := range rows {
		if err := enc.Encode(row); err != nil {
			return err
		}
	}
	return nil
}

// exportConversation reads message rows in conversation order, and for a
// call, rows with a field and value: the system prompt, instructions, or
// tools the call sent, and its response, which may echo them.
func exportConversation(r io.Reader, w io.Writer, format string) error {
	var ctx conversations.Context
	var path []conversations.Message
	type row struct {
		conversations.Message
		Field string `json:"field"`
		Value string `json:"value"`
	}
	err := eachRow(r, func(row row) error {
		if row.Field != "" {
			ctx.Add(row.Field, []byte(row.Value))
		} else {
			path = append(path, row.Message)
		}
		return nil
	})
	if err != nil {
		return err
	}
	var out any
	switch format {
	case "openai":
		out, err = conversations.OpenAIChat(ctx, path)
	case "anthropic":
		out, err = conversations.AnthropicMessages(ctx, path)
	default:
		return fmt.Errorf("unknown export format %q", format)
	}
	if err != nil {
		return err
	}
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	return enc.Encode(out)
}
