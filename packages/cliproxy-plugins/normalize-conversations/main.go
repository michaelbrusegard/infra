// Command normalize-conversations is the prototype normalizer described in
// docs/llm-conversations.md. It reads source rows as JSONEachRow and writes
// the canonical rows for each table into a directory, one JSONEachRow file
// per table.
//
// With -requests, input rows are llm.requests rows with their items, in
// start order, from requests.sql. Otherwise they are llm.transcripts rows
// from transcripts.sql, and -proxied names a file of session IDs whose
// messages the proxy owns.
//
// With -export openai or -export anthropic, it instead reads the messages
// of one conversation in order, as the conversation query in the design
// doc returns them, and prints them for training.
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

	"cliproxy-plugins/conversations"
)

func main() {
	log.SetFlags(0)
	requests := flag.Bool("requests", false, "read llm.requests rows instead of transcript lines")
	proxied := flag.String("proxied", "", "file of session IDs the proxy captured")
	out := flag.String("out", ".", "directory for the output files")
	export := flag.String("export", "", "print a conversation as openai or anthropic messages")
	flag.Parse()
	if *export != "" {
		if err := exportConversation(os.Stdin, os.Stdout, *export); err != nil {
			log.Fatal(err)
		}
		return
	}
	sessions := map[string]bool{}
	if *proxied != "" {
		data, err := os.ReadFile(*proxied)
		if err != nil {
			log.Fatal(err)
		}
		for _, s := range strings.Fields(string(data)) {
			sessions[s] = true
		}
	}
	if err := run(os.Stdin, *out, *requests, func(s string) bool { return sessions[s] }); err != nil {
		log.Fatal(err)
	}
}

var tables = []string{"llm.request_items", "llm.sessions", "llm.messages", "llm.calls", "llm.events"}

func run(r io.Reader, dir string, requests bool, proxied func(string) bool) error {
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
	n := conversations.NewNormalizer()
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
	dec := json.NewDecoder(bufio.NewReaderSize(r, 1<<20))
	var file []conversations.TranscriptLine
	for {
		if requests {
			var req conversations.Request
			if err := dec.Decode(&req); err == io.EOF {
				break
			} else if err != nil {
				return err
			}
			n.Request(req)
		} else {
			var line conversations.TranscriptLine
			err := dec.Decode(&line)
			if err != nil && err != io.EOF {
				return err
			}
			if len(file) > 0 && (err == io.EOF || line.Source != file[0].Source || line.Host != file[0].Host ||
				line.Session != file[0].Session || line.Path != file[0].Path) {
				n.Transcript(file, proxied)
				file = file[:0]
			}
			if err == io.EOF {
				break
			}
			file = append(file, line)
		}
		if err := drain(); err != nil {
			return err
		}
	}
	return drain()
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

func exportConversation(r io.Reader, w io.Writer, format string) error {
	var path []conversations.Message
	dec := json.NewDecoder(r)
	for {
		var m conversations.Message
		if err := dec.Decode(&m); err == io.EOF {
			break
		} else if err != nil {
			return err
		}
		path = append(path, m)
	}
	var out any
	switch format {
	case "openai":
		out = map[string]any{"messages": conversations.OpenAIChat(path)}
	case "anthropic":
		system, messages := conversations.AnthropicMessages(path)
		out = map[string]any{"system": system, "messages": messages}
	default:
		return fmt.Errorf("unknown export format %q", format)
	}
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	return enc.Encode(out)
}
