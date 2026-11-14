package conversations

import (
	"encoding/json"
	"path"
	"sort"
	"strconv"
	"strings"

	"cliproxy-plugins/requestitems"
)

// TranscriptLine is a row of llm.transcripts.
type TranscriptLine struct {
	Source  string `json:"source"`
	Host    string `json:"host"`
	Session string `json:"session"`
	ID      string `json:"id"`
	Path    string `json:"path"`
	Line    string `json:"line"`
	TS      string `json:"ts"`
}

// file is the state of one transcript file being normalized.
type file struct {
	n       *Normalizer
	session Session
	// Whether the proxy owns this session's messages.
	proxied bool
	ts      string
	// Entry IDs to their parent entry, and entries that became messages, for
	// sources that record a tree.
	parents map[string]string
	nodes   map[string]Hash
	last    Hash
	calls   map[string]*Call
	order   []string
}

// Transcript normalizes the lines of one transcript file, in file order.
// Every line becomes exactly one message or event that references the line
// verbatim. A session the proxy also captured keeps its lines as events
// only: its messages come from the proxy, so nothing is counted twice.
func (n *Normalizer) Transcript(lines []TranscriptLine, proxied func(session string) bool) {
	if len(lines) == 0 {
		return
	}
	f := &file{n: n, parents: map[string]string{}, nodes: map[string]Hash{}, calls: map[string]*Call{}}
	f.session = transcriptSession(lines)
	f.proxied = proxied != nil && proxied(f.session.SessionID)
	switch lines[0].Source {
	case "claude-code":
		f.claudeCode(lines)
	case "codex":
		f.codex(lines)
	case "pi":
		f.pi(lines)
	case "opencode":
		f.opencode(lines)
	default:
		for _, l := range lines {
			f.event(l, "")
		}
	}
	n.session(f.session)
	for _, id := range f.order {
		n.Calls = append(n.Calls, *f.calls[id])
	}
}

// transcriptSession names a file's session in CLIProxy's scheme, so a
// session recorded by both a transcript and the proxy has one ID.
func transcriptSession(lines []TranscriptLine) Session {
	l := lines[0]
	s := Session{Client: l.Source, Origin: "transcript", Host: l.Host, Path: l.Path}
	stem := strings.TrimSuffix(path.Base(l.Path), ".jsonl")
	switch l.Source {
	case "claude-code":
		// .claude/projects/<project>/<session>.jsonl, or for sub-agents
		// <project>/<session>/subagents/[workflows/<id>/]agent-<id>.jsonl.
		parts := strings.Split(l.Path, "/")
		if i := indexOf(parts, "subagents"); i > 0 {
			parent := "claude:" + parts[i-1]
			s.ParentSessionID = parent
			if agent, ok := strings.CutPrefix(stem, "agent-"); ok {
				s.SessionID = parent + ":agent:" + agent
			} else {
				s.SessionID = parent + ":" + strings.Join(parts[i+1:len(parts)-1], ":")
			}
		} else {
			s.SessionID = "claude:" + stem
		}
	case "codex":
		id := stem
		if len(stem) >= 36 {
			id = stem[len(stem)-36:]
		}
		s.SessionID = "codex:" + id
		for _, line := range lines {
			if parse([]byte(line.Line)).str("type") != "session_meta" {
				continue
			}
			meta := parse([]byte(line.Line)).obj("payload")
			s.Cwd = meta.str("cwd")
			s.SessionID = "codex:" + firstNonEmpty(meta.str("id"), id)
			spawn := meta.obj("source").obj("subagent").obj("thread_spawn")
			if parent := spawn.str("parent_thread_id"); parent != "" {
				s.ParentSessionID = "codex:" + parent
				s.SessionID = "codex:" + parent + ":agent:" + strings.TrimPrefix(spawn.str("agent_path"), "/root/")
			}
			break
		}
	case "pi":
		_, id, _ := strings.Cut(stem, "_")
		s.SessionID = "pi:" + firstNonEmpty(id, stem)
	case "opencode":
		s.SessionID = "opencode:" + l.Session
	default:
		s.SessionID = l.Source + ":" + l.Session
	}
	return s
}

func indexOf(list []string, v string) int {
	for i, s := range list {
		if s == v {
			return i
		}
	}
	return -1
}

// stamp returns the line's time, or the previous line's when it has none.
func (f *file) stamp(l TranscriptLine) string {
	if l.TS != "" && !strings.HasPrefix(l.TS, "1970-") {
		f.ts = l.TS
	}
	if f.ts == "" {
		return "1970-01-01 00:00:00.000"
	}
	return f.ts
}

func (f *file) event(l TranscriptLine, kind string) {
	f.n.Events = append(f.n.Events, Event{SessionID: f.session.SessionID, TS: f.stamp(l), Line: l.ID,
		Type: kind, Item: f.n.item([]byte(l.Line))})
}

