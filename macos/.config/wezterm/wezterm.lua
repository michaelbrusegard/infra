-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- ********************************************************************************
-- * General                                                                      *
-- ********************************************************************************

-- Keep wezterm running when all windows are closed
config.quit_when_all_windows_are_closed = false

-- Don't adjust window size because of tiling window manager
config.adjust_window_size_when_changing_font_size = true

-- Use kitty keyboard protocol over csi-u
config.enable_kitty_keyboard = true
config.enable_csi_u_key_encoding = false

-- ********************************************************************************
-- * Appearance                                                                   *
-- ********************************************************************************

-- Colors
local colors = {
	rosewater = "#f5e0dc",
	flamingo = "#f2cdcd",
	pink = "#f5c2e7",
	mauve = "#cba6f7",
	red = "#f38ba8",
	maroon = "#eba0ac",
	peach = "#fab387",
	yellow = "#f9e2af",
	green = "#a6e3a1",
	teal = "#94e2d5",
	sky = "#89dceb",
	sapphire = "#74c7ec",
	blue = "#89b4fa",
	lavender = "#b4befe",
	text = "#cdd6f4",
	subtext1 = "#bac2de",
	subtext0 = "#a6adc8",
	overlay2 = "#9399b2",
	overlay1 = "#7f849c",
	overlay0 = "#6c7086",
	surface2 = "#585b70",
	surface1 = "#45475a",
	surface0 = "#313244",
	base = "#1e1e2e",
	mantle = "#181825",
	crust = "#11111b",
}

-- Color scheme
config.color_scheme = "Catppuccin Mocha"

-- Font style without ligatures
config.font = wezterm.font_with_fallback({
	{
		family = "MesloLGS Nerd Font",
		harfbuzz_features = { "calt=0", "clig=0", "liga=0" },
	},
})

-- Font size
config.font_size = 13.0

-- Disable window resize UI
config.window_decorations = "RESIZE"

-- Disable window padding
config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

-- ********************************************************************************
-- * Tab bar                                                                      *
-- ********************************************************************************

-- Set terminal style for tab bar
config.use_fancy_tab_bar = false

-- Hide new tab button
config.show_new_tab_button_in_tab_bar = false

-- Increase max tab width
config.tab_max_width = 32

-- Set tab bar background
config.colors = {
	tab_bar = {
		background = colors.mantle,
	},
}

