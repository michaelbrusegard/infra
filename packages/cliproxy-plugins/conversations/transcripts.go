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
	// The file's fileKey.
	key string
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
	// The provider's ID of each Codex call's first output item; see itemKey.
	items map[string]string
	// The usage point of each Codex call that a token count gives its
	// usage; see codexCounts.
	counts map[string]string
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

// Replies records which transcript file holds the call of each reply that
// files record, by response ID, or for Codex by the provider's ID of the
// reply's first output item (see itemKey) and the point of an older log's
// token count (see codexCounts). A Codex file that records a call's usage
// holds it over copies that do not, since only the file that made the call
// writes its usage record, and a copy holding it would lose
// its usage and response ID. Within a lineage of sessions, recorded by each
// file's parent session, an ancestor's file holds it over its sub-agents' and
// forks', since they copy the replies they start from, even when clocks or
// timestamps of equal precision say otherwise. Otherwise the file whose
// line recording it is earliest holds it, then the first by host, path,
// and session. Copies that tie, such as sibling forks holding a reply
// neither wrote, or one file synced to two hosts, fall to the first.
//
// Only lines from before the proxy took a file's session over count, since
// a file writes no call after that, so a reply the proxy never returned
// stays with a file that can write it. Every file is added before any is
// normalized, so which file holds a call depends on all of them, never on
// which run together or in what order.
type Replies struct {
	// Response IDs and item keys to the lines recording them.
	seen map[string][]sighting
	// Sessions to their parent session, as files record them.
	parents map[string]string
	// Item keys of Codex calls to their response ID. Codex records it after
	// the call's items, and copies of the items in other files lack it.
	responses map[string]string
	// Item keys that files map to more than one response ID, to those IDs.
	// Their calls are distinct, so each is matched by its own response ID.
	conflicts map[string]map[string]bool
	// Response IDs to the file holding the call, once every file is added.
	owners map[string]string
}

type sighting struct {
	ts, file, session string
	// Whether the file records the call's usage.
	recorded bool
}

// Add records the replies of one file, with the proxied calls that
// Transcript is given.
func (r *Replies) Add(lines []TranscriptLine, proxied *Proxied) {
	if len(lines) == 0 {
		return
	}
	if r.seen == nil {
		r.seen, r.parents, r.responses = map[string][]sighting{}, map[string]string{}, map[string]string{}
		r.conflicts = map[string]map[string]bool{}
	}
	r.owners = nil
	f := newFile(nil, lines, proxied)
	recorded, counts := map[string]bool{}, map[string]string{}
	if lines[0].Source == "codex" {
		recorded, counts = r.codexResponses(lines)
	}
	// Copies of a session agree on its parent; the smaller one keeps the
	// result independent of order if they do not.
	if p, ok := r.parents[f.session.SessionID]; !ok || f.session.ParentSessionID < p {
		r.parents[f.session.SessionID] = f.session.ParentSessionID
	}
	for _, l := range lines {
		owned := f.owned(l)
		for _, id := range []string{replyID(l), itemKey(l), counts[l.ID]} {
			if id == "" || !owned {
				continue
			}
			// Claude Code writes a line per streamed block of a reply; the
			// file's earliest counts.
			s := sighting{f.stamp(l), f.key, f.session.SessionID, id == replyID(l) || recorded[id]}
			if seen := r.seen[id]; len(seen) > 0 && seen[len(seen)-1].file == f.key {
				seen[len(seen)-1].ts = min(seen[len(seen)-1].ts, s.ts)
				continue
			}
			r.seen[id] = append(r.seen[id], s)
		}
	}
}