// message adds a line as a message under parent, keyed by its entry ID.
func (f *file) message(l TranscriptLine, parent Hash, key string, m Message) Hash {
	m.Line = l.ID
	m.Role = roleOf(m.Role, m.Blocks)
	id := f.n.node(f.session.SessionID, parent, key, f.n.item([]byte(l.Line)), f.stamp(l), m)
	f.last = id
	if m.Output && m.CallID != "" {
		c := f.calls[m.CallID]
		if c == nil {
			c = &Call{CallID: m.CallID, SessionID: f.session.SessionID, Origin: "transcript",
				Client: f.session.Client, SourceFormat: m.Format, Model: m.Model, InputID: parent,
				StartedAt: f.stamp(l), RequestParts: []requestitems.Part{}, OutputIDs: []Hash{}}
			f.calls[m.CallID] = c
			f.order = append(f.order, m.CallID)
		}
		c.OutputIDs = append(c.OutputIDs, id)
		c.CompletedAt = f.stamp(l)
		c.Model = firstNonEmpty(c.Model, m.Model)
	}
	return id
}

// treeParent finds the nearest ancestor entry that is a message, skipping
// entries such as Pi model changes or Claude Code compaction boundaries.
func (f *file) treeParent(parent string) Hash {
	for seen := 0; parent != "" && seen < 1<<20; seen++ {
		if id, ok := f.nodes[parent]; ok {
			return id
		}
		parent = f.parents[parent]
	}
	return Hash{}
}

func (f *file) setUsage(callID, responseID string, u usage) {
	if c := f.calls[callID]; c != nil {
		u.apply(c)
		c.ResponseID = firstNonEmpty(responseID, c.ResponseID)
	}
}

func (f *file) claudeCode(lines []TranscriptLine) {
	for _, l := range lines {
		e := parse([]byte(l.Line))
		t := e.str("type")
		uuid := e.str("uuid")
		if uuid != "" {
			f.parents[uuid] = e.str("parentUuid")
		}
		if t == "ai-title" {
			f.session.Title = firstNonEmpty(e.str("aiTitle"), e.str("title"), f.session.Title)
		}
		if f.session.Cwd == "" {
			f.session.Cwd = e.str("cwd")
		}
		m := Message{Format: "claude-code"}
		switch {
		case f.proxied || uuid == "":
		case t == "user" || t == "assistant":
			msg := e.obj("message")
			m.Role, m.Blocks = msg.str("role"), anthropicContent(msg["content"])
			if e.boolean("isCompactSummary") {
				for i := range m.Blocks {
					if m.Blocks[i].Type == "text" {
						m.Blocks[i].Type = "compaction"
					}
				}
			}
			if t == "assistant" {
				m.Output, m.Model = true, msg.str("model")
				m.CallID = firstNonEmpty(e.str("requestId"), msg.str("id"), uuid)
			}
		case t == "attachment":
			// Attachments such as instructions, reminders, and hook output
			// are rendered into the context the model sees; the others, such
			// as tool records, stay events.
			kind := "attachment:" + e.obj("attachment").str("type")
			for _, r := range e.arr("rendered") {
				if text := parse(r).str("content"); text != "" {
					m.Blocks = append(m.Blocks, Block{Type: "text", SourceType: kind, Text: text})
				}
			}
			if len(m.Blocks) > 0 {
				m.Role = firstNonEmpty(e.str("renderedRole"), "user")
			}
		}
		if m.Role == "" {
			f.event(l, t)
			continue
		}
		f.nodes[uuid] = f.message(l, f.treeParent(e.str("parentUuid")), uuid, m)
		if m.Output {
			// Each streamed block is a line; the last one carries final usage.
			msg := e.obj("message")
			f.setUsage(m.CallID, msg.str("id"), anthropicUsage(msg.obj("usage")))
		}
	}
}

func (f *file) codex(lines []TranscriptLine) {
	model, call, lastWasOutput := "", "", false
	for _, l := range lines {
		e := parse([]byte(l.Line))
		t, p := e.str("type"), e.obj("payload")
		switch {
		case t == "turn_context":
			model = firstNonEmpty(p.str("model"), model)
		case f.proxied:
		case t == "compacted":
			// The replacement history is the context from here on: a new
			// root, built from the items inside this line.
			f.event(l, t)
			parent := Hash{}
			for i, raw := range p.arr("replacement_history") {
				role, blocks := responsesItem(raw)
				parent = f.n.node(f.session.SessionID, parent, l.ID+"#"+strconv.Itoa(i), f.n.item(raw), f.stamp(l),
					Message{Role: roleOf(role, blocks), Blocks: blocks, Format: "openai-responses", Line: l.ID})
			}
			f.last, lastWasOutput = parent, false
			continue
		case t == "response_item":
			role, blocks := responsesItem(e["payload"])
			m := Message{Role: role, Blocks: blocks, Format: "codex"}
			if role == "assistant" {
				if !lastWasOutput {
					call = f.session.SessionID + ":" + l.ID
				}
				m.Output, m.Model, m.CallID = true, model, call
			}
			lastWasOutput = m.Output
			f.message(l, f.last, l.ID, m)
			continue
		case t == "token_usage_record":
			u := p.obj("usage")
			f.setUsage(call, p.str("response_id"), codexUsage(u))
		case t == "event_msg" && p.str("type") == "token_count":
			// Older logs only have the last call's counters.
			if c := f.calls[call]; c != nil && c.ResponseID == "" && c.OutputTokens == 0 {
				f.setUsage(call, "", codexUsage(p.obj("info").obj("last_token_usage")))
			}
		}
		kind := t
		if sub := p.str("type"); sub != "" {
			kind += ":" + sub
		}
		f.event(l, kind)
	}
}

