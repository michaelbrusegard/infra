package conversations

import (
	"bytes"
	"encoding/json"
	"fmt"
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
	replies *Replies
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
	kept  map[string]Message
	last  Hash
	calls map[string]*Call
	order []string
	// The provider's ID of each Codex call's first output item; see itemKey.
	items map[string]string
	// The usage point of each Codex call that a token count gives its
	// usage; see codexCounts.
	counts map[string]string
	// Claude Code's request logs: the shapes, holding the system prompt and
	// tools, by hash, the shape of each request, and the request of each
	// call, by the requestRef of its replies.
	shapes   map[string]json.RawMessage
	requests map[string]string
	refs     map[string]string
	// The tool definitions Codex's additional_tools items add to the
	// context from where they appear, and those each call was sent with.
	tools     []json.RawMessage
	callTools map[string][]json.RawMessage
	// The system prompt an OpenCode call was sent with.
	callSystem map[string]json.RawMessage
	// Lines folded into calls, which count by what became of their call,
	// and those of them that take the next call the file starts.
	folds []fold
	next  []int
	// Lines after the proxy took the session over whose reply the proxy
	// returned; see owned.
	proxied map[string]bool
	// Lines from before the takeover whose reply the proxy returned, such
	// as the tools Codex adds just before the proxy's first call.
	toProxy map[string]bool
	// Claude Code's request logs as the file wrote them: each request's
	// line, its shapes' lines, and its message blobs by hash.
	requestLines []requestLine
	shapeLines   map[string][]TranscriptLine
	blobs        map[string]blob
	// The calls of requests no reply names: each request's messages, as
	// far as its blobs hold them, by position.
	requestMessages map[string][]requestMessage
	// The message lines the file keeps, which hold the messages of those
	// requests that are no blob.
	sent []sentLine
}

// fold is a line folded into a call: its usage, model, or context. What
// became of the call decides what became of the line: a call of this file
// holds it, the file holding a copied reply's call does, or the proxy.
type fold struct {
	l           TranscriptLine
	kind, field string
	// The call, or empty until the file starts its next call.
	call string
	// The items a context line holds, which the call of a copy's owner
	// must hold too.
	items []Hash
}

type requestLine struct {
	l                      TranscriptLine
	id, shape, base, model string
	keep                   int
	tail                   []string
	// The conversation as the file had it when the request was logged.
	input Hash
	ts    string
}

type blob struct {
	lines   []TranscriptLine
	message json.RawMessage
	// Held by the messages of a request no reply names.
	used bool
}

type requestMessage struct {
	position int
	raw      json.RawMessage
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
	// Claude Code's request logs over all files: the request each reply
	// names, by response ID, the shape of each request, and the shapes.
	// The file that holds a reply's call may lack the log another copy
	// has, as a parent's does when only its sub-agent's file logged it.
	refs     map[string]string
	requests map[string]string
	shapes   map[string]json.RawMessage
	// The reply naming each request, from any file.
	replies map[string]string
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
		r.refs, r.requests, r.shapes = map[string]string{}, map[string]string{}, map[string]json.RawMessage{}
		r.replies = map[string]string{}
	}
	r.owners = nil
	f := newFile(nil, lines, proxied)
	if lines[0].Source == "claude-code" {
		r.requestLogs(lines)
	}
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

// requestLogs records Claude Code's request logs of a file, for the call
// of each reply whichever file holds it.
func (r *Replies) requestLogs(lines []TranscriptLine) {
	for _, l := range lines {
		e := parse([]byte(l.Line))
		switch e.str("type") {
		case "api-request-shape":
			if _, ok := r.shapes[e.str("shapeHash")]; !ok {
				r.shapes[e.str("shapeHash")] = e["shape"]
			}
		case "api-request":
			r.requests[e.str("id")] = e.str("shapeHash")
		case "assistant":
			id, ref := e.obj("message").str("id"), e.str("requestRef")
			if _, ok := r.refs[id]; !ok && id != "" && ref != "" {
				r.refs[id] = ref
			}
			if _, ok := r.replies[ref]; !ok && ref != "" {
				r.replies[ref] = id
			}
		}
	}
}

// referenced returns the reply that names a request, in any file.
func (r *Replies) referenced(request string) (string, bool) {
	if r == nil {
		return "", false
	}
	reply, ok := r.replies[request]
	return reply, ok
}