// codexResponses records the response ID of each Codex call by its item
// key, grouping items into calls as Transcript does, and returns the item
// keys of the calls whose usage the file records, which include the keys of
// its token counts, and those keys by line.
func (r *Replies) codexResponses(lines []TranscriptLine) (map[string]bool, map[string]string) {
	recorded, counted := map[string]bool{}, map[string]string{}
	key, output := "", false
	// Whether the call has a usage record yet, and its response ID.
	used, response := false, ""
	counts := codexCounts{points: map[uint64]bool{}}
	for _, l := range lines {
		e := parse([]byte(l.Line))
		count := counts.key(e)
		if count != "" {
			recorded[count], counted[l.ID] = true, count
		}
		switch e.str("type") {
		case "response_item":
			role, _ := responsesItem(e["payload"])
			if role == "assistant" && !output {
				used, response = false, ""
			}
			if role == "assistant" && (!output || key == "") {
				key = itemKey(l)
			}
			output = role == "assistant"
		case "compacted":
			output = false
		case "token_usage_record":
			id := e.obj("payload").str("response_id")
			output = false
			if used && id != response {
				// A response without items of its own; see file.codex.
				continue
			}
			used, response = true, firstNonEmpty(id, response)
			if id != "" && key != "" {
				if old, ok := r.responses[key]; ok && old != id {
					if r.conflicts[key] == nil {
						r.conflicts[key] = map[string]bool{}
					}
					r.conflicts[key][old], r.conflicts[key][id] = true, true
				}
				r.responses[key] = id
			}
			recorded[key] = true
		case "event_msg":
			if count == "" {
				continue
			}
			output = false
			if used {
				// A response without items of its own; see file.codex.
				continue
			}
			used = true
			recorded[key] = true
		}
	}
	return recorded, counted
}

// codexCounts follows the token counts of a Codex file. Older logs only
// have token counts: the last response's usage, at a cumulative point.
// Codex repeats a point it reported, even within the next response, and a
// repeat is no call's usage. Newer logs repeat each usage record in a
// count, at a point that drifts from the record's after a compaction, so
// there the records alone are the usage.
type codexCounts struct {
	records bool
	// The thread of the last session_meta line. A sub-agent's file writes a
	// copy of its parent's before the history it copies from the parent.
	thread string
	points map[uint64]bool
}

// key returns the key of the usage point a line records, or "" if it
// records none: the thread and the point, as llm.historical_usage counts
// each once.
func (c *codexCounts) key(e obj) string {
	p := e.obj("payload")
	switch e.str("type") {
	case "session_meta":
		c.thread = p.str("id")
	case "token_usage_record":
		c.records = true
	case "event_msg":
		point := p.obj("info").obj("total_token_usage").num("total_tokens")
		if p.str("type") != "token_count" || c.records || point == 0 || c.points[point] {
			return ""
		}
		c.points[point] = true
		return "count:" + c.thread + ":" + strconv.FormatUint(point, 10)
	}
	return ""
}

// response returns the response ID of a call by its item key, from any
// file that records it.
func (r *Replies) response(key string) string {
	if r == nil || key == "" || r.conflicts[key] != nil {
		return ""
	}
	return r.responses[key]
}

// Conflicts lists the item keys that files map to more than one response
// ID, each with those IDs, for the collision audit. Their calls stay
// distinct, but a copy without a response ID cannot be matched to any of
// them, so it keeps a call of its own.
func (r *Replies) Conflicts() []string {
	var out []string
	for key, ids := range r.conflicts {
		line := []string{key}
		for id := range ids {
			line = append(line, id)
		}
		sort.Strings(line[1:])
		out = append(out, strings.Join(line, " "))
	}
	sort.Strings(out)
	return out
}

// elect decides the owner of every reply, as Replies describes. Each
// sighting ranks by whether its file records the call's usage, its
// lineage's earliest sighting and root, then its depth in the lineage, its
// time, and its file: a total order, so the owner never depends on the
// order files were added in.
func (r *Replies) elect() {
	r.owners = map[string]string{}
	type rank struct {
		copied      bool
		first, root string
		depth       int
		ts, file    string
	}
	less := func(a, b rank) bool {
		switch {
		case a.copied != b.copied:
			return !a.copied
		case a.first != b.first:
			return a.first < b.first
		case a.root != b.root:
			return a.root < b.root
		case a.depth != b.depth:
			return a.depth < b.depth
		case a.ts != b.ts:
			return a.ts < b.ts
		}
		return a.file < b.file
	}
	for id, seen := range r.seen {
		ranks := make([]rank, len(seen))
		first := map[string]string{}
		for i, s := range seen {
			root, depth := r.lineage(s.session)
			ranks[i] = rank{copied: !s.recorded, root: root, depth: depth, ts: s.ts, file: s.file}
			if t, ok := first[root]; !ok || s.ts < t {
				first[root] = s.ts
			}
		}
		best := rank{}
		for i, k := range ranks {
			k.first = first[k.root]
			if i == 0 || less(k, best) {
				best = k
			}
		}
		r.owners[id] = best.file
	}
}