-- Format tabs
wezterm.on("format-tab-title", function(tab)
	local cwd_uri = tab.active_pane.current_working_dir
	local cwd = ""
	local parent = ""

	if cwd_uri then
		local file_path = cwd_uri.file_path
		if file_path then
			local parts = {}
			for part in string.gmatch(file_path, "([^/]+)") do
				table.insert(parts, part)
			end
			cwd = parts[#parts] or ""
			parent = parts[#parts - 1] or ""
		end
	end

	local title = tab.active_pane.title
	if tab.is_active then
		if parent ~= "" then
			title = parent .. "/" .. cwd
		else
			title = cwd
		end
	end

	if title == "" then
		title = tab.active_pane.title
	end

	return {
		{ Attribute = { Intensity = "Bold" } },
		{ Foreground = { Color = colors.mantle } },
		{ Background = { Color = tab.is_active and colors.peach or colors.blue } },
		{ Text = " " .. (tab.tab_index + 1) .. " " },
		"ResetAttributes",
		{ Foreground = { Color = tab.is_active and colors.text or colors.subtext0 } },
		{ Background = { Color = tab.is_active and colors.surface1 or colors.surface0 } },
		{ Text = " " .. title .. " " },
	}
end)

-- Right side status
wezterm.on("update-status", function(window, pane)
	local cwd_uri = pane:get_current_working_dir()
	local hostname = ""

	if cwd_uri then
		if type(cwd_uri) == "userdata" then
			hostname = cwd_uri.host or wezterm.hostname()
		else
			cwd_uri = cwd_uri:sub(8)
			local slash = cwd_uri:find("/")
			if slash then
				hostname = cwd_uri:sub(1, slash - 1)
			end
		end
		local dot = hostname:find("[.]")
		if dot then
			hostname = hostname:sub(1, dot - 1)
		end
		if hostname == "" then
			hostname = wezterm.hostname()
		end
	else
		hostname = wezterm.hostname()
	end

	local status_elements = {
		{ Foreground = { Color = colors.mantle } },
		{ Background = { Color = colors.green } },
		{ Text = "  " },
		{ Foreground = { Color = colors.text } },
		{ Background = { Color = colors.surface0 } },
		{ Text = " " .. hostname .. " " },
	}
	window:set_right_status(wezterm.format(status_elements))
end)

-- ********************************************************************************
-- * Smart Splits                                                                 *
-- ********************************************************************************

-- Check if the pane contains vim
local function is_vim(pane)
	return pane:get_user_vars().IS_NVIM == "true"
end

-- Keymaps for vim when using super key
local vim_super_keymaps = {
	["SUPER_h"] = utf8.char(0xAA),
	["SUPER_j"] = utf8.char(0xAB),
	["SUPER_k"] = utf8.char(0xAC),
	["SUPER_l"] = utf8.char(0xAD),
	["SUPER|CTRL_h"] = utf8.char(0xBA),
	["SUPER|CTRL_j"] = utf8.char(0xBB),
	["SUPER|CTRL_k"] = utf8.char(0xBC),
	["SUPER|CTRL_l"] = utf8.char(0xBD),
	["SUPER_c"] = utf8.char(0xCA),
	["SUPER_v"] = utf8.char(0xCB),
}

local direction_keys = {
	h = "Left",
	j = "Down",
	k = "Up",
	l = "Right",
}

-- Translate keybinds to be sent to vim if needed
local function vim_super_keymap_translation(key, mods)
	return {
		key = key,
		mods = mods,
		action = wezterm.action_callback(function(window, pane)
			if is_vim(pane) then
				local char = vim_super_keymaps[mods .. "_" .. key]
				if char then
					window:perform_action({
						SendKey = { key = char, mods = nil },
					}, pane)
				end
			else
				if key == "c" then
					window:perform_action(wezterm.action.CopyTo("Clipboard"), pane)
				elseif key == "v" then
					window:perform_action(wezterm.action.PasteFrom("Clipboard"), pane)
				else
					if mods == "SUPER|CTRL" then
						window:perform_action({ AdjustPaneSize = { direction_keys[key], 3 } }, pane)
					else
						window:perform_action({ ActivatePaneDirection = direction_keys[key] }, pane)
					end
				end
			end
		end),
	}
end

-- ********************************************************************************
-- * Keybinds                                                                     *
-- ********************************************************************************

-- Disable default bindings
config.disable_default_key_bindings = true

config.keys = {
	-- Global keys
	vim_super_keymap_translation("c", "SUPER"),
	vim_super_keymap_translation("v", "SUPER"),

	-- Smart splits
	vim_super_keymap_translation("h", "SUPER"),
	vim_super_keymap_translation("j", "SUPER"),
	vim_super_keymap_translation("k", "SUPER"),
	vim_super_keymap_translation("l", "SUPER"),
	vim_super_keymap_translation("h", "SUPER|CTRL"),
	vim_super_keymap_translation("j", "SUPER|CTRL"),
	vim_super_keymap_translation("k", "SUPER|CTRL"),
	vim_super_keymap_translation("l", "SUPER|CTRL"),

	-- Navigation between tabs
	{ key = "Tab", mods = "CTRL", action = wezterm.action.ActivateTabRelative(1) },
	{ key = "Tab", mods = "SHIFT|CTRL", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "[", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "]", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(1) },
	{ key = "{", mods = "SUPER", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "{", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "}", mods = "SUPER", action = wezterm.action.ActivateTabRelative(1) },
	{ key = "}", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(1) },
	{ key = "1", mods = "SUPER", action = wezterm.action.ActivateTab(0) },
	{ key = "2", mods = "SUPER", action = wezterm.action.ActivateTab(1) },
	{ key = "3", mods = "SUPER", action = wezterm.action.ActivateTab(2) },
	{ key = "4", mods = "SUPER", action = wezterm.action.ActivateTab(3) },
	{ key = "5", mods = "SUPER", action = wezterm.action.ActivateTab(4) },
	{ key = "6", mods = "SUPER", action = wezterm.action.ActivateTab(5) },
	{ key = "7", mods = "SUPER", action = wezterm.action.ActivateTab(6) },
	{ key = "8", mods = "SUPER", action = wezterm.action.ActivateTab(7) },
	{ key = "9", mods = "SUPER", action = wezterm.action.ActivateTab(-1) },

	-- Swaping and splitting into new panes
	{ key = "0", mods = "SUPER", action = wezterm.action.PaneSelect({ mode = "SwapWithActive" }) },
	{ key = "-", mods = "SUPER", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "=", mods = "SUPER", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },

	-- Basic actions
	{ key = "f", mods = "SUPER", action = wezterm.action.Search("CurrentSelectionOrEmptyString") },
	{ key = "Enter", mods = "SUPER", action = wezterm.action.ActivateCopyMode },
	{ key = "z", mods = "SUPER", action = wezterm.action.TogglePaneZoomState },
	{ key = "r", mods = "SUPER", action = wezterm.action.ReloadConfiguration },

	-- Application actions
	{ key = "m", mods = "SUPER", action = wezterm.action.Hide },
	{ key = "q", mods = "SUPER", action = wezterm.action.QuitApplication },
	{ key = "n", mods = "SUPER", action = wezterm.action.SpawnWindow },
	{ key = "t", mods = "SUPER", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "SHIFT|SUPER", action = wezterm.action.CloseCurrentTab({ confirm = true }) },
	{ key = "w", mods = "SUPER", action = wezterm.action.CloseCurrentPane({ confirm = false }) },
}

config.key_tables = {
	copy_mode = {
		{ key = "Tab", mods = "NONE", action = wezterm.action.CopyMode("MoveForwardWord") },
		{ key = "Tab", mods = "SHIFT", action = wezterm.action.CopyMode("MoveBackwardWord") },
		{ key = "Enter", mods = "NONE", action = wezterm.action.CopyMode("MoveToStartOfNextLine") },
		{ key = "Escape", mods = "NONE", action = wezterm.action.CopyMode("Close") },
		{ key = "Space", mods = "NONE", action = wezterm.action.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "$", mods = "NONE", action = wezterm.action.CopyMode("MoveToEndOfLineContent") },
		{ key = "$", mods = "SHIFT", action = wezterm.action.CopyMode("MoveToEndOfLineContent") },
		{ key = ",", mods = "NONE", action = wezterm.action.CopyMode("JumpReverse") },
		{ key = "0", mods = "NONE", action = wezterm.action.CopyMode("MoveToStartOfLine") },
		{ key = ";", mods = "NONE", action = wezterm.action.CopyMode("JumpAgain") },
		{ key = "F", mods = "NONE", action = wezterm.action.CopyMode({ JumpBackward = { prev_char = false } }) },
		{ key = "F", mods = "SHIFT", action = wezterm.action.CopyMode({ JumpBackward = { prev_char = false } }) },
		{ key = "G", mods = "NONE", action = wezterm.action.CopyMode("MoveToScrollbackBottom") },
		{ key = "G", mods = "SHIFT", action = wezterm.action.CopyMode("MoveToScrollbackBottom") },
		{ key = "H", mods = "NONE", action = wezterm.action.CopyMode("MoveToViewportTop") },
		{ key = "H", mods = "SHIFT", action = wezterm.action.CopyMode("MoveToViewportTop") },
		{ key = "L", mods = "NONE", action = wezterm.action.CopyMode("MoveToViewportBottom") },
		{ key = "L", mods = "SHIFT", action = wezterm.action.CopyMode("MoveToViewportBottom") },
		{ key = "M", mods = "NONE", action = wezterm.action.CopyMode("MoveToViewportMiddle") },
		{ key = "M", mods = "SHIFT", action = wezterm.action.CopyMode("MoveToViewportMiddle") },
		{ key = "O", mods = "NONE", action = wezterm.action.CopyMode("MoveToSelectionOtherEndHoriz") },
		{ key = "O", mods = "SHIFT", action = wezterm.action.CopyMode("MoveToSelectionOtherEndHoriz") },
		{ key = "T", mods = "NONE", action = wezterm.action.CopyMode({ JumpBackward = { prev_char = true } }) },
		{ key = "T", mods = "SHIFT", action = wezterm.action.CopyMode({ JumpBackward = { prev_char = true } }) },
		{ key = "V", mods = "NONE", action = wezterm.action.CopyMode({ SetSelectionMode = "Line" }) },
		{ key = "V", mods = "SHIFT", action = wezterm.action.CopyMode({ SetSelectionMode = "Line" }) },
		{ key = "^", mods = "NONE", action = wezterm.action.CopyMode("MoveToStartOfLineContent") },
		{ key = "^", mods = "SHIFT", action = wezterm.action.CopyMode("MoveToStartOfLineContent") },
		{ key = "b", mods = "NONE", action = wezterm.action.CopyMode("MoveBackwardWord") },
		{ key = "b", mods = "ALT", action = wezterm.action.CopyMode("MoveBackwardWord") },
		{ key = "b", mods = "CTRL", action = wezterm.action.CopyMode("PageUp") },
		{ key = "c", mods = "CTRL", action = wezterm.action.CopyMode("Close") },
		{ key = "d", mods = "CTRL", action = wezterm.action.CopyMode({ MoveByPage = 0.5 }) },
		{ key = "e", mods = "NONE", action = wezterm.action.CopyMode("MoveForwardWordEnd") },
		{ key = "f", mods = "NONE", action = wezterm.action.CopyMode({ JumpForward = { prev_char = false } }) },
		{ key = "f", mods = "ALT", action = wezterm.action.CopyMode("MoveForwardWord") },
		{ key = "f", mods = "CTRL", action = wezterm.action.CopyMode("PageDown") },
		{ key = "g", mods = "NONE", action = wezterm.action.CopyMode("MoveToScrollbackTop") },
		{ key = "g", mods = "CTRL", action = wezterm.action.CopyMode("Close") },
		{ key = "h", mods = "NONE", action = wezterm.action.CopyMode("MoveLeft") },
		{ key = "j", mods = "NONE", action = wezterm.action.CopyMode("MoveDown") },
		{ key = "k", mods = "NONE", action = wezterm.action.CopyMode("MoveUp") },
		{ key = "l", mods = "NONE", action = wezterm.action.CopyMode("MoveRight") },
		{ key = "m", mods = "ALT", action = wezterm.action.CopyMode("MoveToStartOfLineContent") },
		{ key = "o", mods = "NONE", action = wezterm.action.CopyMode("MoveToSelectionOtherEnd") },
		{ key = "q", mods = "NONE", action = wezterm.action.CopyMode("Close") },
		{ key = "t", mods = "NONE", action = wezterm.action.CopyMode({ JumpForward = { prev_char = true } }) },
		{ key = "u", mods = "CTRL", action = wezterm.action.CopyMode({ MoveByPage = -0.5 }) },
		{ key = "v", mods = "NONE", action = wezterm.action.CopyMode({ SetSelectionMode = "Cell" }) },
		{ key = "v", mods = "CTRL", action = wezterm.action.CopyMode({ SetSelectionMode = "Block" }) },
		{ key = "w", mods = "NONE", action = wezterm.action.CopyMode("MoveForwardWord") },
		{
			key = "y",
			mods = "NONE",
			action = wezterm.action.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
		},
		{ key = "PageUp", mods = "NONE", action = wezterm.action.CopyMode("PageUp") },
		{ key = "PageDown", mods = "NONE", action = wezterm.action.CopyMode("PageDown") },
		{ key = "End", mods = "NONE", action = wezterm.action.CopyMode("MoveToEndOfLineContent") },
		{ key = "Home", mods = "NONE", action = wezterm.action.CopyMode("MoveToStartOfLine") },
	},

	search_mode = {
		{ key = "Enter", mods = "NONE", action = wezterm.action.CopyMode("PriorMatch") },
		{ key = "Escape", mods = "NONE", action = wezterm.action.CopyMode("Close") },
		{ key = "n", mods = "CTRL", action = wezterm.action.CopyMode("NextMatch") },
		{ key = "p", mods = "CTRL", action = wezterm.action.CopyMode("PriorMatch") },
		{ key = "r", mods = "CTRL", action = wezterm.action.CopyMode("CycleMatchType") },
		{ key = "u", mods = "CTRL", action = wezterm.action.CopyMode("ClearPattern") },
		{ key = "PageUp", mods = "NONE", action = wezterm.action.CopyMode("PriorMatchPage") },
		{ key = "PageDown", mods = "NONE", action = wezterm.action.CopyMode("NextMatchPage") },
	},
}

-- Finally, return the configuration to wezterm
return config