// shape returns the shape of the request log of a reply, from any file.
func (r *Replies) shape(responseID string) json.RawMessage {
	if r == nil || responseID == "" {
		return nil
	}
	return r.shapes[r.requests[r.refs[responseID]]]
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
	counts := newCodexCounts(lines)
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
// repeat is no call's usage. Newer logs echo each usage record in a count,
// before or after it, at a point that drifts from the record's after a
// compaction, so a count whose usage a record of the file reports is that
// record's echo. A file can mix both, so any other count stays a response's
// usage.
type codexCounts struct {
	// The thread of the last session_meta line. A sub-agent's file writes a
	// copy of its parent's before the history it copies from the parent.
	thread string
	// The points already counted, by thread: threads report their own
	// cumulative totals, which can coincide.
	points map[string]bool
	// The usage records of the whole file not yet matched to an echo, by
	// input and output tokens.
	records map[[2]uint64]int
}

func newCodexCounts(lines []TranscriptLine) *codexCounts {
	c := &codexCounts{points: map[string]bool{}, records: map[[2]uint64]int{}}
	for _, l := range lines {
		if e := parse([]byte(l.Line)); e.str("type") == "token_usage_record" {
			u := e.obj("payload").obj("usage")
			c.records[[2]uint64{u.num("input_tokens"), u.num("output_tokens")}]++
		}
	}
	return c
}

// key returns the key of the usage point a line records, or "" if it
// records none: the thread and the point, as llm.historical_usage counts
// each once.
func (c *codexCounts) key(e obj) string {
	p := e.obj("payload")
	switch e.str("type") {
	case "session_meta":
		c.thread = p.str("id")
	case "event_msg":
		point := p.obj("info").obj("total_token_usage").num("total_tokens")
		if p.str("type") != "token_count" || point == 0 {
			return ""
		}
		key := "count:" + c.thread + ":" + strconv.FormatUint(point, 10)
		if c.points[key] {
			return ""
		}
		c.points[key] = true
		last := p.obj("info").obj("last_token_usage")
		if echo := [2]uint64{last.num("input_tokens"), last.num("output_tokens")}; c.records[echo] > 0 {
			c.records[echo]--
			return ""
		}
		return key
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
// Every line is counted once in Coverage, by what became of it. A transcript and the proxy share a session when they share
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
	f.replies = replies
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
			f.other(l, parse([]byte(l.Line)))
		}
	}
	n.session(f.session)
	// What became of each call: written here, copied from the file or
	// source that holds it, or the proxy's.
	fates := map[string]string{}
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
			fates[id] = "copy"
			if returned {
				fates[id] = "proxied"
			}
			continue
		}
		c.ResponseID = responseID
		c.Context = f.context(c.CallID, replies.shape(responseID))
		n.Calls = append(n.Calls, *c)
		fates[id] = "call"
		for _, p := range c.Context {
			n.held[p.Hash] = true
		}
	}
	f.requestLogs(replies, proxied, fates)
	for _, fd := range f.folds {
		f.settle(fd, fates[fd.call])
	}
}

// settle counts a folded line by what became of its call. A line no call
// took fails the import, except a line whose reply the proxy returned,
// whose call the proxy holds, and the turn settings of a turn that made no
// call, which hold nothing else the import keeps.
func (f *file) settle(fd fold, fate string) {
	if fate == "" && f.toProxy[fd.l.ID] {
		fate = "proxied"
	}
	switch {
	case fate == "" && fd.kind == "turn_context":
		f.count(fd.l.Source, fd.kind, "dropped", "")
	case fate == "":
		f.unknown("no call for " + fd.l.Source + "/" + fd.kind)
	case fate == "proxied":
		f.count(fd.l.Source, fd.kind, fate, "llm.calls")
	default:
		if fate == "copy" && len(fd.items) > 0 {
			f.n.copies = append(f.n.copies, held{fd.l.Source + "/" + fd.kind, fd.items})
		}
		f.count(fd.l.Source, fd.kind, fate, "llm.calls."+fd.field)
	}
}

// fold folds a line into a call, or with no call, into the next call the
// file starts.
func (f *file) fold(l TranscriptLine, e obj, field, call string, items []Hash) {
	f.folds = append(f.folds, fold{l: l, kind: kindOf(l.Source, e), field: field, call: call, items: items})
	if call == "" {
		f.next = append(f.next, len(f.folds)-1)
	}
}

