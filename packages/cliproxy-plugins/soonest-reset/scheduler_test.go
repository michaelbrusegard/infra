package main

import (
	"net/http"
	"strconv"
	"testing"
	"time"
)

func request(session string, ids ...string) pickRequest {
	r := pickRequest{Provider: "claude"}
	r.Options.Metadata = map[string]any{"canonical_session_id": session}
	for _, id := range ids {
		r.Candidates = append(r.Candidates, candidate{ID: id})
	}
	return r
}

func picked(t *testing.T, result map[string]any) string {
	t.Helper()
	if result["handled"] != true {
		t.Fatalf("pick was not handled: %v", result)
	}
	return result["auth_id"].(string)
}

func TestSingleCandidateIsLeftToTheHost(t *testing.T) {
	s := newScheduler()
	if got := s.pick(request("s", "a"), time.Now()); got["handled"] != false {
		t.Fatalf("got %v", got)
	}
}

func TestNewSessionGoesToSoonestReset(t *testing.T) {
	now := time.Now()
	s := newScheduler()
	s.resets["a"] = now.Add(96 * time.Hour)
	s.resets["b"] = now.Add(24 * time.Hour)
	s.resets["c"] = now.Add(48 * time.Hour)
	if got := picked(t, s.pick(request("s", "a", "b", "c"), now)); got != "b" {
		t.Fatalf("picked %s, want b", got)
	}
}

func TestUnknownOrPassedResetGoesFirst(t *testing.T) {
	now := time.Now()
	s := newScheduler()
	s.resets["a"] = now.Add(time.Hour)
	s.resets["b"] = now.Add(-time.Hour)
	if got := picked(t, s.pick(request("s1", "a", "b"), now)); got != "b" {
		t.Fatalf("passed reset: picked %s, want b", got)
	}
	s.resets["b"] = now.Add(2 * time.Hour)
	if got := picked(t, s.pick(request("s2", "a", "b", "new"), now)); got != "new" {
		t.Fatalf("unknown reset: picked %s, want new", got)
	}
}

func TestSessionStaysOnItsAccount(t *testing.T) {
	now := time.Now()
	s := newScheduler()
	s.resets["a"] = now.Add(24 * time.Hour)
	s.resets["b"] = now.Add(48 * time.Hour)
	if got := picked(t, s.pick(request("s", "a", "b"), now)); got != "a" {
		t.Fatalf("picked %s, want a", got)
	}
	// b now resets sooner, but the session keeps its prompt cache on a.
	s.resets["b"] = now.Add(time.Hour)
	if got := picked(t, s.pick(request("s", "a", "b"), now.Add(30*time.Minute))); got != "a" {
		t.Fatalf("picked %s, want a", got)
	}
	// A new session still picks the soonest reset.
	if got := picked(t, s.pick(request("other", "a", "b"), now)); got != "b" {
		t.Fatalf("picked %s, want b", got)
	}
}

func TestSessionMovesWhenItsAccountDropsOut(t *testing.T) {
	now := time.Now()
	s := newScheduler()
	s.resets["a"] = now.Add(24 * time.Hour)
	s.resets["b"] = now.Add(48 * time.Hour)
	s.resets["c"] = now.Add(72 * time.Hour)
	picked(t, s.pick(request("s", "a", "b", "c"), now))
	if got := picked(t, s.pick(request("s", "b", "c"), now)); got != "b" {
		t.Fatalf("picked %s, want b", got)
	}
	// It stays on the new account once the old one is back.
	if got := picked(t, s.pick(request("s", "a", "b", "c"), now)); got != "b" {
		t.Fatalf("picked %s, want b", got)
	}
}

func TestIdleSessionIsRepicked(t *testing.T) {
	now := time.Now()
	s := newScheduler()
	s.resets["a"] = now.Add(24 * time.Hour)
	s.resets["b"] = now.Add(48 * time.Hour)
	picked(t, s.pick(request("s", "a", "b"), now))
	s.resets["b"] = now.Add(2 * time.Hour)
	if got := picked(t, s.pick(request("s", "a", "b"), now.Add(sessionTTL+time.Minute))); got != "b" {
		t.Fatalf("picked %s, want b", got)
	}
}

func unix(t time.Time) string {
	return strconv.FormatInt(t.Unix(), 10)
}

func TestLongestWindowReset(t *testing.T) {
	week := time.Unix(1_800_000_000, 0)
	hours := time.Unix(1_799_000_000, 0)
	cases := map[string]struct {
		headers http.Header
		want    time.Time
		ok      bool
	}{
		"claude weekly": {
			headers: http.Header{
				"anthropic-ratelimit-unified-5h-reset": {unix(hours)},
				"anthropic-ratelimit-unified-7d-reset": {unix(week)},
			},
			want: week, ok: true,
		},
		"codex weekly in secondary": {
			headers: http.Header{
				"X-Codex-Primary-Window-Minutes":   {"300"},
				"X-Codex-Primary-Reset-At":         {unix(hours)},
				"X-Codex-Secondary-Window-Minutes": {"10080"},
				"X-Codex-Secondary-Reset-At":       {unix(week)},
			},
			want: week, ok: true,
		},
		"codex pro weekly in primary": {
			headers: http.Header{
				"X-Codex-Primary-Window-Minutes": {"10080"},
				"X-Codex-Primary-Reset-At":       {unix(week)},
			},
			want: week, ok: true,
		},
		"no quota headers": {headers: http.Header{"Content-Type": {"application/json"}}},
	}
	for name, c := range cases {
		got, ok := longestWindowReset(c.headers)
		if ok != c.ok || !got.Equal(c.want) {
			t.Errorf("%s: got %v %v, want %v %v", name, got, ok, c.want, c.ok)
		}
	}
}

func TestUsageTeachesReset(t *testing.T) {
	s := newScheduler()
	reset := time.Now().Add(24 * time.Hour).Truncate(time.Second)
	raw := []byte(`{"AuthID":"a","ResponseHeaders":{"Anthropic-Ratelimit-Unified-7d-Reset":["` + unix(reset) + `"]}}`)
	if _, ok := s.Handle("usage.handle", raw); !ok {
		t.Fatal("usage.handle failed")
	}
	if !s.resets["a"].Equal(reset) {
		t.Fatalf("got %v, want %v", s.resets["a"], reset)
	}
}
