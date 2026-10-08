--- @since 26.8.15

local TITLE = "Difftool"

local DEFAULTS = {
	-- Tool to use when none is passed with `--tool`; nil lets git decide (`diff.tool`)
	tool = nil,
	-- Candidates offered by `--pick`
	tools = { "meld", "vscode", "bc", "vimdiff", "nvimdiff" },
	-- Tools that can't compare directories; directory pairs fall back to one diff per changed file
	per_file_tools = { "vscode" },
	-- Tools that run inside the terminal, so Yazi has to hide its UI while they run
	terminal_tools = { "vimdiff", "vimdiff1", "vimdiff2", "vimdiff3", "nvimdiff", "emerge" },
}

local function notify(level, s, ...)
	ya.notify {
		title = TITLE,
		content = string.format(s, ...),
		level = level,
		timeout = 5,
	}
end

local function contains(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local get_opts = ya.sync(function(state)
	local opts = {}
	for k, v in pairs(DEFAULTS) do
		if state[k] == nil then
			opts[k] = v
		else
			opts[k] = state[k]
		end
	end
	return opts
end)

local function entry_of(f)
	return f and { path = f.path and tostring(f.path), is_dir = f.cha.is_dir }
end

-- Picks the two things to compare:
--   2 selected                 -> those two, in selection order
--   1 selected + hovered       -> selected vs hovered
--   nothing selected, 2+ tabs  -> hovered in this tab vs hovered in the next tab (lower tab number on the left)
local get_targets = ya.sync(function()
	local tab, targets = cx.active, {}
	for _, f in pairs(tab.selected) do
		targets[#targets + 1] = entry_of(f)
	end

	if #targets == 1 then
		local h = entry_of(tab.current.hovered)
		if h and h.path ~= targets[1].path then
			targets[2] = h
		end
	elseif #targets == 0 and #cx.tabs > 1 then
		local next_idx = cx.tabs.idx % #cx.tabs + 1
		local a, b = entry_of(tab.current.hovered), entry_of(cx.tabs[next_idx].current.hovered)
		if next_idx < cx.tabs.idx then
			a, b = b, a
		end
		if a and b then
			targets = { a, b }
		end
	end
	return targets
end)

-- The tool git would use when none is given, so we know whether it's a terminal tool
local function configured_tool()
	for _, key in ipairs { "diff.tool", "merge.tool" } do
		local output = Command("git"):arg { "config", "--get", key }:output()
		local value = output and output.status.success and output.stdout:gsub("%s+$", "")
		if value and value ~= "" then
			return value
		end
	end
end

local function pick_tool(tools)
	local cands = {}
	for i, t in ipairs(tools) do
		cands[i] = { on = i <= 9 and tostring(i) or string.char(string.byte("a") + i - 10), desc = t }
	end
	local idx = ya.which { cands = cands }
	return idx and tools[idx]
end

local function build_command(tool, a, b, per_file)
	local cmd
	if per_file then
		cmd = Command("git"):arg { "difftool", "--no-index", "--no-prompt" }
		if tool then
			cmd = cmd:arg("--tool=" .. tool)
		end
		cmd = cmd:arg { "--", a, b }
	else
		-- git's own launcher for `difftool --dir-diff`: opens the tool once on two paths,
		-- honouring diff.tool, difftool.<tool>.path/cmd and the built-in tool definitions
		cmd = Command("git"):arg { "difftool--helper", a, b }:env("GIT_DIFFTOOL_DIRDIFF", "true")
		if tool then
			cmd = cmd:env("GIT_DIFF_TOOL", tool)
		end
	end
	return cmd:env("GIT_DIFFTOOL_NO_PROMPT", "true")
end

local function run_in_terminal(cmd)
	local permit = ui.hide()
	local status, err = cmd:stdin(Command.INHERIT):stdout(Command.INHERIT):stderr(Command.INHERIT):status()
	permit:drop()
	if not status then
		return notify("error", "Failed to run git: %s", err)
	end
	-- `git diff --no-index` (per-file mode) exits 1 when the inputs differ
	if status.code ~= 0 and status.code ~= 1 then
		notify("error", "Difftool exited with code %s", status.code)
	end
end

local function run_detached(cmd)
	local output, err = cmd:stdin(Command.NULL):stdout(Command.PIPED):stderr(Command.PIPED):output()
	if not output then
		return notify("error", "Failed to run git: %s", err)
	end
	local code = output.status.code
	if code ~= 0 and code ~= 1 then
		local msg = output.stderr ~= "" and output.stderr or output.stdout
		notify("error", "Difftool failed (exit %s):\n%s", code, msg:gsub("%s+$", ""))
	elseif code == 1 and output.stderr:find("%S") then
		-- difftool--helper reports config problems (e.g. unknown tool) with exit 1
		notify("error", "%s", output.stderr:gsub("%s+$", ""))
	end
end

return {
	setup = function(state, opts)
		for k, v in pairs(opts or {}) do
			state[k] = v
		end
	end,

	entry = function(_, job)
		ya.emit("escape", { visual = true })

		local targets = get_targets()
		if #targets ~= 2 then
			return notify(
				"warn",
				"Select exactly 2 files/directories, or select 1 and hover another, "
					.. "or hover one in each of two tabs (got %d)",
				#targets
			)
		end

		local a, b = targets[1], targets[2]
		if not a.path or not b.path then
			return notify("error", "Only local files can be compared")
		elseif a.is_dir ~= b.is_dir then
			return notify("error", "Can't compare a file with a directory")
		end

		local opts = get_opts()
		local tool = job.args.tool
		if not tool and job.args.pick then
			tool = pick_tool(opts.tools)
			if not tool then
				return
			end
		end
		tool = tool or opts.tool or configured_tool()

		local per_file = a.is_dir and tool ~= nil and contains(opts.per_file_tools, tool)
		local cmd = build_command(tool, a.path, b.path, per_file)

		if tool and contains(opts.terminal_tools, tool) then
			run_in_terminal(cmd)
		else
			run_detached(cmd)
		end
	end,
}