// requestLogs accounts for Claude Code's request logs once every call's
// fate is known. A request a reply names is held by that reply's call,
// here, in the file holding a copied reply's call, or by the proxy. Its
// shape is held where any of its requests is, and its blobs are dropped
// unless a request no reply names holds them.
func (f *file) requestLogs(replies *Replies, proxied *Proxied, fates map[string]string) {
	calls := map[string]string{}
	for call, ref := range f.refs {
		calls[ref] = call
	}
	rank := map[string]int{"call": 3, "copy": 2, "proxied": 1}
	shapes := map[string]string{}
	for _, r := range f.requestLines {
		fate := fates[calls[r.id]]
		if fate == "" {
			fate = "copy"
			if reply, ok := replies.referenced(r.id); !ok {
				fate = fates[r.id]
			} else if _, returned := proxied.returned(reply); returned {
				fate = "proxied"
			}
		}
		f.settle(fold{l: r.l, kind: "api-request", field: "context", items: contextHashes(f.shapes[r.shape])}, fate)
		if rank[fate] > rank[shapes[r.shape]] {
			shapes[r.shape] = fate
		}
	}
	for shape, lines := range f.shapeLines {
		for _, l := range lines {
			f.settle(fold{l: l, kind: "api-request-shape", field: "context", items: contextHashes(f.shapes[shape])},
				shapes[shape])
		}
	}
	for _, b := range f.blobs {
		for _, l := range b.lines {
			if b.used {
				f.count(l.Source, "api-request-blob", "call", "llm.calls.context")
			} else {
				f.count(l.Source, "api-request-blob", "dropped", "")
			}
		}
	}
}

func firstRaw(values ...json.RawMessage) json.RawMessage {
	for _, v := range values {
		if len(v) > 0 {
			return v
		}
	}
	return nil
}

// held is the context of a folded line whose call another file holds, by
// its items, which CoverageError checks a written call holds.
type held struct {
	what  string
	items []Hash
}

// contextHashes returns the hashes of the items context stores of a
// request shape.
func contextHashes(shape json.RawMessage) []Hash {
	var out []Hash
	s := parse(shape)
	for _, field := range []string{"system", "tools"} {
		raw := bytes.TrimSpace(s[field])
		switch {
		case len(raw) == 0:
		case raw[0] != '[':
			out = append(out, itemHash(raw))
		default:
			for _, item := range array(raw) {
				out = append(out, itemHash(item))
			}
		}
	}
	return out
}

