package conversations

import (
	"encoding/json"
	"strings"
)

// anthropicContent reads Anthropic Messages content: a string, or an array
// of blocks. Claude Code transcripts use the same blocks.
func anthropicContent(content json.RawMessage) []Block {
	if isString(content) {
		return []Block{{Type: "text", SourceType: "text", Text: str(content)}}
	}
	var out []Block
	for _, raw := range array(content) {
		b := parse(raw)
		t := b.str("type")
		switch {
		case t == "text":
			out = append(out, Block{Type: "text", SourceType: t, Text: b.str("text")})
		case t == "thinking":
			out = append(out, Block{Type: "thinking", SourceType: t, Text: b.str("thinking")})
		case t == "redacted_thinking":
			out = append(out, Block{Type: "thinking", SourceType: t})
		case t == "tool_use" || t == "server_tool_use" || t == "mcp_tool_use":
			out = append(out, Block{Type: "tool_call", SourceType: t, ToolName: b.str("name"),
				ToolCallID: b.str("id"), ToolInput: compactJSON(b["input"])})
		case strings.HasSuffix(t, "tool_result"):
			result := Block{Type: "tool_result", SourceType: t, ToolCallID: b.str("tool_use_id"),
				IsError: b.boolean("is_error")}
			var media []Block
			if isString(b["content"]) {
				result.Text = str(b["content"])
			} else {
				var texts []string
				for _, part := range anthropicContent(b["content"]) {
					if part.Type == "text" {
						texts = append(texts, part.Text)
					} else {
						part.ToolCallID = result.ToolCallID
						media = append(media, part)
					}
				}
				result.Text = strings.Join(texts, "\n")
			}
			out = append(append(out, result), media...)
		case t == "tool_reference":
			// A tool that a tool search loaded, in its result.
			out = append(out, Block{Type: "text", SourceType: t, Text: b.str("tool_name")})
		case t == "image" || t == "document":
			kind := map[string]string{"image": "image", "document": "file"}[t]
			out = append(out, Block{Type: kind, SourceType: t, Media: b.obj("source").str("media_type")})
		default:
			out = append(out, Block{Type: "other", SourceType: t})
		}
	}
	return out
}

// responsesItem reads one OpenAI Responses API item, as sent in input, as
// returned in output, or as recorded by Codex.
func responsesItem(raw []byte) (string, []Block) {
	it := parse(raw)
	t := it.str("type")
	role := it.str("role")
	if t == "" && role != "" {
		t = "message"
	}
	switch t {
	case "message":
		return role, responsesContent(it["content"], "")
	case "agent_message":
		// A message between Codex agents, which its recipient is sent as
		// input. The header names the sender and the task; the payload is
		// encrypted.
		return "user", responsesContent(it["content"], "")
	case "reasoning":
		var texts []string
		for _, key := range []string{"summary", "content"} {
			for _, part := range it.arr(key) {
				texts = append(texts, parse(part).str("text"))
			}
		}
		return "assistant", []Block{{Type: "thinking", SourceType: t, Text: strings.Join(texts, "\n\n")}}
	case "function_call", "custom_tool_call":
		input := it["arguments"]
		if t == "custom_tool_call" {
			input = it["input"]
		}
		return "assistant", []Block{{Type: "tool_call", SourceType: t, ToolName: it.str("name"),
			ToolNamespace: it.str("namespace"), ToolCallID: it.str("call_id"), ToolInput: compactJSON(input)}}
	case "function_call_output", "custom_tool_call_output", "tool_search_output":
		result := Block{Type: "tool_result", SourceType: t, ToolCallID: it.str("call_id")}
		output := it["output"]
		if t == "tool_search_output" {
			output = it["tools"]
		}
		if isString(output) {
			result.Text = str(output)
			return "tool", []Block{result}
		}
		var texts []string
		var media []Block
		for _, part := range responsesContent(output, result.ToolCallID) {
			if part.Type == "text" {
				texts = append(texts, part.Text)
			} else {
				media = append(media, part)
			}
		}
		if len(texts) == 0 && len(media) == 0 {
			texts = append(texts, compactJSON(output))
		}
		result.Text = strings.Join(texts, "\n")
		return "tool", append([]Block{result}, media...)
	case "compaction":
		return "system", []Block{{Type: "compaction", SourceType: t}}
	}
	// Hosted tools: web_search_call, tool_search_call, local_shell_call, ...
	if strings.HasSuffix(t, "_call") {
		input := it["action"]
		if input == nil {
			input = it["arguments"]
		}
		return "assistant", []Block{{Type: "tool_call", SourceType: t, ToolName: strings.TrimSuffix(t, "_call"),
			ToolCallID: firstNonEmpty(it.str("call_id"), it.str("id")), ToolInput: compactJSON(input)}}
	}
	if role == "" {
		role = "system"
	}
	return role, []Block{{Type: "other", SourceType: t}}
}

func responsesContent(content json.RawMessage, callID string) []Block {
	if isString(content) {
		return []Block{{Type: "text", SourceType: "text", Text: str(content)}}
	}
	var out []Block
	for _, raw := range array(content) {
		p := parse(raw)
		t := p.str("type")
		switch t {
		case "input_text", "output_text", "text", "summary_text", "reasoning_text":
			out = append(out, Block{Type: "text", SourceType: t, Text: p.str("text")})
		case "refusal":
			out = append(out, Block{Type: "text", SourceType: t, Text: p.str("refusal")})
		case "input_image":
			out = append(out, Block{Type: "image", SourceType: t, ToolCallID: callID, Media: mediaOf(p.str("image_url"))})
		case "input_file":
			out = append(out, Block{Type: "file", SourceType: t, ToolCallID: callID,
				Text: p.str("filename"), Media: mediaOf(p.str("file_data"))})
		case "encrypted_content":
			// Encrypted, like reasoning; not extracted.
		default:
			out = append(out, Block{Type: "other", SourceType: t, ToolCallID: callID})
		}
	}
	return out
}

