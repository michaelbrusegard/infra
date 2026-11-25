package conversations

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"
)

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

type Context struct {
	System []string
	Tools  []map[string]any
	echo   *Context
}

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

type exported struct {
	system []string
	tools  []exportedTool
	names  map[[2]string]string
}

type exportedTool struct {
	name string
	def  map[string]any
}

const defaultNamespace = "functions"

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
			if _, _, ok := customTool(t); !ok {
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

func toolName(t map[string]any) string {
	name, _, _, _ := function(t)
	return firstNonEmpty(name, text(t["name"]))
}

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

func (e exported) name(b Block, target bool) (string, error) {
	if target {
		return e.call(b)
	}
	ns := b.ToolNamespace
	if ns == defaultNamespace {
		ns = ""
	}
	if name, ok := e.names[[2]string{ns, b.ToolName}]; ok {
		return name, nil
	}
	return qualify(ns, b.ToolName), nil
}

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

func customTool(t map[string]any) (description string, format any, ok bool) {
	if t["type"] != "custom" {
		return "", nil, false
	}
	if c, isChat := t["custom"].(map[string]any); isChat {
		t = c
	}
	return text(t["description"]), t["format"], true
}

func isCustomCall(b Block) bool { return b.SourceType == "custom_tool_call" }

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

func OpenAIChat(ctx Context, path []Message, targets []Hash) (map[string]any, error) {
	e, err := ctx.effective()
	if err != nil {
		return nil, err
	}
	own := set(targets)
	var out []map[string]any
	if len(e.system) > 0 {
		out = append(out, map[string]any{"role": "system", "content": strings.Join(e.system, "\n\n")})
	}
	dropped := hosted(path)
	var assistant map[string]any
	target := false
	turn := func() map[string]any {
		if assistant == nil {
			assistant = map[string]any{"role": "assistant", "content": ""}
			if targets != nil && !target {
				assistant["weight"] = 0
			}
			out = append(out, assistant)
		}
		return assistant
	}
	for _, m := range path {
		if m.Role != "assistant" || own[m.ID] != target {
			assistant = nil
		}
		target = own[m.ID]
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
					name, err := e.name(b, target)
					if err != nil {
						return nil, err
					}
					prior, _ := turn()["tool_calls"].([]any)
					call := map[string]any{
						"id": b.ToolCallID, "type": "function",
						"function": map[string]any{"name": name, "arguments": b.ToolInput},
					}
					if isCustomCall(b) {
						call = map[string]any{
							"id": b.ToolCallID, "type": "custom",
							"custom": map[string]any{"name": name, "input": b.ToolInput},
						}
					}
					turn()["tool_calls"] = append(prior, call)
				}
			case "tool_result":
				if dropped[b.ToolCallID] {
					continue
				}
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
		} else if description, format, ok := customTool(t); ok {
			c := map[string]any{"name": name, "description": description}
			if f, ok := format.(map[string]any); ok && f["type"] == "grammar" && f["grammar"] == nil {
				format = map[string]any{
					"type":    "grammar",
					"grammar": map[string]any{"definition": f["definition"], "syntax": f["syntax"]},
				}
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

func AnthropicMessages(ctx Context, path []Message, targets []Hash) (map[string]any, error) {
	e, err := ctx.effective()
	if err != nil {
		return nil, err
	}
	own := set(targets)
	system := append([]string{}, e.system...)
	dropped := hosted(path)
	var out []map[string]any
	target, split := false, false
	add := func(role string, blocks []any) {
		if len(blocks) == 0 {
			return
		}
		if n := len(out); n > 0 && out[n-1]["role"] == role && !split {
			out[n-1]["content"] = append(out[n-1]["content"].([]any), blocks...)
			return
		}
		split = false
		out = append(out, map[string]any{"role": role, "content": blocks})
	}
	for _, m := range path {
		if own[m.ID] && !target {
			split = true
		}
		target = own[m.ID]
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
				name, err := e.name(b, target)
				if err != nil {
					return nil, err
				}
				var input any = map[string]any{}
				switch {
				case isCustomCall(b):
					input = map[string]any{"input": b.ToolInput}
				case json.Valid([]byte(b.ToolInput)):
					input = json.RawMessage(b.ToolInput)
				case b.ToolInput != "":
					input = map[string]any{"input": b.ToolInput}
				}
				blocks = append(blocks, map[string]any{"type": "tool_use", "id": b.ToolCallID, "name": name, "input": input})
			case "tool_result":
				if dropped[b.ToolCallID] {
					continue
				}
				result := map[string]any{
					"type": "tool_result", "tool_use_id": b.ToolCallID,
					"content": b.Text, "is_error": b.IsError,
				}
				if role == "assistant" {
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
		} else if description, _, ok := customTool(t); ok {
			tools = append(tools, map[string]any{
				"name": name, "description": description,
				"input_schema": map[string]any{
					"type": "object", "required": []any{"input"},
					"properties": map[string]any{"input": map[string]any{"type": "string"}},
				},
			})
		}
	}
	if len(tools) > 0 {
		request["tools"] = tools
	}
	return request, nil
}

func ForTraining(ctx Context, path []Message, outputs []Hash) error {
	e, err := ctx.effective()
	if err != nil {
		return err
	}
	defined := map[string]bool{}
	for _, t := range e.tools {
		defined[t.name] = true
	}
	own := set(outputs)
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
		return errors.New("the call's outputs are not on its conversation")
	}
	if kept == 0 {
		return errors.New("the call produced no output to train on")
	}
	return nil
}

func set(ids []Hash) map[Hash]bool {
	s := map[Hash]bool{}
	for _, id := range ids {
		s[id] = true
	}
	return s
}

func join(prior any, s string) string {
	p, _ := prior.(string)
	if p == "" {
		return s
	}
	return p + "\n\n" + s
}
