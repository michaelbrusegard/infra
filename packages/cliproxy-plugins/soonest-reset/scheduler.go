package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"slices"
	"strconv"
	"sync"
	"time"

	"cliproxy-plugins/plugin"
)

// CLIProxyAPI skips its own session affinity when a scheduler plugin picks,
// so sessions are kept on one account here. This matches its default TTL.
const sessionTTL = time.Hour

type scheduler struct {
	mu sync.Mutex
	// When each account's longest quota window resets, learned from responses.
	resets   map[string]time.Time
	sessions map[string]binding
	swept    time.Time
}

type binding struct {
	authID string
	seen   time.Time
}

// Field names match CLIProxyAPI's pluginapi structs, which it encodes
// without JSON tags.
type pickRequest struct {
	Provider string
	Options  struct {
		Metadata map[string]any
	}
	// Accounts in cooldown or out of quota are already filtered out.
	Candidates []candidate
}

type candidate struct {
	ID string
}

type usageRecord struct {
	AuthID          string
	ResponseHeaders http.Header
}

func newScheduler() *scheduler {
	return &scheduler{
		resets:   map[string]time.Time{},
		sessions: map[string]binding{},
	}
}

func (s *scheduler) Handle(method string, raw []byte) ([]byte, bool) {
	switch method {
	case "plugin.register", "plugin.reconfigure":
		return plugin.Reply(plugin.Registration("soonest-reset", map[string]bool{
			"scheduler":    true,
			"usage_plugin": true,
		}))
	case "scheduler.pick":
		var r pickRequest
		if err := json.Unmarshal(raw, &r); err != nil {
			return plugin.Fail("invalid_request", err)
		}
		return plugin.Reply(s.pick(r, time.Now()))
	case "usage.handle":
		var r usageRecord
		if err := json.Unmarshal(raw, &r); err != nil {
			return plugin.Fail("invalid_request", err)
		}
		if reset, ok := longestWindowReset(r.ResponseHeaders); ok && r.AuthID != "" {
			s.mu.Lock()
			s.resets[r.AuthID] = reset
			s.mu.Unlock()
		}
	case "plugin.quiesce", "plugin.shutdown":
	default:
		return plugin.Fail("unknown_method", fmt.Errorf("unknown method %q", method))
	}
	return plugin.Reply(map[string]any{})
}

func (s *scheduler) Shutdown() {}

func (s *scheduler) pick(r pickRequest, now time.Time) map[string]any {
	if len(r.Candidates) < 2 {
		return map[string]any{"handled": false}
	}
	session, _ := r.Options.Metadata["canonical_session_id"].(string)
	key := r.Provider + "\x00" + session

	s.mu.Lock()
	defer s.mu.Unlock()
	if now.Sub(s.swept) > sessionTTL {
		for k, b := range s.sessions {
			if now.Sub(b.seen) > sessionTTL {
				delete(s.sessions, k)
			}
		}
		s.swept = now
	}

	// Moving a session to another account throws away its prompt cache.
	if b, ok := s.sessions[key]; ok && session != "" && now.Sub(b.seen) <= sessionTTL &&
		slices.ContainsFunc(r.Candidates, func(c candidate) bool { return c.ID == b.authID }) {
		s.sessions[key] = binding{b.authID, now}
		return map[string]any{"handled": true, "auth_id": b.authID}
	}

	// An account with no known upcoming reset goes first: it has not been
	// used yet, or its window already reset, and one response teaches us when
	// it resets next.
	best, bestReset := "", time.Time{}
	for _, c := range r.Candidates {
		reset := s.resets[c.ID]
		if !reset.After(now) {
			reset = time.Time{}
		}
		if best == "" || reset.Before(bestReset) {
			best, bestReset = c.ID, reset
		}
	}
	if session != "" {
		s.sessions[key] = binding{best, now}
	}
	return map[string]any{"handled": true, "auth_id": best}
}

// longestWindowReset returns when the account's longest quota window resets.
// Quota left in that window is what is lost at a reset.
func longestWindowReset(headers http.Header) (time.Time, bool) {
	h := http.Header{}
	for k, v := range headers {
		h[http.CanonicalHeaderKey(k)] = v
	}
	// Claude reports its weekly window directly.
	if reset, ok := unixTime(h.Get("Anthropic-Ratelimit-Unified-7d-Reset")); ok {
		return reset, true
	}
	// Codex reports two windows whose lengths depend on the plan.
	var best time.Time
	longest := 0
	for _, window := range []string{"Primary", "Secondary"} {
		minutes, err := strconv.Atoi(h.Get("X-Codex-" + window + "-Window-Minutes"))
		reset, ok := unixTime(h.Get("X-Codex-" + window + "-Reset-At"))
		if err == nil && ok && minutes > longest {
			best, longest = reset, minutes
		}
	}
	return best, longest > 0
}

func unixTime(raw string) (time.Time, bool) {
	seconds, err := strconv.ParseFloat(raw, 64)
	if err != nil || seconds <= 0 {
		return time.Time{}, false
	}
	return time.Unix(int64(seconds), 0), true
}