// newFile starts a transcript file: its session, and when the proxy took
// the session over, if it did.
func newFile(n *Normalizer, lines []TranscriptLine, proxied *Proxied) *file {
	f := &file{n: n, key: fileKey(lines[0]), parents: map[string]string{}, nodes: map[string]Hash{},
		calls: map[string]*Call{}, kept: map[string]Message{}, items: map[string]string{}, counts: map[string]string{},
		shapes: map[string]json.RawMessage{}, requests: map[string]string{}, refs: map[string]string{},
		callTools: map[string][]json.RawMessage{}, callSystem: map[string]json.RawMessage{}, proxied: map[string]bool{}, toProxy: map[string]bool{}, shapeLines: map[string][]TranscriptLine{},
		blobs: map[string]blob{}, requestMessages: map[string][]requestMessage{}}
	f.session = transcriptSession(lines)
	if proxied != nil {
		f.session.SessionID = proxied.sessionOf(f.session, lines)
		f.proxiedSince = proxied.since[f.session.SessionID]
	}
	if f.proxiedSince != "" {
		// A line from after the handover is the proxy's only when the reply
		// it leads to, its own or the next one the file records, is one
		// the proxy returned. Anything else, such as a turn the proxy never
		// saw or a prompt after the last reply, stays the file's.
		stamps := make([]string, len(lines))
		for i, l := range lines {
			stamps[i] = f.stamp(l)
		}
		f.ts = ""
		next := ""
		for i := len(lines) - 1; i >= 0; i-- {
			if id := replyID(lines[i]); id != "" {
				next = id
			}
			if _, returned := proxied.returned(next); returned && stamps[i] >= f.proxiedSince {
				f.proxied[lines[i].ID] = true
			} else if returned {
				f.toProxy[lines[i].ID] = true
			}
		}
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
		// A sub-agent's session record names the session that started it.
		for _, line := range lines {
			if e := parse([]byte(line.Line)); e.str("kind") == "session" && e.str("parent_id") != "" {
				s.ParentSessionID = "opencode:" + e.str("parent_id")
			}
		}
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

// owned reports whether a line is this transcript's to write: it falls
// before the proxy's capture of the session, or the proxy did not return
// the reply it leads to.
func (f *file) owned(l TranscriptLine) bool {
	f.stamp(l)
	return !f.proxied[l.ID]
}

// Covered is what became of transcript lines of a source and kind: a
// message, an event, folded into a call, a session, or the tree's structure,
// a repeat of an entry that is a message already, a line the proxy holds
// the call of, or dropped. llm.transcripts is dropped after the import, so
// every line must be one of these, and the dropped kinds are listed in
// docs/llm-conversations.md.
type Covered struct {
	Source, Kind, Disposition string
	// Where the line's content is now: a table, or a table and column for
	// lines folded into calls and sessions, empty for dropped lines.
	Destination string
}

// folded names what the lines of each kind that is no message are folded
// into. Lines of any other kind are dropped, unless they are events.
var folded = map[string]string{
	"claude-code/ai-title": "session", "claude-code/api-request": "call",
	"claude-code/api-request-shape": "call", "claude-code/system:compact_boundary": "structure",
	"codex/session_meta": "session", "codex/turn_context": "call", "codex/token_usage_record": "call",
	"codex/event_msg:token_count": "call", "codex/compacted": "structure", "codex/response_item:additional_tools": "call",
	"pi/session": "session", "pi/session_info": "session",
	"opencode/part": "structure", "opencode/session": "session",
}

// droppedKinds are the kinds whose lines the import drops, as listed in
// docs/llm-conversations.md: client state, progress, and copies of what
// other lines hold. A kind in none of folded, eventKinds, and droppedKinds
// is unknown, and fails the import rather than being dropped unseen.
var droppedKinds = map[string]bool{}

func init() {
	for source, kinds := range map[string][]string{
		"claude-code": {"api-request-blob", "attachment:deferred_tools_record", "last-prompt", "atis-latch",
			"queue-operation", "mode", "pr-link", "attachment:prompt_snapshot", "cost-state",
			"attachment:command_permissions", "result", "started", "attachment:thinking_drop",
			"attachment:structured_output", "attachment:session_context", "fork-context-ref", "system:informational",
			"launched", "permission-mode", "file-history-snapshot", "system:local_command", "attachment:credential_org",
			"system:turn_duration"},
		"codex": {"event_msg:item_completed", "event_msg:agent_message", "event_msg:mcp_tool_call_end",
			"event_msg:patch_apply_end", "event_msg:task_started", "event_msg:thread_settings_applied",
			"event_msg:task_complete", "event_msg:user_message", "event_msg:sub_agent_activity", "world_state",
			"event_msg:web_search_end", "inter_agent_communication_metadata", "event_msg:context_compacted"},
		"opencode": {"message:idle"},
		"pi":       {"thinking_level_change", "model_change", "context_edit"},
	} {
		for _, kind := range kinds {
			droppedKinds[source+"/"+kind] = true
		}
	}
}

// eventKinds names the kinds kept as events: how a session went, which no
// message or call records.
var eventKinds = map[string]string{
	"claude-code/system:api_error": "api_error", "claude-code/system:model_refusal_fallback": "model_refusal_fallback",
	"codex/event_msg:turn_aborted": "turn_aborted", "codex/event_msg:thread_rolled_back": "thread_rolled_back",
}

// kindOf names the kind of a transcript line, for coverage: its type, with
// the subtype that tells Claude Code system lines and attachments, Codex
// payloads, and OpenCode messages apart.
func kindOf(source string, e obj) string {
	switch source {
	case "claude-code":
		switch t := e.str("type"); t {
		case "system":
			return t + ":" + e.str("subtype")
		case "attachment":
			return t + ":" + e.obj("attachment").str("type")
		default:
			return t
		}
	case "codex":
		if sub := e.obj("payload").str("type"); sub != "" {
			return e.str("type") + ":" + sub
		}
	case "opencode":
		if k := e.str("kind"); k != "message" {
			return k
		}
		return "message:" + firstNonEmpty(e.obj("data").str("role"), e.str("type"))
	}
	return e.str("type")
}

// unknown records a kind of line or block the import does not know, which
// CoverageError reports: it would otherwise be dropped or kept as an
// empty other block without anyone deciding so.
func (n *Normalizer) unknown(what string) {
	if n.unknowns == nil {
		n.unknowns = map[string]int{}
	}
	n.unknowns[what]++
}

// unknown records what a file's import does not know, and the first file
// with it, for CoverageError to name.
func (f *file) unknown(what string) {
	f.n.unknown(what)
	if f.n.examples == nil {
		f.n.examples = map[string]string{}
	}
	if _, ok := f.n.examples[what]; !ok {
		f.n.examples[what] = f.session.Host + ":" + f.session.Path
	}
}

// CoverageError reports what the transcript import could not account for:
// kinds of line or block it does not know. The import must not be inserted
// with any, since llm.transcripts is dropped after it.
func (n *Normalizer) CoverageError() error {
	for _, c := range n.copies {
		for _, h := range c.items {
			if !n.held[h] {
				n.unknown("no written call holds the context of a copy's " + c.what)
				break
			}
		}
	}
	n.copies = nil
	if len(n.unknowns) == 0 {
		return nil
	}
	var list []string
	for what, lines := range n.unknowns {
		if example := n.examples[what]; example != "" {
			list = append(list, fmt.Sprintf("%s (%d, first in %s)", what, lines, example))
			continue
		}
		list = append(list, fmt.Sprintf("%s (%d)", what, lines))
	}
	sort.Strings(list)
	return fmt.Errorf("the transcript import does not know %s", strings.Join(list, ", "))
}

// cover counts a line by what became of it and where its content is now.
func (f *file) cover(l TranscriptLine, e obj, disposition, destination string) {
	f.count(l.Source, kindOf(l.Source, e), disposition, destination)
}

func (f *file) count(source, kind, disposition, destination string) {
	if f.n.Coverage == nil {
		f.n.Coverage = map[Covered]int{}
	}
	f.n.Coverage[Covered{source, kind, disposition, destination}]++
}

// other accounts for a line that is no message: an event, folded into a
// call, a session, or the tree's structure, or dropped. After the proxy
// took the session over, only what sessions keep counts; the proxy holds
// the rest.
func (f *file) other(l TranscriptLine, e obj) {
	key := l.Source + "/" + kindOf(l.Source, e)
	disposition := firstNonEmpty(folded[key], "dropped")
	kind, event := eventKinds[key]
	if event {
		disposition = "event"
	}
	switch {
	case !f.owned(l) && disposition != "session":
		disposition = "proxied"
	case disposition == "dropped" && !droppedKinds[key]:
		f.unknown("kind " + key)
	case disposition == "call":
		// Lines folded into calls count by what became of the call.
		f.unknown("no call for " + key)
	case event:
		f.n.Events = append(f.n.Events, Event{SessionID: f.session.SessionID, TS: f.stamp(l), Host: l.Host,
			Path: l.Path, Line: l.ID, Type: kind, Detail: eventDetail(kind, e)})
	}
	destination := destinations[disposition+"/"+key]
	if disposition == "proxied" {
		// The proxy's call of the reply the line leads to; see owned.
		destination = "llm.calls"
	}
	f.cover(l, e, disposition, destination)
}

// destinations name where the content of lines that are no message is: an
// event, a session, or the tree.
var destinations = map[string]string{}

func init() {
	for key, disposition := range folded {
		switch disposition {
		case "session":
			destinations["session/"+key] = "llm.sessions"
		case "structure":
			destinations["structure/"+key] = map[string]string{"claude-code/system:compact_boundary": "llm.messages.parent_id",
				"codex/compacted": "llm.messages.part", "opencode/part": "llm.messages.blocks"}[key]
		}
	}
	for key := range eventKinds {
		destinations["event/"+key] = "llm.events"
	}
}

// eventDetail reads what an event says: the error, the notice, why a turn
// stopped, or how many turns were rolled back.
func eventDetail(kind string, e obj) string {
	p := e.obj("payload")
	switch kind {
	case "api_error":
		return firstNonEmpty(e.obj("error").str("formatted"), e.obj("error").str("message"))
	case "model_refusal_fallback":
		return e.str("content")
	case "turn_aborted":
		return p.str("reason")
	case "thread_rolled_back":
		return strconv.FormatUint(p.num("num_turns"), 10)
	}
	return ""
}

// context stores the system prompt and tools of a call that its transcript
// records, as the archive splits request bodies: each array element is an
// item. Claude Code's request logs record both, in this file or, as shared
// for a reply that files copy, another; Codex's additional_tools items
// record the tools.
func (f *file) context(callID string, shared json.RawMessage) []requestitems.Part {
	parts := []requestitems.Part{}
	if system := f.callSystem[callID]; len(system) > 0 {
		parts = append(parts, requestitems.Part{Field: "system", Position: -1, Hash: f.n.item(system)})
	}
	for i, tool := range f.callTools[callID] {
		parts = append(parts, requestitems.Part{Field: "tools", Position: int32(i), Hash: f.n.item(tool)})
	}
	raw, ok := f.shapes[f.requests[f.refs[callID]]]
	if !ok {
		raw = shared
	}
	shape := parse(raw)
	for _, field := range []string{"system", "tools"} {
		raw := bytes.TrimSpace(shape[field])
		if len(raw) == 0 {
			continue
		}
		if raw[0] != '[' {
			parts = append(parts, requestitems.Part{Field: field, Position: -1, Hash: f.n.item(raw)})
			continue
		}
		for i, item := range array(raw) {
			parts = append(parts, requestitems.Part{Field: field, Position: int32(i), Hash: f.n.item(item)})
		}
	}
	for _, m := range f.requestMessages[callID] {
		parts = append(parts, requestitems.Part{Field: "messages", Position: int32(m.position), Hash: f.n.item(m.raw)})
	}
	return parts
}

// message adds a line as a message under parent, keyed by its entry ID,
// and reports whether it did. An entry the source wrote again, as Claude
// Code does when it resumes a session, keeps its first line as the message,
// and the repeat is counted as one.
func (f *file) message(l TranscriptLine, e obj, parent Hash, key string, m Message) (Hash, bool) {
	m.Line = l.ID
	m.Role = roleOf(m.Role, m.Blocks)
	id, added := f.node(parent, key, f.stamp(l), m)
	f.last = id
	if !added {
		f.cover(l, e, "repeat", "llm.messages")
		return id, false
	}
	f.cover(l, e, "message", "llm.messages")
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
		Host: f.session.Host, Path: f.session.Path, SourceFormat: format, Model: model, InputID: input,
		StartedAt: ts, CompletedAt: ts, OutputIDs: []Hash{}}
	f.calls[callID] = c
	f.order = append(f.order, callID)
	if len(f.tools) > 0 {
		f.callTools[callID] = f.tools[:len(f.tools):len(f.tools)]
	}
	for _, i := range f.next {
		f.folds[i].call = callID
	}
	f.next = nil
	return c
}

// node writes a message of this file, which records the file's host and
// path. Its key is the file's as well as the entry's, so a file that another
// shares a session with, such as a copy on another host, keeps its own
// nodes, and no file's rows depend on another's.
func (f *file) node(parent Hash, key string, ts string, m Message) (Hash, bool) {
	for _, b := range m.Blocks {
		if b.Type == "other" {
			f.unknown(f.session.Client + " " + m.Format + " block " + b.SourceType)
		}
	}
	m.Host, m.Path = f.session.Host, f.session.Path
	return f.n.node(f.session.SessionID, parent, f.key+"\x00"+key, ts, m, false)
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
		switch t {
		case "api-request-shape":
			f.shapes[e.str("shapeHash")] = e["shape"]
		case "api-request":
			f.requests[e.str("id")] = e.str("shapeHash")
		}
		if f.owned(l) {
			// Request logs count once every call's fate is known; see
			// requestLogs.
			switch t {
			case "api-request-shape":
				f.shapeLines[e.str("shapeHash")] = append(f.shapeLines[e.str("shapeHash")], l)
				continue
			case "api-request":
				var tail []string
				json.Unmarshal(e["tail"], &tail)
				f.requestLines = append(f.requestLines, requestLine{l: l, id: e.str("id"), shape: e.str("shapeHash"),
					base: e.str("base"), model: e.obj("params").str("model"), keep: int(e.num("keep")), tail: tail,
					input: f.last, ts: f.stamp(l)})
				continue
			case "api-request-blob":
				b := f.blobs[e.str("hash")]
				b.lines = append(b.lines, l)
				b.message = firstRaw(b.message, e["message"])
				f.blobs[e.str("hash")] = b
				continue
			}
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
			f.other(l, e)
			continue
		}
		id, added := f.message(l, e, f.treeParent(e.str("parentUuid")), uuid, m)
		f.nodes[uuid] = id
		if added && (t == "user" || t == "assistant") {
			msg := e.obj("message")
			f.sent = append(f.sent, sentLine{role: msg.str("role"), content: msg["content"], reply: msg.str("id")})
		}
		if added && m.Output {
			// The call's request log, from Claude Code 2.1 on.
			if f.refs[m.CallID] == "" {
				f.refs[m.CallID] = e.str("requestRef")
			}
			// Each streamed block is a line; the last one carries final usage.
			msg := e.obj("message")
			f.setUsage(m.CallID, msg.str("id"), anthropicUsage(msg.obj("usage")))
		}
	}
	f.unansweredRequests()
}

