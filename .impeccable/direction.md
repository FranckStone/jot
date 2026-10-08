# 编辑工作台

Mode: Operate. Scope: Sources/Jot/WorkbenchViews.swift, Sources/Jot/WorkbenchWindowController.swift and shared native components. Native macOS AppKit.

## Direction contract
THESIS: Give arbitrary local files and copied data a spacious shared canvas, with source and result cards visible side by side.
OWN-WORLD: Preserve the user-pinned gray-white Apple Liquid Glass direction, graphite dot-and-lowercase-j identity and system typography. Native translucent navigation and controls surround opaque cards; dark appearance uses neutral charcoal counterparts.
STORY: Add or paste, arrange, inspect in a detail window, process into a source-linked result, compare, then copy or export. Local-save and processing status stay visible. Preview capability follows the file type and system support.
FIRST VIEWPORT: A 220pt translucent sidebar contains brand, workbench navigation, search, type filter and compact item rows. The large workspace has a 24pt title, create/paste/import actions, a 44pt contextual glass toolbar, free canvas and zoom/status footer. Cards have 14pt corners, draggable headers and visible resize grips. Initial content size is 1360×860pt; minimum window size is 1080×680pt. Canvas magnification is 35%–200%.
FORM: Native macOS windows, AppKit controls and original dot-and-j geometry remain authoritative. NSGlassEffectView on macOS 26+, interactive glass on macOS 27+, native visual-effect fallback on older supported systems. Detail editing and preview use separate resizable windows; card manipulation happens on the canvas. Processing creates new cards from the whole source without replacing it.
BOUNDARIES: PDF extraction reads text layers; image OCR is local and may misrecognize. CSV/TSV preview is read-only with editable raw text; other files, including Excel, use Quick Look or a system application. Source association is recorded without connector lines. The canvas is a single persisted workbench, not a collaborative or multi-board system.
FINISH: Keep PRODUCT.md, README.md, DESIGN.md and its sidecar consistent with shipped Swift sources. Preserve raster provenance and native identity assets; documentation previews do not establish native runtime verification.
