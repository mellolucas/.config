-- Ghostty workspace layout.
--
-- Usage:
--   osascript workspace.applescript WORKSPACE_DIR EDITOR_CMD AGENT_CMD STATUS_CMD SHELL_CMD CONTENT_WIDTH CONTENT_HEIGHT LAYOUT MARK
--
-- When the focused pane's title is MARK (the invoking shell titles its own
-- pane) and it is its tab's only pane, lays out that tab, the pane becoming
-- the main shell; otherwise opens a new tab in the frontmost Ghostty window
-- (new window when none). Prints "same tab" or "new tab".
-- CONTENT_WIDTH/CONTENT_HEIGHT are the window text area in pixels (CSI 14 t);
-- when missing or 0 the full layout's splits are equalized instead of
-- ratio-sized. LAYOUT is full (the default) or lean.
--
-- full (columns 20% / 40% / 40%, middle column rows 30% / 70%):
--
--   ┌────────┬───────────────┬───────────────┐
--   │        │ status shell  │               │
--   │        ├───────────────┤               │
--   │ editor │               │   agent       │
--   │        │  main shell   │               │
--   │        │               │               │
--   └────────┴───────────────┴───────────────┘
--
-- lean (even halves; the shell runs the status command, then the shell one):
--
--   ┌──────────────────┬──────────────────┐
--   │      editor      │                  │
--   ├──────────────────┤      agent       │
--   │      shell       │                  │
--   └──────────────────┴──────────────────┘

use AppleScript version "2.4"
use framework "AppKit"
use scripting additions

on run argv
	if (count of argv) < 3 then
		error "usage: workspace.applescript WORKSPACE_DIR EDITOR_CMD AGENT_CMD [STATUS_CMD] [SHELL_CMD] [CONTENT_WIDTH] [CONTENT_HEIGHT] [LAYOUT] [MARK]"
	end if

	set workspaceDir to item 1 of argv
	set editorCmd to item 2 of argv
	set agentCmd to item 3 of argv

	set statusCmd to ""
	set shellCmd to ""
	set contentWidth to 0
	set contentHeight to 0
	set layoutName to "full"
	set markTitle to ""

	if (count of argv) ≥ 4 then set statusCmd to item 4 of argv
	if (count of argv) ≥ 5 then set shellCmd to item 5 of argv
	if (count of argv) ≥ 6 then set contentWidth to (item 6 of argv) as integer
	if (count of argv) ≥ 7 then set contentHeight to (item 7 of argv) as integer
	if (count of argv) ≥ 8 then set layoutName to item 8 of argv
	if (count of argv) ≥ 9 then set markTitle to item 9 of argv

	-- One divider move per axis reaches the target ratios: resize_split moves
	-- the divider of the pane's nearest ancestor split, and nested splits
	-- redistribute proportionally, so 50/25/25 -> 20/40/40 and 50/50 -> 30/70.
	-- CSI 14 t counts device pixels but resize_split moves points; with mixed
	-- displays the largest scale errs toward smaller moves.
	set pixelsPerPoint to 1
	repeat with screen in (current application's NSScreen's screens() as list)
		set screenScale to (screen's backingScaleFactor()) as real
		if screenScale > pixelsPerPoint then set pixelsPerPoint to screenScale
	end repeat
	set widthDelta to round (contentWidth * 0.3 / pixelsPerPoint)
	set heightDelta to round (contentHeight * 0.2 / pixelsPerPoint)

	tell application "Ghostty"
		activate

		set cfg to new surface configuration
		set initial working directory of cfg to workspaceDir

		-- Ghostty applies a new title within about 75 ms
		set mainShell to missing value
		if markTitle is not "" and (count of windows) > 0 then
			try
				repeat 10 times
					set sourceTab to selected tab of front window
					set sourceTerminal to focused terminal of sourceTab
					if name of sourceTerminal is markTitle then
						if (count of terminals of sourceTab) is 1 then set mainShell to sourceTerminal
						exit repeat
					end if
					delay 0.05
				end repeat
			end try
		end if

		if mainShell is not missing value then
			set placement to "same tab"
		else
			set placement to "new tab"
			if (count of windows) > 0 then
				set workspaceTab to new tab in front window with configuration cfg
			else
				set workspaceTab to selected tab of (new window with configuration cfg)
			end if
			set mainShell to focused terminal of workspaceTab
		end if

		-- The other panes split from the main shell
		if layoutName is "lean" then
			-- Splits halve the pane they divide, so no resizing
			set rightAgent to split mainShell direction right with configuration cfg
			set leftEditor to split mainShell direction up with configuration cfg
			set statusShell to mainShell
		else
			set leftEditor to split mainShell direction left with configuration cfg
			set rightAgent to split mainShell direction right with configuration cfg
			set statusShell to split mainShell direction up with configuration cfg

			if widthDelta > 0 and heightDelta > 0 then
				perform action ("resize_split:left," & widthDelta) on leftEditor
				perform action ("resize_split:up," & heightDelta) on mainShell
			else
				perform action "equalize_splits" on mainShell
			end if
		end if

		input text editorCmd to leftEditor
		send key "enter" to leftEditor

		input text agentCmd to rightAgent
		send key "enter" to rightAgent

		if statusCmd is not "" then
			input text statusCmd to statusShell
			send key "enter" to statusShell
		end if

		if shellCmd is not "" then
			input text shellCmd to mainShell
			send key "enter" to mainShell
		end if

		focus mainShell
	end tell
	return placement
end run