// unansweredRequests keeps the requests no reply names, in any file, such
// as ones that failed or were interrupted: no other row would hold what
// they sent. Each is a call without outputs, whose input is the
// conversation as the file had it when the request was logged, and whose
// context holds its system prompt, tools, and the messages it sent that
// Claude Code logged as blobs. Every other message it sent must be one of
// the file's message lines, which are messages (see sentMessages); a
// message neither holds, or a base request the file lacks, fails the
// import.
func (f *file) unansweredRequests() {
	named := map[string]bool{}
	for _, ref := range f.refs {
		named[ref] = true
	}
	byID := map[string]requestLine{}
	for _, r := range f.requestLines {
		byID[r.id] = r
	}
	// The messages of a request, from its base's first keep, or false
	// when the file lacks a base or holds fewer.
	var messages func(id string, depth int) ([]string, bool)
	messages = func(id string, depth int) ([]string, bool) {
		r, ok := byID[id]
		if !ok || depth > 1<<12 {
			return nil, false
		}
		var out []string
		if r.base != "" {
			base, ok := messages(r.base, depth+1)
			if !ok || len(base) < r.keep {
				return nil, false
			}
			out = append(out, base[:r.keep]...)
		}
		return append(out, r.tail...), true
	}
	var sent map[string]bool
	for _, r := range f.requestLines {
		if _, ok := f.replies.referenced(r.id); ok || named[r.id] {
			continue
		}
		if sent == nil {
			sent = sentMessages(f.sent)
		}
		hashes, ok := messages(r.id, 0)
		if !ok {
			f.unknown("base of claude-code/api-request " + r.id)
		}
		for i, hash := range hashes {
			if b, ok := f.blobs[hash]; ok {
				b.used = true
				f.blobs[hash] = b
				f.requestMessages[r.id] = append(f.requestMessages[r.id], requestMessage{i, b.message})
			} else if !sent[hash] {
				f.unknown("message " + hash + " of claude-code/api-request " + r.id)
			}
		}
		f.refs[r.id] = r.id
		f.call(r.id, "claude-code", r.model, r.input, r.ts)
	}
}

