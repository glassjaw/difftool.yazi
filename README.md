# difftool.yazi

A [Yazi](https://github.com/sxyazi/yazi) plugin for comparing two files or two directories in the difftool you already set up for git: Meld, VS Code, Beyond Compare, vimdiff, or any custom `difftool.<name>.cmd`.

It doesn't hard-code any tool commands. It asks git to launch the tool, so each machine uses its own `diff.tool` setting. Directories open as a single folder comparison when the tool supports it.

## Requirements

- Yazi 26.8.15 or newer
- git, with a difftool configured (see [Configuring git](#configuring-git))

## Installation

```sh
ya pkg add glassjaw/difftool
```

## Usage

Add to `~/.config/yazi/keymap.toml`:

```toml
[mgr]
prepend_keymap = [
	{ on = [ "=", "=" ], run = "plugin difftool",                desc = "Diff 2 selected files/dirs with git difftool" },
	{ on = [ "=", "t" ], run = "plugin difftool -- --pick",      desc = "Diff 2 selected files/dirs, choosing the tool" },
	# Or always use a specific tool:
	# { on = [ "=", "m" ], run = "plugin difftool -- --tool=meld", desc = "Diff with Meld" },
]
```

Then pick what to compare in one of three ways:

| You have…                                   | Compared                                       |
| ------------------------------------------- | ---------------------------------------------- |
| 2 items selected (any directories)          | the two selected items, in selection order     |
| 1 item selected and a different one hovered | selected (left) vs hovered (right)             |
| nothing selected and 2+ tabs open           | hovered in this tab vs hovered in the next tab |

Yazi keeps a tab's selection when you change directory. So you can select a file in one folder, go to another folder, select a second file, and press `==`.

Both sides must be files or both must be directories.

### Arguments

| Argument      | Effect                                                     |
| ------------- | ---------------------------------------------------------- |
| `--tool=NAME` | Use this git difftool instead of the configured `diff.tool` |
| `--pick`      | Choose the tool from a menu (the `tools` list, see below)  |

## Configuring git

Set the tool once per machine. Run `git difftool --tool-help` to see what git knows about.

```sh
# Meld
git config --global diff.tool meld

# Visual Studio Code (needs `code` on your PATH)
git config --global diff.tool vscode

# Beyond Compare ("bc" works for v3, v4 and later)
git config --global diff.tool bc
git config --global difftool.bc.path "/path/to/bcompare"   # only if bcompare is not on PATH
```

On Windows, `difftool.bc.path` is usually `C:/Program Files/Beyond Compare 4/BCompare.exe`.

For a tool git doesn't know about:

```sh
git config --global diff.tool mytool
git config --global difftool.mytool.cmd 'mytool "$LOCAL" "$REMOTE"'
```

## Options

All of these are optional. Add to `~/.config/yazi/init.lua`:

```lua
require("difftool"):setup {
	-- Tool to use when no --tool is given. nil uses git's diff.tool.
	tool = nil,
	-- Choices shown by --pick
	tools = { "meld", "vscode", "bc", "vimdiff", "nvimdiff" },
	-- Tools that can't compare directories. For these, a directory pair
	-- opens one diff per changed file instead (VS Code's --diff only takes files).
	per_file_tools = { "vscode" },
	-- Tools that run inside the terminal. Yazi hides its UI until they exit.
	terminal_tools = { "vimdiff", "vimdiff1", "vimdiff2", "vimdiff3", "nvimdiff", "emerge" },
}
```

## How it works

`git difftool --no-index` would open the tool once per changed file. Git also refuses `--dir-diff` together with `--no-index`. So the plugin calls git's own launcher directly, the same way `git difftool --dir-diff` does internally:

```sh
GIT_DIFFTOOL_DIRDIFF=true GIT_DIFF_TOOL=<tool> git difftool--helper <left> <right>
```

That opens the tool once on the two paths. It follows `diff.tool`, `difftool.<tool>.path` and `difftool.<tool>.cmd`, and uses git's built-in tool definitions. For tools in `per_file_tools`, directory pairs instead run `git difftool --no-index --no-prompt --tool=<tool>`.

GUI tools run in the background, so you can keep using Yazi while the diff is open. If git reports an error, such as an unknown tool, it appears as a Yazi notification.

## License

MIT
