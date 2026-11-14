// Command normalize-conversations is the prototype normalizer described in
// docs/llm-conversations.md. It reads source rows as JSONEachRow and writes
// the canonical rows for each table into a directory, one JSONEachRow file
// per table.
//
// Proxy rows reference the raw capture and copy none of it. Transcript rows
// hold their own content, since llm.transcripts is dropped after the import,
// and the transcript run also writes llm.request_items rows for the system
// prompts and tools of Claude Code calls, and coverage.tsv: how many lines
// of each source and kind became what.
//
// With -requests, input rows on stdin are llm.requests rows with their
// items, in start order, from requests.sql. A run first prints the sessions
// they touch with -sessions, then passes those sessions' state from
// state.sql with -state. Otherwise -in names a file of llm.transcripts rows
// from transcripts.sql, plain or gzip-compressed as ClickHouse's HTTP
// interface sends it, which is read twice, and -proxied names a file of the
// proxy's calls, each a session ID, its parent session and client, a
// response ID, and a start time, tab-separated.
//
// With -export openai or -export anthropic, it instead reads one call or
// conversation, as the call and conversation queries in the design doc
// return them, and prints it for training. A call that is no training
// example, because it produced nothing, or its output calls tools its
// context does not define or with arguments cut short, fails with the
// reason.
package main

import (
	"bufio"
	"compress/gzip"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sort"
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
	in := flag.String("in", "", "file of transcript lines from transcripts.sql, plain or gzip-compressed")
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
			err = run(*out, n, func(drain func() error) error { return normalizeRequests(os.Stdin, n, drain) })
		}
	case *in == "":
		err = errors.New("-in names no file of transcript lines")
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
		n := conversations.NewNormalizer()
		err = run(*out, n, func(drain func() error) error { return normalizeTranscripts(*in, n, p, drain) })
		if err == nil {
			err = writeCoverage(filepath.Join(*out, "coverage.tsv"), n.Coverage)
		}
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
	n := conversations.NewNormalizer()
	err := eachRow(r, func(req conversations.Request) error {
		if s := n.SessionOf(req); !seen[s] {
			seen[s] = true
			quoted = append(quoted, "'"+strings.NewReplacer(`\`, `\\`, `'`, `\'`).Replace(s)+"'")
		}
		return nil
	})
	if err = errors.Join(err, n.Err); err != nil {
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

// run creates an output file per table and calls normalize, whose drain
// writes the rows normalized so far.
func run(dir string, n *conversations.Normalizer, normalize func(drain func() error) error) (err error) {
	files := map[string]*bufio.Writer{}
	for _, table := range tables {
		f, createErr := os.Create(filepath.Join(dir, table+".jsonl"))
		if createErr != nil {
			return createErr
		}
		w := bufio.NewWriterSize(f, 1<<20)
		// A full disk may only show when the last rows are flushed, or when
		// the file is closed, and any lost row must fail the run.
		defer func() { err = errors.Join(err, w.Flush(), f.Close()) }()
		files[table] = w
	}
	// Rows are written as each unit is normalized, so memory holds only the
	// normalizer's index of nodes.
	return normalize(func() error {
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
	})
}

func normalizeRequests(r io.Reader, n *conversations.Normalizer, drain func() error) error {
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
	return errors.Join(err, n.Err)
}

// normalizeTranscripts reads the file twice: the first pass decides which
// transcript file holds each reply's call, and the second normalizes.
func normalizeTranscripts(path string, n *conversations.Normalizer, proxied *conversations.Proxied, drain func() error) error {
	replies := &conversations.Replies{}
	for _, pass := range []func([]conversations.TranscriptLine) error{
		func(file []conversations.TranscriptLine) error { replies.Add(file, proxied); return nil },
		func(file []conversations.TranscriptLine) error { n.Transcript(file, replies, proxied); return drain() },
	} {
		if err := readFile(path, func(r io.Reader) error { return eachFile(r, pass) }); err != nil {
			return err
		}
	}
	// Calls under these keys are matched by response ID only, so a copy
	// without one counts again; the collision audit needs every key.
	if conflicts := replies.Conflicts(); len(conflicts) > 0 {
		log.Printf("%d Codex item keys name more than one response ID:\n%s", len(conflicts), strings.Join(conflicts, "\n"))
	}
	return n.CoverageError()
}

// writeCoverage writes the source, kind, disposition, and number of lines
// of every kind of transcript line, sorted.
func writeCoverage(path string, coverage map[conversations.Covered]int) error {
	var rows []string
	for c, lines := range coverage {
		rows = append(rows, fmt.Sprintf("%s\t%s\t%s\t%d", c.Source, c.Kind, c.Disposition, lines))
	}
	sort.Strings(rows)
	return os.WriteFile(path, []byte(strings.Join(rows, "\n")+"\n"), 0o644)
}

// readFile reads a file, decompressing it if it is gzip.
func readFile(path string, read func(io.Reader) error) (err error) {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, f.Close()) }()
	r := bufio.NewReaderSize(f, 1<<20)
	if magic, _ := r.Peek(2); len(magic) == 2 && magic[0] == 0x1f && magic[1] == 0x8b {
		z, err := gzip.NewReader(r)
		if err != nil {
			return err
		}
		// Reading the rows to EOF verifies the checksum.
		return read(z)
	}
	return read(r)
}

// eachFile reads transcript lines grouped by file, as transcripts.sql
// orders them.
func eachFile(r io.Reader, f func([]conversations.TranscriptLine) error) error {
	var file []conversations.TranscriptLine
	err := eachRow(r, func(line conversations.TranscriptLine) error {
		if len(file) > 0 && (line.Source != file[0].Source || line.Host != file[0].Host ||
			line.Session != file[0].Session || line.Path != file[0].Path) {
			if err := f(file); err != nil {
				return err
			}
			file = nil
		}
		file = append(file, line)
		return nil
	})
	if err != nil || len(file) == 0 {
		return err
	}
	return f(file)
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
// call, a row with the field call, which marks the rows as a call's, and
// rows with a field and value: the system prompt, instructions, or tools
// the call sent, and its response, which may echo them. A call is checked
// as a training example, even with no context or outputs.
func exportConversation(r io.Reader, w io.Writer, format string) error {
	var ctx conversations.Context
	var path []conversations.Message
	var outputs []conversations.Hash
	call := false
	type row struct {
		conversations.Message
		Field string `json:"field"`
		Value string `json:"value"`
		// The message is one of the call's outputs.
		CallOutput bool `json:"call_output"`
	}
	err := eachRow(r, func(row row) error {
		switch row.Field {
		case "call":
			call = true
		case "":
			path = append(path, row.Message)
		default:
			call = true
			ctx.Add(row.Field, []byte(row.Value))
		}
		if row.CallOutput {
			outputs = append(outputs, row.ID)
		}
		return nil
	})
	if err != nil {
		return err
	}
	if call {
		if err := conversations.ForTraining(ctx, path, outputs); err != nil {
			return err
		}
	}
	var out any
	switch format {
	case "openai":
		out, err = conversations.OpenAIChat(ctx, path, outputs)
	case "anthropic":
		out, err = conversations.AnthropicMessages(ctx, path, outputs)
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