func (f *file) codex(lines []TranscriptLine) {
	model, call, lastWasOutput := "", "", false
	// The call whose usage record came last.
	recorded := ""
	counts := newCodexCounts(lines)
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
			f.other(l, e)
			parent := Hash{}
			f.tools = nil
			for i, raw := range p.arr("replacement_history") {
				if tools, ok := additionalTools(raw); ok {
					f.tools = append(f.tools, tools...)
					continue
				}
				role, blocks := responsesItem(raw)
				index := strconv.Itoa(i)
				parent, _ = f.node(parent, l.ID+"#"+index, f.stamp(l), Message{Role: roleOf(role, blocks),
					Blocks: blocks, Format: "openai-responses", Line: l.ID, Part: index})
			}
			f.last, lastWasOutput = parent, false
			continue
		case t == "response_item" && p.str("type") == "additional_tools":
			// Tool definitions sent with every call from here on: per-call
			// context, as in a request, rather than a message.
			tools, _ := additionalTools(e["payload"])
			f.tools = append(f.tools, tools...)
			var items []Hash
			for _, tool := range tools {
				items = append(items, itemHash(tool))
			}
			f.fold(l, e, "context", "", items)
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
			f.message(l, e, f.last, l.ID, m)
			if m.Output && f.items[call] == "" {
				f.items[call] = itemKey(l)
			}
			continue
		case t == "token_usage_record":
			// A response's usage record follows its items and ends it. A
			// second response with no output since, such as a remote
			// compaction's, has no items of its own, so it is a call
			// without outputs rather than the previous call's usage, and so
			// is a record before any items.
			if c := f.calls[call]; c == nil || call == recorded && p.str("response_id") != c.ResponseID {
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
		switch {
		case !f.owned(l):
			f.other(l, e)
		case t == "turn_context":
			// The model of the calls from here on.
			f.fold(l, e, "model", "", nil)
		case t == "token_usage_record" || count != "":
			f.fold(l, e, "usage", call, nil)
		case t == "event_msg" && p.str("type") == "token_count":
			// A point counted already, a usage record's echo, or no usage.
			f.cover(l, e, "repeat", "llm.calls.usage")
		default:
			f.other(l, e)
		}
	}
}