// chatMessage reads one OpenAI Chat Completions message.
func chatMessage(raw []byte) (string, []Block) {
	m := parse(raw)
	role := m.str("role")
	var out []Block
	if r := firstNonEmpty(m.str("reasoning_content"), m.str("reasoning")); r != "" {
		out = append(out, Block{Type: "thinking", SourceType: "reasoning_content", Text: r})
	}
	content := m["content"]
	if role == "tool" {
		result := Block{Type: "tool_result", SourceType: "tool", ToolCallID: m.str("tool_call_id")}
		var texts []string
		var media []Block
		for _, b := range chatContent(content) {
			if b.Type == "text" {
				texts = append(texts, b.Text)
			} else {
				b.ToolCallID = result.ToolCallID
				media = append(media, b)
			}
		}
		result.Text = strings.Join(texts, "\n")
		return "tool", append(append(out, result), media...)
	}
	out = append(out, chatContent(content)...)
	for _, raw := range m.arr("tool_calls") {
		c := parse(raw)
		f := c.obj("function")
		out = append(out, Block{Type: "tool_call", SourceType: firstNonEmpty(c.str("type"), "function"),
			ToolName: f.str("name"), ToolCallID: c.str("id"), ToolInput: compactJSON(f["arguments"])})
	}
	return role, out
}

func chatContent(content json.RawMessage) []Block {
	if isString(content) {
		if s := str(content); s != "" {
			return []Block{{Type: "text", SourceType: "text", Text: s}}
		}
		return nil
	}
	var out []Block
	for _, raw := range array(content) {
		p := parse(raw)
		switch t := p.str("type"); t {
		case "text":
			out = append(out, Block{Type: "text", SourceType: t, Text: p.str("text")})
		case "image_url":
			out = append(out, Block{Type: "image", SourceType: t, Media: mediaOf(p.obj("image_url").str("url"))})
		default:
			out = append(out, Block{Type: "other", SourceType: t})
		}
	}
	return out
}

// piMessage reads the message of a Pi session entry.
func piMessage(m obj) (string, []Block) {
	role := m.str("role")
	var parts []Block
	if isString(m["content"]) {
		if s := str(m["content"]); s != "" {
			parts = append(parts, Block{Type: "text", SourceType: "text", Text: s})
		}
	}
	for _, raw := range m.arr("content") {
		p := parse(raw)
		switch t := p.str("type"); t {
		case "text":
			parts = append(parts, Block{Type: "text", SourceType: t, Text: p.str("text")})
		case "thinking":
			parts = append(parts, Block{Type: "thinking", SourceType: t, Text: p.str("thinking")})
		case "toolCall":
			parts = append(parts, Block{Type: "tool_call", SourceType: t, ToolName: p.str("name"),
				ToolCallID: p.str("id"), ToolInput: compactJSON(p["arguments"])})
		case "image":
			parts = append(parts, Block{Type: "image", SourceType: t, Media: p.str("mimeType")})
		default:
			parts = append(parts, Block{Type: "other", SourceType: t})
		}
	}
	if role != "toolResult" {
		return role, parts
	}
	result := Block{Type: "tool_result", SourceType: role, ToolName: m.str("toolName"),
		ToolCallID: m.str("toolCallId"), IsError: m.boolean("isError")}
	var texts []string
	var media []Block
	for _, p := range parts {
		if p.Type == "text" {
			texts = append(texts, p.Text)
		} else {
			p.ToolCallID = result.ToolCallID
			media = append(media, p)
		}
	}
	result.Text = strings.Join(texts, "\n")
	return "tool", append([]Block{result}, media...)
}

// opencodeParts reads OpenCode message parts, stored inline as content in
// newer exports and as separate part records in older ones. A tool part
// holds both the call and its result.
func opencodeParts(parts []json.RawMessage) []Block {
	var out []Block
	for _, raw := range parts {
		p := parse(raw)
		switch t := p.str("type"); t {
		case "text":
			out = append(out, Block{Type: "text", SourceType: t, Text: p.str("text")})
		case "reasoning":
			out = append(out, Block{Type: "thinking", SourceType: t, Text: p.str("text")})
		case "file":
			out = append(out, Block{Type: "file", SourceType: t, Text: p.str("filename"), Media: p.str("mime")})
		case "tool":
			state := p.obj("state")
			id := firstNonEmpty(p.str("callID"), p.str("id"))
			out = append(out, Block{Type: "tool_call", SourceType: t, ToolName: firstNonEmpty(p.str("tool"), p.str("name")),
				ToolCallID: id, ToolInput: compactJSON(state["input"])})
			if status := state.str("status"); status == "completed" || status == "error" {
				out = append(out, Block{Type: "tool_result", SourceType: t, ToolCallID: id,
					Text: firstNonEmpty(compactJSON(state["output"]), state.str("error")), IsError: status == "error"})
			}
		case "compaction":
			out = append(out, Block{Type: "compaction", SourceType: t})
		case "step-start", "step-finish", "patch", "snapshot", "agent":
			// Step markers, and the snapshot hashes and file lists of the
			// edits the tool parts hold.
		default:
			out = append(out, Block{Type: "other", SourceType: t})
		}
	}
	return out
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
