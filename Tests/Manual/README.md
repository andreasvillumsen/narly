# Narly: manual macOS test app

`NarlyQA.swift` is a small AppKit test app with no user data. Run
`bash scripts/run-manual-tests.sh` to build Narly Dev and the QA bundle, then
launch the QA app targeting this checkout's Dev bundle. Use
`bash scripts/run-manual-tests.sh --release` to explicitly test a release build.
Neither mode changes the default browser or installs an app in Applications.
Add `--build-only` to compile and validate without launching.

The QA bundle uses `app.narlymac.qa`. Without an explicit `--app-path` launch
argument, it looks up `app.narlymac.dev`; it never falls back to the default browser.
The window title identifies the selected app.

- **Send Test Link** targets the selected build with a neutral example.com link.
- **Send 10 Links** sends ten URLs to the same build in one delivery. Copy them
  one at a time and check their order.
- **Test Outside Click** counts received clicks. Move the pointer away from the
  button before the link panel appears so the button is outside the panel.
  One click should both dismiss the picker and increment the counter by one.
- **Full Screen** uses NSWindow’s public fullscreen API. Repeat link delivery,
  cold launch, Escape, copying and opening Narly’s Settings from the new Space.

The test app uses the normal `.regular` activation policy. Keep private browser
URLs, clipboard contents and screenshots out of the repository. Only close
test tabs identified by the neutral test addresses.

## Search-pill motion

Build Narly Dev with `./script/build_and_run.sh`. For frame-by-frame inspection,
quit that development app and reopen the generated `.app` bundle with
`open -n "<generated app path>" --args --slow-search-exit`.
This debug-only flag runs the same 80 ms native exit at one-tenth speed; release
builds ignore it. Relaunch without the flag to assess normal timing.

Use a neutral example.com link. Type `asdasd`, then press Cmd+Delete. Check that
the glass and text visibly transition out, the pill leaves no residual capsule,
and the picker does not move. Repeat with final-character Backspace and Escape.
Type again during an exit and confirm that the new query survives the old
animation's completion. Ordinary typing must not restart the entry animation.

## Picker layouts

- In the development app, use General → Link picker → Layout to switch between List and Horizontal.
  Check that it uses the same native menu control as Window size.
  Check that Standard/Compact/Custom and the size editor only appear for List and the
  saved list size returns after switching back.
- Send a synthetic example.com link with 1, 5 and more than 10 enabled apps.
  Check centered small rows, a width that grows beyond 520 points to fit every app,
  no scrolling, left/right wraparound and Option hints.
- In both layouts, type a unique name, an ambiguous query and a typo. Check bold
  matching letters, match count and no-match message. Keep the mouse stationary while using keys;
  selection must stay with the keyboard.
- Repeat near each screen edge and on another display. Queue more links and
  trigger an opening error; the picker must retain its opening anchor.
- Inspect both layouts over light and dark backgrounds, then with increased
  contrast and reduced transparency. Verify app names, availability and selection
  with VoiceOver. Restore any changed accessibility settings after testing.

- In Horizontal, hover apps and navigate with arrows: only the selected icon
  shows its name instead of its number. Hold Option to reveal app shortcuts.
  Check long names truncate within their own slot, the link has its own centered glass pill above the icons
  without a leading symbol or divider, and selection closely surrounds the larger icon.

- In List, check that the app names and shortcuts remain visible, native selection
  follows the entire row, and there is no Open with heading, divider or footer link.
  Choose Custom under Window size (or Resize… for an existing custom size) and confirm the row preview still resizes and saves correctly.
  Hover each window edge and corner to check native resize cursors. Drag slowly
  by a few points: the window should respond continuously and snap to whole rows
  only on release. Check Cancel leaves the saved size unchanged.
- In both layouts, click the link pill to copy the exact URL. Click the transparent gap beside or
  below it to dismiss. Check the pill with a long hostname, a local filename and
  multiple queued links; the picker must stay within the screen.

## Native settings

- Switch General / Apps / About using the native toolbar. Close and reopen settings;
  the selected tab should remain. Reopening onboarding should return to General.
- In General, verify List and Horizontal both persist. Window size is only available
  for List; Resize… only for Custom. Cancel the custom-size editor before saving and
  confirm the old size remains selected. Confirm default-browser and login-approval
  messages are still available when relevant.
- In Apps, check/uncheck an app, then select it and move it up/down. Hidden apps must
  remain in the settings list and follow the same order as visible apps. Drag rows
  in both directions; cancel a drag and confirm no change is saved. Keep at least one browser enabled.
- Select Slack, Figma or another supported app and change its link behavior. Switch
  tabs and return: selection and the chosen behavior must remain. Record a shortcut,
  try a conflicting key, and cancel with Escape or by switching tabs.
- Add app… should open a native application chooser directly, without Edit list.
  Cancel without changes. Remove a manually added app through its context menu and
  confirm selection falls back to an available row.
- Check About, Help, Privacy and Copy app info. Inspect all tabs in English/Danish,
  light/dark mode and at the minimum window size, including keyboard and VoiceOver
  navigation. Restore any development preferences changed during manual testing.