// additionalTools reads the tool definitions of a Codex additional_tools
// item, which may hold namespaces of tools.
func additionalTools(raw json.RawMessage) ([]json.RawMessage, bool) {
	it := parse(raw)
	if it.str("type") != "additional_tools" {
		return nil, false
	}
	return it.arr("tools"), true
}

func codexUsage(u obj) usage {
	input, read := u.num("input_tokens"), u.num("cached_input_tokens")
	write := u.num("cache_write_input_tokens")
	return usage{uncached: input - min(input, read+write), read: read, write: write,
		output: u.num("output_tokens"), reasoning: u.num("reasoning_output_tokens")}
}

func (f *file) pi(lines []TranscriptLine) {
	// The model in use, which a compaction's summarization call ran with.
	model := ""
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
		case "model_change":
			model = firstNonEmpty(e.str("modelId"), model)
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
			f.other(l, e)
			continue
		}
		if t == "compaction" {
			// Pi summarizes the conversation with a call of the model in
			// use, which records the call's usage but no response ID. It is
			// a call without outputs, like a Codex remote compaction: its
			// input is what it summarized, and the summary is the root of
			// what Pi sends from then on.
			input := f.treeParent(e.str("parentId"))
			written := len(f.n.Messages)
			f.nodes[id] = f.piCompaction(l, e, m)
			if _, ok := e["usage"]; ok && len(f.n.Messages) > written {
				f.call(id, "pi", model, input, f.stamp(l))
				f.setUsage(id, "", piUsage(e.obj("usage")))
			}
			continue
		}
		var added bool
		f.nodes[id], added = f.message(l, e, f.treeParent(e.str("parentId")), id, m)
		if added {
			f.kept[id] = f.n.Messages[len(f.n.Messages)-1]
		}
		if added && m.Output {
			model = firstNonEmpty(m.Model, model)
			f.setUsage(m.CallID, e.obj("message").str("responseId"), piUsage(e.obj("message").obj("usage")))
		}
	}
}