// lineage returns the topmost known ancestor of a session, and how many
// parent sessions lead to it.
func (r *Replies) lineage(session string) (string, int) {
	depth := 0
	for ; depth < 64; depth++ {
		parent := r.parents[session]
		if parent == "" {
			break
		}
		session = parent
	}
	return session, depth
}

// owns reports whether a file, by its fileKey, holds the call of a reply,
// by its response ID or item key. A call with neither cannot be matched to
// a copy elsewhere, and nil Replies know no other files.
func (r *Replies) owns(file, reply string) bool {
	if r == nil || reply == "" {
		return true
	}
	if r.owners == nil {
		r.elect()
	}
	owner, ok := r.owners[reply]
	return !ok || owner == file
}

// fileKey identifies the file a transcript line comes from. One OpenCode
// database holds many sessions, so the session is part of it.
func fileKey(l TranscriptLine) string {
	return strings.Join([]string{l.Host, l.Path, l.Session}, "\x00")
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
// A reply that the proxy returned, or whose call replies gives another file,
// is a copy, such as the parent's reply a forked sub-agent starts from: it
// stays in this file's tree as context sent to the model, with no call of
// its own. Nodes are keyed by file, so a file's rows depend only on the
// file, replies, and proxied, and files can be normalized in any order and
// any runs.
func (n *Normalizer) Transcript(lines []TranscriptLine, replies *Replies, proxied *Proxied) {
	if len(lines) == 0 {
		return
	}
	f := newFile(n, lines, proxied)
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
		// A copy of a Codex reply lacks its response ID, which the file it
		// was copied from records. An item key of distinct responses
		// matches none of them. A sub-agent's copy can also lack the
		// first items of a reply, but not the token count of its usage.
		key := f.items[id]
		if replies != nil && replies.conflicts[key] != nil {
			key = ""
		}
		responseID := firstNonEmpty(c.ResponseID, replies.response(key))
		reply := firstNonEmpty(key, responseID)
		copied := !replies.owns(f.key, reply) || !replies.owns(f.key, f.counts[id])
		if _, returned := proxied.returned(responseID); returned || copied {
			n.copied(n.Messages[start:], c.CallID)
			continue
		}
		c.ResponseID = responseID
		n.Calls = append(n.Calls, *c)
	}
}

