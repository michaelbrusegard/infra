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
	// When the proxy's capture of this session starts, or empty.
	proxiedSince string
	ts           string
	// Entry IDs to their parent entry, and entries that became messages, for
	// sources that record a tree.
	parents map[string]string
	nodes   map[string]Hash
	// Pi entries that became messages, for the context after a compaction.
	kept  map[string]keptMessage
	last  Hash
	calls map[string]*Call
	order []string
}

type keptMessage struct {
	m    Message
	item Hash
}

// Proxied is what the proxy captured, for handing sessions over from
// transcripts: when each session's first proxied call started, each
// session's client and parent session, and the session of each response the
// proxy returned.
type Proxied struct {
	since    map[string]string
	clients  map[string]string
	parents  map[string]string
	sessions map[string]string
}

// Add records a proxy call and its session's client and parent session.
func (p *Proxied) Add(session, parent, client, responseID, startedAt string) {
	if p.since == nil {
		p.since, p.clients, p.parents, p.sessions = map[string]string{}, map[string]string{}, map[string]string{}, map[string]string{}
	}
	if s, ok := p.since[session]; !ok || startedAt < s {
		p.since[session] = startedAt
	}
	p.clients[session], p.parents[session] = client, parent
	if responseID != "" {
		p.sessions[responseID] = session
	}
}

// sessionOf returns the proxy session a transcript shares by its replies,
// or else the transcript's own. Sessionless clients such as Pi get a
// session from CLIProxy that the transcript cannot derive, so shared replies
// decide, but only when every one of them was returned in the same session,
// of the same client and parent. A sub-agent's file can hold a copy of its
// parent's reply, so a reply alone does not make a session the same.
func (p *Proxied) sessionOf(s Session, lines []TranscriptLine) string {
	shared := ""
	for _, l := range lines {
		switch session, ok := p.sessions[replyID(l)]; {
		case !ok:
		case shared == "":
			shared = session
		case session != shared:
			return s.SessionID
		}
	}
	if shared == "" || p.clients[shared] != s.Client || p.parents[shared] != s.ParentSessionID {
		return s.SessionID
	}
	return shared
}

// Transcript normalizes the lines of one transcript file, in file order.
// Every line becomes exactly one message or event that references the line
// verbatim. A transcript and the proxy share a session when they share
// their replies, by response ID (see sessionOf), or else when their session
// IDs match. From the session's first proxied call on, the proxy owns its
// messages and calls, and its transcript lines are kept as events only.
// Everything before, which the proxy never saw, keeps its messages and calls
// here, so nothing is counted twice and no history is lost.
//
// A reply that the proxy returned, or that an earlier file already made a
// call, is a copy, such as the parent's reply a forked sub-agent starts
// from: it stays in this file's tree as context sent to the model, with no
// call of its own. Files must arrive in path order, which puts a Claude Code
// session before its sub-agents, and a Codex rollout before those it spawns.
func (n *Normalizer) Transcript(lines []TranscriptLine, proxied *Proxied) {
	if len(lines) == 0 {
		return
	}
	f := &file{n: n, parents: map[string]string{}, nodes: map[string]Hash{}, calls: map[string]*Call{},
		kept: map[string]keptMessage{}}
	f.session = transcriptSession(lines)
	if proxied != nil {
		f.session.SessionID = proxied.sessionOf(f.session, lines)
		f.proxiedSince = proxied.since[f.session.SessionID]
	}
	start := len(n.Messages)
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
		c := f.calls[id]
		if _, returned := proxied.returned(c.ResponseID); returned || n.called[c.ResponseID] {
			n.copied(n.Messages[start:], c.CallID)
			continue
		}
		if c.ResponseID != "" {
			n.called[c.ResponseID] = true
		}
		n.Calls = append(n.Calls, *c)
	}
}

// returned reports whether the proxy returned a response, and in which
// session.
func (p *Proxied) returned(responseID string) (string, bool) {
	if p == nil || responseID == "" {
		return "", false
	}
	s, ok := p.sessions[responseID]
	return s, ok
}