func piUsage(u obj) usage {
	return usage{uncached: u.num("input"), read: u.num("cacheRead"), write: u.num("cacheWrite"),
		output: u.num("output"), reasoning: u.num("reasoning")}
}

// piCompaction builds the context Pi sends after a compaction: the summary,
// then the entries from firstKeptEntryId to the compaction. The summary
// starts a new root, the kept entries are copied under it as context the
// model was sent again, and the original branch stays as it was. It
// returns the node later entries continue from.
func (f *file) piCompaction(l TranscriptLine, e obj, m Message) Hash {
	leaf, added := f.message(l, e, Hash{}, e.str("id"), m)
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
		c, ok := f.kept[tail[i]]
		if !ok {
			continue
		}
		c.Output, c.Model, c.CallID, c.Line, c.Part = false, "", "", l.ID, tail[i]
		leaf, _ = f.node(leaf, l.ID+"#"+tail[i], f.stamp(l), c)
	}
	return leaf
}

// opencode handles both exports: messages with inline content, and older
// messages whose parts are separate records. Records sort by kind and ID in
// the table, so messages are ordered by time here.
func (f *file) opencode(lines []TranscriptLine) {
	parts := map[string][]json.RawMessage{}
	var messages, partLines []TranscriptLine
	for _, l := range lines {
		e := parse([]byte(l.Line))
		switch e.str("kind") {
		case "part":
			parts[e.str("message_id")] = append(parts[e.str("message_id")], e["data"])
			partLines = append(partLines, l)
		case "message":
			messages = append(messages, l)
		default:
			if e.str("kind") == "session" {
				f.session.Title, f.session.Cwd = e.str("title"), e.str("directory")
			}
			f.other(l, e)
		}
	}
	sort.SliceStable(messages, func(i, j int) bool {
		a, b := parse([]byte(messages[i].Line)), parse([]byte(messages[j].Line))
		return a.str("timestamp")+a.str("id") < b.str("timestamp")+b.str("id")
	})
	// The messages that hold their parts' content, or whose lines are the
	// proxy's.
	held := map[string]string{}
	// The system prompt OpenCode sends with a user message's turn.
	var system json.RawMessage
	for _, l := range messages {
		e := parse([]byte(l.Line))
		d := e.obj("data")
		m := Message{Format: "opencode", Role: firstNonEmpty(d.str("role"), e.str("type"))}
		if m.Role == "user" {
			system = d["system"]
		}
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
		if !f.owned(l) {
			held[e.str("id")] = "proxied"
		}
		if !f.owned(l) || m.Role == "" {
			f.other(l, e)
			continue
		}
		held[e.str("id")] = "structure"
		if _, added := f.message(l, e, f.last, e.str("id"), m); added && m.Output {
			f.setUsage(m.CallID, "", opencodeUsage(d.obj("tokens")))
			if len(system) > 0 {
				f.callSystem[m.CallID] = system
			}
		}
	}
	for _, l := range partLines {
		e := parse([]byte(l.Line))
		switch held[e.str("message_id")] {
		case "structure":
			f.cover(l, e, "structure", "llm.messages.blocks")
		case "proxied":
			f.cover(l, e, "proxied", "llm.calls")
		default:
			f.unknown("no message for opencode/part")
		}
	}
}

// opencodeUsage reads OpenCode's tokens the way the usage importer did.
// Current OpenCode counts reasoning apart from output; older records can
// include it, and only a recorded total that adds up without it tells them
// apart.
func opencodeUsage(t obj) usage {
	cache := t.obj("cache")
	u := usage{uncached: t.num("input"), read: cache.num("read"), write: cache.num("write"),
		output: t.num("output"), reasoning: t.num("reasoning")}
	if _, ok := t["total"]; !ok || t.num("total") != u.uncached+u.read+u.write+u.output {
		u.output += u.reasoning
	}
	return u
}
