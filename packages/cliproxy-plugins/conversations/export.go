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

// Context is what a call ran with beside its messages: the system prompt or
// instructions, and the tool definitions. It is not part of the message
// tree, so an export of a call adds it from the call's request and
// response.
type Context struct {
	System []string
	Tools  []map[string]any
	// The instructions and tools a Responses API response echoed as in
	// effect. Codex leaves tools out of its websocket requests, and a request
	// continuing a previous response sends neither, so often only the echo
	// has them.
	echo *Context
}

// Add reads a system, instructions, or tools value of a request body: the
// whole value, or one element of an array, as the request's parts and
// envelope hold them. A response body, as field response, adds what the
// response echoed.
func (c *Context) Add(field string, raw []byte) {
	if field == "response" {
		for _, e := range events(string(raw)) {
			r := parse(e).obj("response")
			if r == nil && parse(e).str("object") == "response" {
				r = parse(e)
			}
			if r != nil {
				c.echo = &Context{}
				c.echo.Add("instructions", r["instructions"])
				c.echo.Add("tools", r["tools"])
				return
			}
		}
		return
	}
	v := value(raw)
	values, ok := v.([]any)
	if !ok {
		values = []any{v}
	}
	for _, v := range values {
		switch field {
		case "system", "instructions":
			switch v := v.(type) {
			case string:
				if v != "" {
					c.System = append(c.System, v)
				}
			case map[string]any:
				if s := text(v["text"]); s != "" {
					c.System = append(c.System, s)
				}
			}
		case "tools":
			if t, ok := v.(map[string]any); ok {
				c.Tools = append(c.Tools, t)
			}
		}
	}
}

// effective is the context the model ran with: what the response echoed
// where it echoed anything, and what the request sent otherwise. Namespaces,
// which only the Responses API has, are flattened into their tools, since a
// call names its tool without the namespace; a name defined twice keeps its
// first definition.
func (c Context) effective() Context {
	out := Context{System: c.System}
	tools := c.Tools
	if c.echo != nil && len(c.echo.System) > 0 {
		out.System = c.echo.System
	}
	if c.echo != nil && len(c.echo.Tools) > 0 {
		tools = c.echo.Tools
	}
	seen := map[string]bool{}
	var add func(t map[string]any)
	add = func(t map[string]any) {
		if t["type"] == "namespace" {
			nested, _ := t["tools"].([]any)
			for _, n := range nested {
				if n, ok := n.(map[string]any); ok {
					add(n)
				}
			}
			return
		}
		name, _, _, _ := function(t)
		if name = firstNonEmpty(name, text(t["name"])); name != "" && seen[name] {
			return
		}
		seen[name] = true
		out.Tools = append(out.Tools, t)
	}
	for _, t := range tools {
		add(t)
	}
	return out
}

// function reads a tool definition in any dialect as a function name,
// description, and JSON schema. Hosted tools, such as web search, have no
// schema and are kept as they are.
func function(t map[string]any) (name, description string, schema any, ok bool) {
	if f, isChat := t["function"].(map[string]any); isChat {
		return text(f["name"]), text(f["description"]), f["parameters"], true
	}
	if schema, ok := t["input_schema"]; ok {
		return text(t["name"]), text(t["description"]), schema, true
	}
	if t["type"] == "function" {
		return text(t["name"]), text(t["description"]), t["parameters"], true
	}
	return "", "", nil, false
}

// customTool reads a freeform custom tool definition, in the Responses or
// Chat Completions shape. Its calls carry raw text rather than JSON
// arguments.
func customTool(t map[string]any) (name, description string, format any, ok bool) {
	if t["type"] != "custom" {
		return "", "", nil, false
	}
	if c, isChat := t["custom"].(map[string]any); isChat {
		t = c
	}
	return text(t["name"]), text(t["description"]), t["format"], true
}

// isCustomCall reports whether a tool call invokes a freeform custom tool.
func isCustomCall(b Block) bool { return b.SourceType == "custom_tool_call" }

