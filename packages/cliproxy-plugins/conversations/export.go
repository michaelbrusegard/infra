package conversations

import (
	"encoding/json"
	"strings"
)

// Path returns the conversation ending at leaf, from its root. With the
// leaf of a call's input or last output, it is the context the model saw.
func Path(messages []Message, leaf Hash) []Message {
	byID := make(map[Hash]Message, len(messages))
	for _, m := range messages {
		byID[m.ID] = m
	}
	var path []Message
	for id := leaf; id != (Hash{}); {
		m, ok := byID[id]
		if !ok {
			break
		}
		path = append(path, m)
		id = m.ParentID
	}
	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}
	return path
}

// OpenAIChat renders a conversation as Chat Completions messages for
// training: text, reasoning, tool calls, and tool results. Consecutive
// assistant messages, such as Responses items or streamed Claude Code
// blocks, become one message. Images and files are left out: their data is
// only in the raw items.
func OpenAIChat(path []Message) []map[string]any {
	var out []map[string]any
	var assistant map[string]any
	flush := func() {
		if assistant != nil {
			out = append(out, assistant)
			assistant = nil
		}
	}
	for _, m := range path {
		var texts, thinking []string
		var calls []any
		var results []map[string]any
		for _, b := range m.Blocks {
			switch b.Type {
			case "text", "compaction":
				if b.Text != "" {
					texts = append(texts, b.Text)
				}
			case "thinking":
				if b.Text != "" {
					thinking = append(thinking, b.Text)
				}
			case "tool_call":
				calls = append(calls, map[string]any{"id": b.ToolCallID, "type": "function",
					"function": map[string]any{"name": b.ToolName, "arguments": b.ToolInput}})
			case "tool_result":
				results = append(results, map[string]any{"role": "tool", "tool_call_id": b.ToolCallID, "content": b.Text})
			}
		}
		if m.Role == "assistant" {
			if assistant == nil {
				assistant = map[string]any{"role": "assistant", "content": ""}
			}
			assistant["content"] = join(assistant["content"], texts)
			if len(thinking) > 0 {
				assistant["reasoning_content"] = join(assistant["reasoning_content"], thinking)
			}
			if len(calls) > 0 {
				prior, _ := assistant["tool_calls"].([]any)
				assistant["tool_calls"] = append(prior, calls...)
			}
			if len(results) > 0 {
				// OpenCode keeps a tool's result in the assistant message.
				flush()
				for _, r := range results {
					out = append(out, r)
				}
			}
			continue
		}
		flush()
		for _, r := range results {
			out = append(out, r)
		}
		if len(texts) > 0 {
			out = append(out, map[string]any{"role": m.Role, "content": strings.Join(texts, "\n\n")})
		}
	}
	flush()
	return out
}

// AnthropicMessages renders a conversation as an Anthropic Messages system
// prompt and messages. Tool results are user content, and consecutive
// messages of a role merge, as the API requires.
func AnthropicMessages(path []Message) (string, []map[string]any) {
	var system []string
	var out []map[string]any
	add := func(role string, blocks []any) {
		if len(blocks) == 0 {
			return
		}
		if n := len(out); n > 0 && out[n-1]["role"] == role {
			out[n-1]["content"] = append(out[n-1]["content"].([]any), blocks...)
			return
		}
		out = append(out, map[string]any{"role": role, "content": blocks})
	}
	for _, m := range path {
		var blocks, results []any
		for _, b := range m.Blocks {
			switch b.Type {
			case "text", "compaction":
				if b.Text != "" {
					blocks = append(blocks, map[string]any{"type": "text", "text": b.Text})
				}
			case "thinking":
				if b.Text != "" {
					blocks = append(blocks, map[string]any{"type": "thinking", "thinking": b.Text})
				}
			case "tool_call":
				var input any = map[string]any{}
				if b.ToolInput != "" && json.Unmarshal([]byte(b.ToolInput), &input) != nil {
					input = map[string]any{"input": b.ToolInput}
				}
				blocks = append(blocks, map[string]any{"type": "tool_use", "id": b.ToolCallID, "name": b.ToolName, "input": input})
			case "tool_result":
				results = append(results, map[string]any{"type": "tool_result", "tool_use_id": b.ToolCallID,
					"content": b.Text, "is_error": b.IsError})
			}
		}
		switch m.Role {
		case "system", "developer":
			for _, b := range blocks {
				if text, ok := b.(map[string]any)["text"].(string); ok {
					system = append(system, text)
				}
			}
		case "assistant":
			add("assistant", blocks)
			add("user", results)
		default:
			add("user", append(results, blocks...))
		}
	}
	return strings.Join(system, "\n\n"), out
}

func join(prior any, texts []string) string {
	s, _ := prior.(string)
	if len(texts) == 0 {
		return s
	}
	if s != "" {
		s += "\n\n"
	}
	return s + strings.Join(texts, "\n\n")
}
