package conversations

import (
	"encoding/json"
	"fmt"
	"reflect"
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

// exported is what an export writes beside the messages: the system prompt,
// and the tools under the names the export gives them.
type exported struct {
	system []string
	tools  []exportedTool
	// Export names by namespace and name, for every tool defined.
	names map[[2]string]string
}

type exportedTool struct {
	name string
	def  map[string]any
}

// The namespace the Responses API echoes top-level tools in. Calls to its
// tools name no namespace.
const defaultNamespace = "functions"

// effective is the context the model ran with: what the response echoed
// where it echoed anything, and what the request sent otherwise. Namespaces,
// which only the Responses API has, are flattened into their tools, since
// the export dialects have none. Tools keep their bare names unless more than
// one namespace defines the name; then those tools, and the calls naming
// them, become namespace__name, as MCP tools are named elsewhere. A call
// matches a tool by namespace and name, and an export that would have to
// guess which tool a call means fails instead. Hosted tools are left out,
// with their calls; see hosted.
func (c Context) effective() (exported, error) {
	out := exported{system: c.System, names: map[[2]string]string{}}
	tools := c.Tools
	if c.echo != nil && len(c.echo.System) > 0 {
		out.system = c.echo.System
	}
	if c.echo != nil && len(c.echo.Tools) > 0 {
		tools = c.echo.Tools
	}
	type defined struct {
		namespace string
		exportedTool
	}
	var all []defined
	namespaces := map[string]map[string]bool{}
	var add func(namespace string, t map[string]any) error
	add = func(namespace string, t map[string]any) error {
		if t["type"] == "namespace" {
			nested, _ := t["tools"].([]any)
			ns := text(t["name"])
			if ns == defaultNamespace {
				ns = ""
			}
			for _, n := range nested {
				if n, ok := n.(map[string]any); ok {
					if err := add(ns, n); err != nil {
						return err
					}
				}
			}
			return nil
		}
		if _, _, _, ok := function(t); !ok {
			if _, _, _, ok := customTool(t); !ok {
				return nil
			}
		}
		name := toolName(t)
		if name != "" {
			if namespaces[name] == nil {
				namespaces[name] = map[string]bool{}
			}
			if namespaces[name][namespace] {
				for _, d := range all {
					if d.namespace == namespace && d.name == name && !reflect.DeepEqual(d.def, t) {
						return fmt.Errorf("tool %q is defined twice, differently", qualify(namespace, name))
					}
				}
				return nil
			}
			namespaces[name][namespace] = true
		}
		all = append(all, defined{namespace, exportedTool{name, t}})
		return nil
	}
	for _, t := range tools {
		if err := add("", t); err != nil {
			return exported{}, err
		}
	}
	names := map[string]bool{}
	for _, d := range all {
		key := [2]string{d.namespace, d.name}
		if len(namespaces[d.name]) > 1 {
			d.name = qualify(d.namespace, d.name)
		}
		out.names[key] = d.name
		if d.name != "" && names[d.name] {
			return exported{}, fmt.Errorf("two tools are exported as %q", d.name)
		}
		names[d.name] = true
		out.tools = append(out.tools, d.exportedTool)
	}
	return out, nil
}

func qualify(namespace, name string) string {
	if namespace == "" {
		return name
	}
	return namespace + "__" + name
}

// toolName reads the name a call uses for a tool definition.
func toolName(t map[string]any) string {
	name, _, _, _ := function(t)
	return firstNonEmpty(name, text(t["name"]))
}

// call returns the name an export gives a tool call's tool: the name of the
// tool its namespace defines under its name. A call to a name that only
// other namespaces define fails, rather than take another tool's schema. A
// name nothing defines stays as it is; ForTraining refuses such calls.
func (e exported) call(b Block) (string, error) {
	ns := b.ToolNamespace
	if ns == defaultNamespace {
		ns = ""
	}
	if name, ok := e.names[[2]string{ns, b.ToolName}]; ok {
		return name, nil
	}
	for key := range e.names {
		if key[1] == b.ToolName {
			return "", fmt.Errorf("call %s to %q matches none of the namespaces defining it", b.ToolCallID, qualify(ns, b.ToolName))
		}
	}
	return b.ToolName, nil
}

// function reads a tool definition in any dialect as a function name,
// description, and JSON schema. Hosted tools, such as web search, have no
// schema.
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

// hosted returns the IDs of the path's calls to hosted tools, such as
// Responses web_search_call or tool_search_call items and Anthropic
// server_tool_use blocks. Exports leave them out with their results and
// definitions: Chat Completions has no hosted tools, and Anthropic's hosted
// results are opaque, often encrypted, and only in the raw items, so neither
// export could write them back. The text the model wrote from a result
// stays.
func hosted(path []Message) map[string]bool {
	ids := map[string]bool{}
	for _, m := range path {
		for _, b := range m.Blocks {
			if isHostedCall(b) {
				ids[b.ToolCallID] = true
			}
		}
	}
	return ids
}

func isHostedCall(b Block) bool {
	t := b.SourceType
	return b.Type == "tool_call" && (t == "server_tool_use" || t == "mcp_tool_use" ||
		strings.HasSuffix(t, "_call") && t != "function_call" && t != "custom_tool_call")
}

// OpenAIChat renders a call or conversation as a Chat Completions request
// for training: the context's system prompt and tools, then text,
// reasoning, tool calls, and tool results in the order they happened.
// Consecutive assistant messages, such as Responses items or streamed Claude
// Code blocks, become one message until a tool result ends the turn. Images
// and files are left out: their data is only in the raw items. Freeform
// custom tools stay custom in both their definitions and their calls.
func OpenAIChat(ctx Context, path []Message) (map[string]any, error) {
	e, err := ctx.effective()
	if err != nil {
		return nil, err
	}
	var out []map[string]any
	if len(e.system) > 0 {
		out = append(out, map[string]any{"role": "system", "content": strings.Join(e.system, "\n\n")})
	}
	dropped := hosted(path)
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
				if m.Role == "assistant" && !dropped[b.ToolCallID] {
					name, err := e.call(b)
					if err != nil {
						return nil, err
					}
					prior, _ := turn()["tool_calls"].([]any)
					call := map[string]any{"id": b.ToolCallID, "type": "function",
						"function": map[string]any{"name": name, "arguments": b.ToolInput}}
					if isCustomCall(b) {
						call = map[string]any{"id": b.ToolCallID, "type": "custom",
							"custom": map[string]any{"name": name, "input": b.ToolInput}}
					}
					turn()["tool_calls"] = append(prior, call)
				}
			case "tool_result":
				if dropped[b.ToolCallID] {
					continue
				}
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
	for _, et := range e.tools {
		t, name := et.def, et.name
		if _, description, schema, ok := function(t); ok {
			f := map[string]any{"name": name, "description": description}
			if schema != nil {
				f["parameters"] = schema
			}
			tools = append(tools, map[string]any{"type": "function", "function": f})
		} else if _, description, format, ok := customTool(t); ok {
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
		}
	}
	if len(tools) > 0 {
		request["tools"] = tools
	}
	return request, nil
}

// AnthropicMessages renders a call or conversation as an Anthropic Messages
// request: system prompt, tools, and messages in the order they happened.
// Tool results are user content, and consecutive messages of a role merge,
// as the API requires. Anthropic has no freeform custom tools, so they
// become tools taking their raw text as input, in both their definitions
// and their calls.
func AnthropicMessages(ctx Context, path []Message) (map[string]any, error) {
	e, err := ctx.effective()
	if err != nil {
		return nil, err
	}
	system := append([]string{}, e.system...)
	dropped := hosted(path)
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
				if dropped[b.ToolCallID] {
					continue
				}
				name, err := e.call(b)
				if err != nil {
					return nil, err
				}
				var input any = map[string]any{}
				if isCustomCall(b) {
					// Anthropic has no freeform tools; the definition takes
					// the raw text as input.
					input = map[string]any{"input": b.ToolInput}
				} else if b.ToolInput != "" && json.Unmarshal([]byte(b.ToolInput), &input) != nil {
					input = map[string]any{"input": b.ToolInput}
				}
				blocks = append(blocks, map[string]any{"type": "tool_use", "id": b.ToolCallID, "name": name, "input": input})
			case "tool_result":
				if dropped[b.ToolCallID] {
					continue
				}
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
	for _, et := range e.tools {
		t, name := et.def, et.name
		if _, description, schema, ok := function(t); ok {
			tool := map[string]any{"name": name, "description": description}
			if schema != nil {
				tool["input_schema"] = schema
			}
			tools = append(tools, tool)
		} else if _, description, _, ok := customTool(t); ok {
			tools = append(tools, map[string]any{"name": name, "description": description,
				"input_schema": map[string]any{"type": "object", "required": []any{"input"},
					"properties": map[string]any{"input": map[string]any{"type": "string"}}}})
		}
	}
	if len(tools) > 0 {
		request["tools"] = tools
	}
	return request, nil
}

// ForTraining checks that a call makes a training example: that the model
// produced something an export keeps, and that every tool its output calls
// is defined. A call that failed or returned nothing fails the first, and a
// call whose context is unknown fails the second: a failed Responses call
// with output but no echo after a request that sent no tools, or a
// transcript call, whose tools the transcript does not record. Writing
// those as examples would teach calls to tools the model was never given.
// A call to a JSON-schema tool also needs a JSON object as arguments: an
// interrupted stream keeps what streamed in the canonical rows, but
// partial arguments would teach invalid calls.
//
// Only the call's own outputs, by ID, are checked. Others on the path are
// context, even when they end it: a failed delta call that sent nothing new
// ends at the output of the call it continues.
func ForTraining(ctx Context, path []Message, outputs []Hash) error {
	e, err := ctx.effective()
	if err != nil {
		return err
	}
	defined := map[string]bool{}
	for _, t := range e.tools {
		defined[t.name] = true
	}
	own := map[Hash]bool{}
	for _, id := range outputs {
		own[id] = true
	}
	dropped := hosted(path)
	kept := 0
	for _, m := range path {
		if !own[m.ID] {
			continue
		}
		delete(own, m.ID)
		for _, b := range m.Blocks {
			switch {
			case b.Type == "text" || b.Type == "thinking":
				if b.Text != "" {
					kept++
				}
			case b.Type == "tool_call" && !dropped[b.ToolCallID]:
				name, err := e.call(b)
				if err != nil {
					return err
				}
				if !defined[name] {
					return fmt.Errorf("the output calls %q, which the call's context does not define", name)
				}
				var args map[string]any
				if !isCustomCall(b) && (json.Unmarshal([]byte(b.ToolInput), &args) != nil || args == nil) {
					return fmt.Errorf("the arguments of call %s to %q are no JSON object, as an interrupted stream leaves them", b.ToolCallID, name)
				}
				kept++
			}
		}
	}
	if len(own) > 0 {
		return fmt.Errorf("the call's outputs are not on its conversation")
	}
	if kept == 0 {
		return fmt.Errorf("the call produced no output to train on")
	}
	return nil
}

func join(prior any, s string) string {
	p, _ := prior.(string)
	if p == "" {
		return s
	}
	return p + "\n\n" + s
}