// OpenAIChat renders a call or conversation as a Chat Completions request
// for training: the context's system prompt and tools, then text,
// reasoning, tool calls, and tool results in the order they happened.
// Consecutive assistant messages, such as Responses items or streamed Claude
// Code blocks, become one message until a tool result ends the turn. Images
// and files are left out: their data is only in the raw items. Freeform
// custom tools stay custom in both their definitions and their calls.
func OpenAIChat(ctx Context, path []Message) map[string]any {
	ctx = ctx.effective()
	var out []map[string]any
	if len(ctx.System) > 0 {
		out = append(out, map[string]any{"role": "system", "content": strings.Join(ctx.System, "\n\n")})
	}
	var assistant map[string]any
	turn := func() map[string]any {
		if assistant == nil {
			assistant = map[string]any{"role": "assistant", "content": ""}
			out = append(out, assistant)
		}
		return assistant
	}
	for _, m := range path {
		if m.Role != "assistant" {
			assistant = nil
		}
		var texts []string
		flushTexts := func() {
			if len(texts) > 0 {
				out = append(out, map[string]any{"role": m.Role, "content": strings.Join(texts, "\n\n")})
				texts = nil
			}
		}
		for _, b := range m.Blocks {
			switch b.Type {
			case "text", "compaction":
				if b.Text == "" {
					continue
				}
				if m.Role == "assistant" {
					turn()["content"] = join(turn()["content"], b.Text)
				} else {
					texts = append(texts, b.Text)
				}
			case "thinking":
				if b.Text != "" && m.Role == "assistant" {
					turn()["reasoning_content"] = join(turn()["reasoning_content"], b.Text)
				}
			case "tool_call":
				if m.Role == "assistant" {
					prior, _ := turn()["tool_calls"].([]any)
					call := map[string]any{"id": b.ToolCallID, "type": "function",
						"function": map[string]any{"name": b.ToolName, "arguments": b.ToolInput}}
					if isCustomCall(b) {
						call = map[string]any{"id": b.ToolCallID, "type": "custom",
							"custom": map[string]any{"name": b.ToolName, "input": b.ToolInput}}
					}
					turn()["tool_calls"] = append(prior, call)
				}
			case "tool_result":
				// OpenCode keeps a tool's result in the assistant message;
				// the result ends the assistant's turn either way.
				flushTexts()
				assistant = nil
				out = append(out, map[string]any{"role": "tool", "tool_call_id": b.ToolCallID, "content": b.Text})
			}
		}
		flushTexts()
	}
	request := map[string]any{"messages": out}
	var tools []any
	for _, t := range ctx.Tools {
		if name, description, schema, ok := function(t); ok {
			f := map[string]any{"name": name, "description": description}
			if schema != nil {
				f["parameters"] = schema
			}
			tools = append(tools, map[string]any{"type": "function", "function": f})
		} else if name, description, format, ok := customTool(t); ok {
			c := map[string]any{"name": name, "description": description}
			if f, ok := format.(map[string]any); ok && f["type"] == "grammar" && f["grammar"] == nil {
				// Chat Completions nests a grammar one level deeper.
				format = map[string]any{"type": "grammar",
					"grammar": map[string]any{"definition": f["definition"], "syntax": f["syntax"]}}
			}
			if format != nil {
				c["format"] = format
			}
			tools = append(tools, map[string]any{"type": "custom", "custom": c})
		} else {
			tools = append(tools, t)
		}
	}
	if len(tools) > 0 {
		request["tools"] = tools
	}
	return request
}

// AnthropicMessages renders a call or conversation as an Anthropic Messages
// request: system prompt, tools, and messages in the order they happened.
// Tool results are user content, and consecutive messages of a role merge,
// as the API requires. Anthropic has no freeform custom tools, so they
// become tools taking their raw text as input, in both their definitions
// and their calls.
func AnthropicMessages(ctx Context, path []Message) map[string]any {
	ctx = ctx.effective()
	system := append([]string{}, ctx.System...)
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
		role := "user"
		switch m.Role {
		case "assistant":
			role = "assistant"
		case "system", "developer":
			role = "system"
		}
		var blocks []any
		for _, b := range m.Blocks {
			switch b.Type {
			case "text", "compaction":
				if b.Text == "" {
					continue
				}
				if role == "system" {
					system = append(system, b.Text)
				} else {
					blocks = append(blocks, map[string]any{"type": "text", "text": b.Text})
				}
			case "thinking":
				if b.Text != "" {
					blocks = append(blocks, map[string]any{"type": "thinking", "thinking": b.Text})
				}
			case "tool_call":
				var input any = map[string]any{}
				if isCustomCall(b) {
					// Anthropic has no freeform tools; the definition takes
					// the raw text as input.
					input = map[string]any{"input": b.ToolInput}
				} else if b.ToolInput != "" && json.Unmarshal([]byte(b.ToolInput), &input) != nil {
					input = map[string]any{"input": b.ToolInput}
				}
				blocks = append(blocks, map[string]any{"type": "tool_use", "id": b.ToolCallID, "name": b.ToolName, "input": input})
			case "tool_result":
				result := map[string]any{"type": "tool_result", "tool_use_id": b.ToolCallID,
					"content": b.Text, "is_error": b.IsError}
				if role == "assistant" {
					// OpenCode keeps a tool's result in the assistant message.
					add("assistant", blocks)
					blocks = nil
					add("user", []any{result})
				} else {
					blocks = append(blocks, result)
				}
			}
		}
		if role != "system" {
			add(role, blocks)
		}
	}
	request := map[string]any{"system": strings.Join(system, "\n\n"), "messages": out}
	var tools []any
	for _, t := range ctx.Tools {
		if name, description, schema, ok := function(t); ok {
			tool := map[string]any{"name": name, "description": description}
			if schema != nil {
				tool["input_schema"] = schema
			}
			tools = append(tools, tool)
		} else if name, description, _, ok := customTool(t); ok {
			tools = append(tools, map[string]any{"name": name, "description": description,
				"input_schema": map[string]any{"type": "object", "required": []any{"input"},
					"properties": map[string]any{"input": map[string]any{"type": "string"}}}})
		} else {
			tools = append(tools, t)
		}
	}
	if len(tools) > 0 {
		request["tools"] = tools
	}
	return request
}

func join(prior any, s string) string {
	p, _ := prior.(string)
	if p == "" {
		return s
	}
	return p + "\n\n" + s
}
