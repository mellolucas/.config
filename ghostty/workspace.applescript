-- Ghostty workspace layout.
--
-- Usage:
--   osascript workspace.applescript WORKSPACE_DIR EDITOR_CMD AGENT_CMD MIDDLE_TOP_CMD MIDDLE_BOTTOM_CMD CONTENT_WIDTH CONTENT_HEIGHT
--
-- Opens as a new tab in the frontmost Ghostty window (new window when none).
-- CONTENT_WIDTH/CONTENT_HEIGHT are the window text area in pixels (CSI 14 t);
-- when missing or 0 the splits are equalized instead of ratio-sized.
--
-- Layout (columns 20% / 40% / 40%, middle column rows 30% / 70%):
--
--   ┌────────┬───────────────┬───────────────┐
--   │        │               │               │
--   │        │   shell       │               │
--   │        │               │               │
--   │ editor ├───────────────┤   agent       │
--   │        │               │               │
--   │        │   shell       │               │
--   │        │               │               │
--   └────────┴───────────────┴───────────────┘

on run argv
	if (count of argv) < 3 then
		error "usage: workspace.applescript WORKSPACE_DIR EDITOR_CMD AGENT_CMD [MIDDLE_TOP_CMD] [MIDDLE_BOTTOM_CMD] [CONTENT_WIDTH] [CONTENT_HEIGHT]"
	end if
	
	set workspaceDir to item 1 of argv
	set editorCmd to item 2 of argv
	set agentCmd to item 3 of argv
	
	set middleTopCmd to ""
	set middleBottomCmd to ""
	set contentWidth to 0
	set contentHeight to 0
	
	if (count of argv) ≥ 4 then set middleTopCmd to item 4 of argv
	if (count of argv) ≥ 5 then set middleBottomCmd to item 5 of argv
	if (count of argv) ≥ 6 then set contentWidth to (item 6 of argv) as integer
	if (count of argv) ≥ 7 then set contentHeight to (item 7 of argv) as integer
	
	-- One divider move per axis reaches the target ratios: resize_split moves
	-- the divider of the pane's nearest ancestor split, and nested splits
	-- redistribute proportionally, so 50/25/25 -> 20/40/40 and 50/50 -> 30/70.
	set widthDelta to round (contentWidth * 0.3)
	set heightDelta to round (contentHeight * 0.2)
	
	tell application "Ghostty"
		activate

		set cfg to new surface configuration
		set initial working directory of cfg to workspaceDir
		
		if (count of windows) > 0 then
			set workspaceTab to new tab in front window with configuration cfg
		else
			set workspaceTab to selected tab of (new window with configuration cfg)
		end if
		
		set middleTop to focused terminal of workspaceTab
		set leftEditor to split middleTop direction left with configuration cfg
		set rightAgent to split middleTop direction right with configuration cfg
		set middleBottom to split middleTop direction down with configuration cfg
		
		if widthDelta > 0 and heightDelta > 0 then
			perform action ("resize_split:left," & widthDelta) on leftEditor
			perform action ("resize_split:up," & heightDelta) on middleBottom
		else
			perform action "equalize_splits" on middleTop
		end if

		input text editorCmd to leftEditor
		send key "enter" to leftEditor
		
		input text agentCmd to rightAgent
		send key "enter" to rightAgent
		
		if middleTopCmd is not "" then
			input text middleTopCmd to middleTop
			send key "enter" to middleTop
		end if
		
		if middleBottomCmd is not "" then
			input text middleBottomCmd to middleBottom
			send key "enter" to middleBottom
		end if
		
		focus middleBottom
	end tell
end run