// copied turns the outputs of a call that another source owns into context
// sent to the model, as Pi's compaction copies are.
func (n *Normalizer) copied(messages []Message, callID string) {
	for i := range messages {
		m := &messages[i]
		if m.Output && m.CallID == callID {
			m.Output, m.Model, m.CallID, m.Version = false, "", "", version(false, m.TS)
			n.nodes[m.ID] = node{m.Seq, m.Version}
		}
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

// replyID reads the response ID a transcript line records for a model
// reply, which the proxy's call for the reply has too. OpenCode records
// none.
func replyID(l TranscriptLine) string {
	e := parse([]byte(l.Line))
	switch {
	case l.Source == "claude-code" && e.str("type") == "assistant":
		return e.obj("message").str("id")
	case l.Source == "codex" && e.str("type") == "token_usage_record":
		return e.obj("payload").str("response_id")
	case l.Source == "pi" && e.str("type") == "message":
		return e.obj("message").str("responseId")
	}
	return ""
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

// owned reports whether a line falls before the proxy's capture, so its
// message is this transcript's to write.
func (f *file) owned(l TranscriptLine) bool {
	return f.proxiedSince == "" || f.stamp(l) < f.proxiedSince
}

func (f *file) event(l TranscriptLine, kind string) {
	f.n.Events = append(f.n.Events, Event{SessionID: f.session.SessionID, TS: f.stamp(l), Line: l.ID,
		Type: kind, Item: f.n.item([]byte(l.Line))})
}

// message adds a line as a message under parent, keyed by its entry ID,
// and reports whether it did. An entry the source wrote again, as Claude
// Code does when it resumes a session, keeps its first line as the message,
// and the repeat is kept as an event.
func (f *file) message(l TranscriptLine, parent Hash, key string, m Message) (Hash, bool) {
	m.Line = l.ID
	m.Role = roleOf(m.Role, m.Blocks)
	id, added := f.n.node(f.session.SessionID, parent, key, f.n.item([]byte(l.Line)), f.stamp(l), m, false)
	f.last = id
	if !added {
		f.event(l, "repeat")
		return id, false
	}
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
	return id, true
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
		case uuid == "" || !f.owned(l):
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
		id, added := f.message(l, f.treeParent(e.str("parentUuid")), uuid, m)
		f.nodes[uuid] = id
		if added && m.Output {
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
		case !f.owned(l):
		case t == "compacted":
			// The replacement history is the context from here on: a new
			// root, built from the items inside this line.
			f.event(l, t)
			parent := Hash{}
			for i, raw := range p.arr("replacement_history") {
				role, blocks := responsesItem(raw)
				parent, _ = f.n.node(f.session.SessionID, parent, l.ID+"#"+strconv.Itoa(i), f.n.item(raw), f.stamp(l),
					Message{Role: roleOf(role, blocks), Blocks: blocks, Format: "openai-responses", Line: l.ID}, false)
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
		case id == "" || !f.owned(l):
		case t == "message":
			msg := e.obj("message")
			m.Role, m.Blocks = piMessage(msg)
			if m.Role == "assistant" {
				m.Output, m.Model = true, msg.str("model")
				m.CallID = firstNonEmpty(msg.str("responseId"), id)
			}
		case t == "compaction" || t == "branch_summary":
			m.Role = "user"
			m.Blocks = []Block{{Type: "compaction", SourceType: t, Text: e.str("summary")}}
		}
		if m.Role == "" {
			f.event(l, t)
			continue
		}
		if t == "compaction" {
			f.nodes[id] = f.piCompaction(l, e, m)
			continue
		}
		var added bool
		f.nodes[id], added = f.message(l, f.treeParent(e.str("parentId")), id, m)
		if added {
			f.kept[id] = keptMessage{f.n.Messages[len(f.n.Messages)-1], f.n.item([]byte(l.Line))}
		}
		if added && m.Output {
			u := e.obj("message").obj("usage")
			f.setUsage(m.CallID, e.obj("message").str("responseId"), usage{uncached: u.num("input"),
				read: u.num("cacheRead"), write: u.num("cacheWrite"), output: u.num("output"), reasoning: u.num("reasoning")})
		}
	}
}

// piCompaction builds the context Pi sends after a compaction: the summary,
// then the entries from firstKeptEntryId to the compaction. The summary
// starts a new root, the kept entries are copied under it as context the
// model was sent again, and the original branch stays as it was. It
// returns the node later entries continue from.
func (f *file) piCompaction(l TranscriptLine, e obj, m Message) Hash {
	leaf, added := f.message(l, Hash{}, e.str("id"), m)
	if !added {
		return leaf
	}
	var tail []string
	first := e.str("firstKeptEntryId")
	for id, seen := e.str("parentId"), 0; id != "" && first != "" && seen < 1<<20; id, seen = f.parents[id], seen+1 {
		tail = append(tail, id)
		if id == first {
			break
		}
	}
	if len(tail) == 0 || tail[len(tail)-1] != first {
		return leaf
	}
	for i := len(tail) - 1; i >= 0; i-- {
		k, ok := f.kept[tail[i]]
		if !ok {
			continue
		}
		c := k.m
		c.Output, c.Model, c.CallID, c.Line = false, "", "", l.ID+"#"+tail[i]
		leaf, _ = f.n.node(f.session.SessionID, leaf, c.Line, k.item, f.stamp(l), c, false)
	}
	return leaf
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
		if !f.owned(l) || m.Role == "" {
			f.event(l, firstNonEmpty(e.str("type"), "message"))
			continue
		}
		if _, added := f.message(l, f.last, e.str("id"), m); added && m.Output {
			t := d.obj("tokens")
			cache := t.obj("cache")
			f.setUsage(m.CallID, "", usage{uncached: t.num("input"), read: cache.num("read"),
				write: cache.num("write"), output: t.num("output"), reasoning: t.num("reasoning")})
		}
	}
}