// newFile starts a transcript file: its session, and when the proxy took
// the session over, if it did.
func newFile(n *Normalizer, lines []TranscriptLine, proxied *Proxied) *file {
	f := &file{n: n, key: fileKey(lines[0]), parents: map[string]string{}, nodes: map[string]Hash{},
		calls: map[string]*Call{}, kept: map[string]keptMessage{}, items: map[string]string{}, counts: map[string]string{}}
	f.session = transcriptSession(lines)
	if proxied != nil {
		f.session.SessionID = proxied.sessionOf(f.session, lines)
		f.proxiedSince = proxied.since[f.session.SessionID]
	}
	return f
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

// itemKey reads the provider's ID of a Codex output item: a tool call's
// call ID, or else the item's own. Unlike response IDs, which older Codex
// logs lack, every Codex log records them, and a sub-agent's copy of its
// parent's history keeps them, so a Codex call is matched to its copies by
// its first output item's key. They should be unique to the call that
// produced the item; a key that files map to more than one response ID is
// a conflict, which Replies reports and never merges.
func itemKey(l TranscriptLine) string {
	e := parse([]byte(l.Line))
	if l.Source != "codex" || e.str("type") != "response_item" {
		return ""
	}
	if role, _ := responsesItem(e["payload"]); role != "assistant" {
		return ""
	}
	p := e.obj("payload")
	if id := firstNonEmpty(p.str("call_id"), p.str("id")); id != "" {
		return "item:" + id
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
	f.n.Events = append(f.n.Events, Event{SessionID: f.session.SessionID, TS: f.stamp(l), Host: l.Host,
		Path: l.Path, Line: l.ID, Type: kind, Item: f.n.item([]byte(l.Line))})
}

// message adds a line as a message under parent, keyed by its entry ID,
// and reports whether it did. An entry the source wrote again, as Claude
// Code does when it resumes a session, keeps its first line as the message,
// and the repeat is kept as an event.
func (f *file) message(l TranscriptLine, parent Hash, key string, m Message) (Hash, bool) {
	m.Line = l.ID
	m.Role = roleOf(m.Role, m.Blocks)
	id, added := f.node(parent, key, f.n.item([]byte(l.Line)), f.stamp(l), m)
	f.last = id
	if !added {
		f.event(l, "repeat")
		return id, false
	}
	if m.Output && m.CallID != "" {
		c := f.calls[m.CallID]
		if c == nil {
			c = f.call(m.CallID, m.Format, m.Model, parent, f.stamp(l))
		}
		c.OutputIDs = append(c.OutputIDs, id)
		c.CompletedAt = f.stamp(l)
		c.Model = firstNonEmpty(c.Model, m.Model)
	}
	return id, true
}

// call starts a call of this file, with no outputs yet.
func (f *file) call(callID, format, model string, input Hash, ts string) *Call {
	c := &Call{CallID: callID, SessionID: f.session.SessionID, Origin: "transcript", Client: f.session.Client,
		SourceFormat: format, Model: model, InputID: input, StartedAt: ts, CompletedAt: ts,
		RequestParts: []requestitems.Part{}, OutputIDs: []Hash{}}
	f.calls[callID] = c
	f.order = append(f.order, callID)
	return c
}

// node writes a message of this file, which records the file's host and
// path. Its key is the file's as well as the entry's, so a file that another
// shares a session with, such as a copy on another host, keeps its own
// nodes, and no file's rows depend on another's.
func (f *file) node(parent Hash, key string, item Hash, ts string, m Message) (Hash, bool) {
	m.Host, m.Path = f.session.Host, f.session.Path
	return f.n.node(f.session.SessionID, parent, f.key+"\x00"+key, item, ts, m, false)
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
	// The call whose usage record came last.
	recorded := ""
	counts := codexCounts{points: map[uint64]bool{}}
	for _, l := range lines {
		e := parse([]byte(l.Line))
		t, p := e.str("type"), e.obj("payload")
		count := counts.key(e)
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
				line := l.ID + "#" + strconv.Itoa(i)
				parent, _ = f.node(parent, line, f.n.item(raw), f.stamp(l),
					Message{Role: roleOf(role, blocks), Blocks: blocks, Format: "openai-responses", Line: line})
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
			if m.Output && f.items[call] == "" {
				f.items[call] = itemKey(l)
			}
			continue
		case t == "token_usage_record":
			// A response's usage record follows its items and ends it. A
			// second response with no output since, such as a remote
			// compaction's, has no items of its own, so it is a call
			// without outputs rather than the previous call's usage.
			if c := f.calls[call]; c != nil && call == recorded && p.str("response_id") != c.ResponseID {
				call = f.session.SessionID + ":" + l.ID
				f.call(call, "codex", model, f.last, f.stamp(l))
			}
			recorded, lastWasOutput = call, false
			f.setUsage(call, p.str("response_id"), codexUsage(p.obj("usage")))
		case count != "":
			// A token count's point, which codexCounts keeps once, is a
			// response's usage and ends it like a usage record. Without a
			// call to take it, it is a call without outputs. The point
			// matches the call to its copies: a sub-agent copies its
			// parent's counts but not every item they follow.
			if c := f.calls[call]; c == nil || call == recorded {
				call = f.session.SessionID + ":" + l.ID
				f.call(call, "codex", model, f.last, f.stamp(l))
			}
			recorded, lastWasOutput, f.counts[call] = call, false, count
			f.setUsage(call, "", codexUsage(p.obj("info").obj("last_token_usage")))
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
		leaf, _ = f.node(leaf, c.Line, k.item, f.stamp(l), c)
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
