# Instant Translation (Loquat)

A macOS menu-bar app that translates selected/copied text through Google and LLM providers. This context records the terms that describe how text enters the translation window.

## Language

**clipboard-on-shortcut**:
A setting that, when enabled, reads the latest pasteboard text and translates or prefills it (subject to the 500-character auto-submit limit) — but only when the popover is opened via the global shortcut.
_Avoid_: clipboard-on-open

**shortcut invocation**:
Opening the popover by pressing the registered global shortcut. The only trigger that may read the clipboard.
_Avoid_: keyboard open, hotkey open

**menu-bar click**:
Opening the popover by clicking the menu-bar status item. Never reads the clipboard.
_Avoid_: mouse open, status-item click