func codexUsage(u obj) usage {
	input, read := u.num("input_tokens"), u.num("cached_input_tokens")
	write := u.num("cache_write_input_tokens")
	return usage{uncached: input - min(input, read+write), read: read, write: write,
		output: u.num("output_tokens"), reasoning: u.num("reasoning_output_tokens")}
}

func (f *file) pi(lines []TranscriptLine) {
	for _, l := range lines {
		e := parse([]byte(l.Line))
		t, id := e.str("type"), e.str("id")
		if id != "" {
			f.parents[id] = e.str("parentId")
		}
		switch t {
		case "session":
			f.session.Cwd = e.str("cwd")
		case "session_info":
			f.session.Title = firstNonEmpty(e.str("name"), f.session.Title)
		}
		m := Message{Format: "pi"}
		switch {
		case f.proxied || id == "":
		case t == "message":
			msg := e.obj("message")
			m.Role, m.Blocks = piMessage(msg)
			if m.Role == "assistant" {
				m.Output, m.Model = true, msg.str("model")
				m.CallID = firstNonEmpty(msg.str("responseId"), id)
			}
		case t == "compaction" || t == "branch_summary":
			// Pi sends the summary in place of the entries it replaces.
			m.Role = "user"
			m.Blocks = []Block{{Type: "compaction", SourceType: t, Text: e.str("summary")}}
		}
		if m.Role == "" {
			f.event(l, t)
			continue
		}
		f.nodes[id] = f.message(l, f.treeParent(e.str("parentId")), id, m)
		if m.Output {
			u := e.obj("message").obj("usage")
			f.setUsage(m.CallID, e.obj("message").str("responseId"), usage{uncached: u.num("input"),
				read: u.num("cacheRead"), write: u.num("cacheWrite"), output: u.num("output"), reasoning: u.num("reasoning")})
		}
	}
}

// opencode handles both exports: messages with inline content, and older
// messages whose parts are separate records. Records sort by kind and ID in
// the table, so messages are ordered by time here.
func (f *file) opencode(lines []TranscriptLine) {
	parts := map[string][]json.RawMessage{}
	var messages []TranscriptLine
	for _, l := range lines {
		e := parse([]byte(l.Line))
		switch e.str("kind") {
		case "part":
			parts[e.str("message_id")] = append(parts[e.str("message_id")], e["data"])
			f.event(l, "part")
		case "message":
			messages = append(messages, l)
		default:
			if e.str("kind") == "session" {
				f.session.Title, f.session.Cwd = e.str("title"), e.str("directory")
			}
			f.event(l, e.str("kind"))
		}
	}
	sort.SliceStable(messages, func(i, j int) bool {
		a, b := parse([]byte(messages[i].Line)), parse([]byte(messages[j].Line))
		return a.str("timestamp")+a.str("id") < b.str("timestamp")+b.str("id")
	})
	for _, l := range messages {
		e := parse([]byte(l.Line))
		d := e.obj("data")
		m := Message{Format: "opencode", Role: firstNonEmpty(d.str("role"), e.str("type"))}
		switch m.Role {
		case "user", "system", "synthetic":
			if s := d.str("text"); s != "" {
				m.Blocks = append(m.Blocks, Block{Type: "text", SourceType: m.Role, Text: s})
			}
			if m.Role == "synthetic" {
				m.Role = "user"
			}
		case "assistant":
			m.Output = true
			model := d.obj("model")
			m.Model = firstNonEmpty(d.str("modelID"), model.str("id"), model.str("modelID"))
			m.CallID = e.str("id")
		case "compaction":
			m.Role = "user"
			m.Blocks = []Block{{Type: "compaction", SourceType: "compaction", Text: d.str("summary")}}
		default:
			m.Role = ""
		}
		m.Blocks = append(m.Blocks, opencodeParts(append(d.arr("content"), parts[e.str("id")]...))...)
		if f.proxied || m.Role == "" {
			f.event(l, firstNonEmpty(e.str("type"), "message"))
			continue
		}
		f.message(l, f.last, e.str("id"), m)
		if m.Output {
			t := d.obj("tokens")
			cache := t.obj("cache")
			f.setUsage(m.CallID, "", usage{uncached: t.num("input"), read: cache.num("read"),
				write: cache.num("write"), output: t.num("output"), reasoning: t.num("reasoning")})
		}
	}
}
