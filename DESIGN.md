---
name: Jot
description: Native macOS local data workbench with a free canvas, neutral cards and Apple Liquid Glass controls.
colors:
  backdrop: "#F3F3F5"
  backdrop-dark: "#1C1C1E"
  paper: "#FFFFFF"
  paper-dark: "#242426"
  sidebar: "#ECECEE"
  sidebar-dark: "#29292C"
  ink: "#1D1D1F"
  ink-dark: "#F5F5F7"
  muted: "#5C5C61"
  muted-dark: "#B7B7BD"
  accent: "#303034"
  accent-dark: "#E4E4E8"
  on-accent: "#FFFFFF"
  on-accent-dark: "#242426"
  selected: "#E2E2E6"
  selected-dark: "#36363A"
  line: "#DEDEE2"
  line-dark: "#3C3C40"
typography:
  wordmark:
    fontFamily: "system-ui"
    fontSize: "26px"
    fontWeight: 600
  headline:
    fontFamily: "system-ui"
    fontSize: "25px"
    fontWeight: 500
  title:
    fontFamily: "system-ui"
    fontSize: "24px"
    fontWeight: 600
  detail-title:
    fontFamily: "system-ui"
    fontSize: "19px"
    fontWeight: 600
  body:
    fontFamily: "system-ui"
    fontSize: "15px"
    fontWeight: 400
  code:
    fontFamily: "ui-monospace"
    fontSize: "14px"
    fontWeight: 400
  card-title:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 600
  control:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 400
  control-primary:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 500
  metadata:
    fontFamily: "system-ui"
    fontSize: "11px"
    fontWeight: 400
  caption:
    fontFamily: "system-ui"
    fontSize: "10px"
    fontWeight: 400
rounded:
  card: "14px"
  toolbar: "18px"
  control-capsule: "17px"
spacing:
  tight: "8px"
  compact: "12px"
  content-inset: "16px"
  sidebar-inset: "20px"
  detail-inset: "24px"
  frame-inset: "28px"
  card-gap: "32px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    typography: "{typography.control-primary}"
    rounded: "{rounded.control-capsule}"
    height: "34px"
  button-secondary:
    backgroundColor: "#FAFAFC"
    textColor: "{colors.ink}"
    rounded: "10px"
    typography: "{typography.control}"
    height: "34px"
  type-filter:
    backgroundColor: "#FAFAFC"
    textColor: "{colors.ink}"
    typography: "{typography.control}"
    rounded: "10px"
    height: "34px"
  search-field:
    typography: "{typography.control}"
    height: "28px"
  item-row:
    textColor: "{colors.ink}"
    typography: "{typography.control-primary}"
    height: "49px"
  card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    width: "360px"
    height: "320px"
  editor:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    padding: "14px 16px"
  glass-toolbar:
    rounded: "{rounded.toolbar}"
    height: "44px"
    padding: "0px 12px 0px 16px"
---

# Design System: Jot

## Overview

**Creative North Star: "编辑工作台"**

Jot gives text, data and files a spacious native Mac workbench. The confirmed gray-white direction appears in an adaptive graphite identity, a translucent sidebar, opaque content cards and native glass controls. The Jot name and user-selected dot-and-lowercase-j silhouette remain the identity anchors.

The free canvas makes sources and results visible together. Compact navigation and contextual tools leave room for movable cards; separate detail windows give editing and previewing focused space. System typography, AppKit window chrome and native text interactions determine the feel.

**Key Characteristics:**

- Neutral gray-white surfaces with adaptive charcoal counterparts.
- Opaque cards on a scrollable, magnifiable canvas.
- Native glass navigation and contextual controls.
- Visible card selection, source context and local-save status.
- User-selected dot-and-lowercase-j identity, drawn natively. The packaged Dock icon uses a centered 832 × 832 px badge on a transparent 1024 × 1024 px canvas (96 px margin); in-app marks use their existing control bounds.

The source of truth is `Sources/Jot/WorkbenchViews.swift`, `Sources/Jot/WorkbenchWindowController.swift` and the shared `Palette`, `glassPanel`, `controlCapsule` and `LogoView` in `Sources/Jot/Components.swift`. `Sources/JotCore/Workbench.swift` owns persisted card geometry. CSS-compatible pixel values in frontmatter represent the same numeric AppKit point values. Native scaling, materials and control chrome remain authoritative.

## Colors

Graphite actions and nearly achromatic surfaces carry the established identity. Palette values resolve through native Aqua or Dark Aqua appearance; unsuffixed tokens are light and `-dark` tokens are dark counterparts.

### Primary

- **Graphite accent** (`accent` / `accent-dark`): identity badge, primary import capsule and selected-card outline.
- **Accent foreground** (`on-accent` / `on-accent-dark`): dot-and-j mark and primary action content.

### Neutral

- **Window gray** (`backdrop` / `backdrop-dark`): workspace and canvas backing.
- **Content paper** (`paper` / `paper-dark`): opaque card surfaces, text previews, PDF backing and detail editor.
- **Sidebar reference gray** (`sidebar` / `sidebar-dark`): reference palette only; the sidebar uses system-composited `.sidebar` material.
- **Graphite ink** (`ink` / `ink-dark`): text, card names and headings.
- **Muted gray ink** (`muted` / `muted-dark`): descriptions, type icons, card footers and save status.
- **Selection gray** (`selected` / `selected-dark`): retained shared palette role; the workbench list and detail text use native selection behavior.
- **Fine gray rule** (`line` / `line-dark`): unselected-card border.

**The Appearance Pair Rule.** Apply light and dark values by semantic role through native appearance resolution; do not freeze the app to a single screenshot's palette.

Save failures use adaptive `NSColor.systemRed` with explanatory text. System selection and error states are platform semantics, not additional brand accents.

## Typography

**Display Font:** `NSFont.systemFont`.
**Body Font:** `NSFont.systemFont`.
**Label/Mono Font:** system labels and `NSFont.monospacedSystemFont` for JSON and table source text.

No fonts are bundled. Chinese labels and mixed text/data content use native metrics and truncation. The workbench title and sidebar wordmark anchor orientation; card titles remain compact, with type and provenance in smaller captions.

### Hierarchy

- **Wordmark / title:** semibold sidebar identity and main workbench heading.
- **Headline:** medium empty-canvas invitation.
- **Detail title:** semibold editable card name in the separate window.
- **Body / code:** default detail text and structured-data editing. View-menu adjustments range from (12–28 pt); these are current editor presentation controls, not saved per-card preferences.
- **Card title:** semibold; compact text previews use regular (13 pt), JSON previews monospaced (12 pt).
- **Control / metadata / caption:** native actions, save status, type labels and source-operation context.

## Layout

The initial main-window content rectangle is (1360 × 860 pt), with minimum window size (1080 × 680 pt). Its frame is restored under `Jot.WorkbenchWindow`. A collapsible sidebar (220 pt when expanded) holds the (36 pt) identity badge, workbench navigation, search, type filter and scrolling item list. List rows are (49 pt) high. Native traffic lights and resizable window behavior remain intact.

The main heading starts (28 pt) from the workspace edge and (25 pt) from the top. Creation and import actions sit to its right. The contextual glass toolbar begins (102 pt) below the main area's top, inset (22 pt) on each side, and uses the frontmatter height. The canvas scroll view begins (12 pt) below the toolbar. A (36 pt) footer contains save state, arrange and zoom controls.

The canvas expands to fit card bounds with (240 pt) trailing room, with minimum document size (1800 × 1200 pt). Scrolling works on both axes. Magnification ranges from (35%–200%); button increments are (15 percentage points), with reset to (100%). On macOS 26 and newer, main and detail windows use a native unified NSToolbar title bar. AppKit owns the close, minimize and zoom buttons, including their spacing, materials, hover states, full-screen behavior and window corner geometry. There are no web or mobile breakpoints.

Default cards use the frontmatter size. PDF and imported-image cards start (400 pt) tall, pasted-image cards (360 pt). Drag the header to move; drag the lower-right grip to resize. Width clamps to (280–1600 pt), height to (220–1600 pt). The header is (48 pt) high; previews have (12 pt) horizontal insets and leave (34 pt) at the bottom for captions and the grip. Result cards start beside the source with card-gap spacing and move downward to avoid existing cards.

Detail windows start at (900 × 680 pt), with minimum window size (560 × 400 pt). Their editable title begins at (24 pt, 18 pt); content begins at (82 pt) with (16 pt) side and bottom insets. Multiple detail windows may coexist.

## Elevation & Depth

The sidebar uses `NSVisualEffectView` with `.sidebar`, `.withinWindow` and `.active`. On macOS (26+), glass panels use `NSGlassEffectView` with `.regular` style, explicit radius, optional tint and a `contentView`. macOS (27+) enables `effectIsInteractive`. On macOS (13–25), untinted panels use active `.headerView` material with rounded clipping, tinted surfaces use an opaque accent surface. Shared action buttons render their own state feedback on every supported macOS version.

Cards have no authored shadow. Opaque surfaces and borders establish their bounds: a (1 pt) fine-rule border at rest and (2 pt) graphite border when selected. Preview controls retain their native depth and selection behavior.

**The Native Material Rule.** Let AppKit own glass composition, highlights, shadows, focus, hover and pressed rendering. Documentation snippets illustrate geometry and palette only; they do not reproduce native materials.

The availability branches are source-verified. This documentation pass does not establish runtime verification for every supported macOS release.

## Shapes

Cards, contextual toolbar and the import capsule use their separate frontmatter radius tokens. Rounded cards clip preview content. Native search, popup and segmented controls retain system shape behavior.

The user-selected dot-and-lowercase-j geometry stays shared between `Resources/icon.svg` and `LogoView`. Its reference frame is (64 × 64), with a dot centered at (40, 16), radius (4), and j path `M37.5 28 L34.5 41.5 C33 48.5 23 50 20 43` with a (7-unit) round-capped stroke. Badge corners are (25%) of width. The workbench sidebar renders the badge at (36 × 36 pt).

## Components

### Buttons

Compact native actions pair labels with SF Symbols. The shared factory uses the declared control height and system typography. Shared `FeedbackButton` controls preserve native NSButton tracking, actions, keyboard activation and accessibility while rendering visible state feedback. “添加文件” uses an accent capsule (17 pt radius); secondary actions use a light fill, 1 pt outline and 10 pt radius. Secondary light/dark fills are #FAFAFC/#323237 at rest, #E6E6ED/#45454D on hover, and #D3D3DC/#55555E when pressed. Hover transitions take 140 ms, presses 80 ms and pointer exit 180 ms, using a decelerating curve. Presses scale to 96% around the center and release smoothly; interrupted transitions start from the presentation state. Reduce Motion removes scale changes and retains 80 ms color feedback. Enabled controls show a pointing-hand cursor, keyboard focus uses the system focus color, and disabled controls use 40% opacity without hover or press feedback. Icon-only controls center their glyphs; text controls reserve horizontal padding. Contextual tools disable without a selection or while that source is processing.

### Inputs / Fields

The sidebar `NSSearchField` sends queries immediately, paired with a native type popup. The detail title is a transparent, borderless `NSTextField`. Text editing is an `NSTextView` with native undo and selection, paired with the localized find/replace panel. Search, title and icon-only actions have accessibility labels.

### Navigation

An `NSTableView` lists item icons, names and type or operation captions in a transparent scroll view over sidebar material. Selecting an item reveals its card; double-click opens its detail window. Filtering and search also hide nonmatching canvas cards. The list retains native selection rendering. Items appear newest-added first, including existing saved items. Adding or pasting a card scrolls the list to its first row and selects the new card. Editing an older card does not change this order. Explicit canvas arrangement follows the same newest-first order; ordinary additions preserve existing card positions.

### Cards / Containers

An opaque card presents type, title, content preview, operation caption and resize grip. The title/header is the drag target; double-clicking it or using the expand button opens detail. Text previews are read-only and capped at (12,000 characters). Images scale proportionally, PDFs use a single-page preview, and CSV/TSV uses a native table with (25 pt) rows and initially (130 pt) columns. Arbitrary files show a system icon on the canvas and use Quick Look in detail when available.

### Glass Toolbar

The contextual row shows selected type and title, flexible space, “专注查看” and “卡片工具”. Its menu adapts to content type. Result cards show the operation and provide a source-location action; this is a source relationship, with no connector lines or node-graph editor.

### Detail Window

Plain text, JSON and table source use the editor. CSV/TSV adds “表格 / 原文” segments: the table is read-only, the source editable. PDFs use continuous-page PDFKit; images use native image views; other files use system Quick Look. The processing commands use the full source card, even when text is selected in detail, and create separate results.

### Save Status and Empty Canvas

The footer reports “正在保存…”, “已保存到本机”, processing progress or failure in text. Edits and layout changes debounce saving by (0.5 s). The previous editor's timed save-seal animation is not part of the workbench. Failure text becomes system red and directs the user to export.

The empty canvas displays “把文件放上来，开始处理。” at (56 pt, 64 pt), followed by instructions to drop files, paste text, arrange cards and open detail. The whole canvas accepts file, text and image drops.

## Do's and Don'ts

### Do:

- **Do** preserve the Jot name and user-selected dot-and-lowercase-j silhouette.
- **Do** keep gray-white surfaces and adaptive charcoal counterparts.
- **Do** reserve glass for navigation and controls while keeping content cards opaque.
- **Do** keep drag handles, resize grips and selection outlines visible.
- **Do** use native windows and controls for detail editing, preview and system actions.
- **Do** show processing state, result provenance and save failures in clear text.

### Don't:

- **Don't** restore the superseded sage palette or add stationery textures.
- **Don't** replace the native Mac implementation with a web shell or mobile layout.
- **Don't** invent exact glass colors, decorative card shadows or production CSS blur.
- **Don't** describe read-only previews as editable grids or claim direct editing of arbitrary files.
- **Don't** treat documentation panel previews as native rendering or older-OS validation.

### Type filter

The sidebar type filter uses `FeedbackPopUpButton`, a native NSPopUpButton with the shared secondary-button surface and feedback. It is 34 pt high with a 10 pt radius, 12 pt text, a leading type icon and a trailing disclosure chevron. Hover changes the fill and border; menu tracking keeps the pressed treatment and upward chevron until selection or dismissal. The native menu retains type icons, selection checkmarks, keyboard navigation and Escape dismissal. Menu width follows the field, with 13 pt menu text. The shared renderer honors dark appearance, disabled states, keyboard focus and Reduce Motion.

### Sidebar visibility

A persistent 34 pt sidebar toggle sits beside the workbench heading. It collapses the sidebar fully and gives its 220 pt width to the canvas; it remains accessible in both states. The View menu and Control–Command–S trigger the same action, with labels reflecting the current state. A 220 ms decelerating slide explains the layout change; Reduce Motion switches immediately. The last choice persists in `Jot.SidebarCollapsed`. Collapsing moves keyboard focus out of sidebar controls; reopening preserves the existing search, type filter, selection, card layout and zoom. Rapid toggles keep the latest visibility choice.

### Find and replace

Text, JSON and raw-table detail windows expose a visible “查找替换” button and Command–F. A rounded neutral panel has a heading and match counter, separate 34 pt find and replacement rows, shared feedback buttons, case-sensitive and whole-word options, and a close action. Searches are literal, debounce for 120 ms, and use UTF-16 ranges for AppKit. Match highlights are temporary; at most 1,000 are painted while navigation and replacement cover all matches. Return/Shift–Return and Command–G/Shift–Command–G navigate with wrapping. Replacing the current match and replacing all use native NSTextView edits and undo. Empty replacement deletes matches; empty query disables actions. Counts, no-match and completed-replacement states are explicit. Escape dismisses the panel from its inputs or editor. The panel fits the 560 pt minimum detail window and uses the existing adaptive palette.

Find/replace inputs use a 10 pt rounded paper surface with 12 pt horizontal padding. The inner NSTextField and its cell disable the default focus ring. Focus is shown around the full input surface with a 1.5 pt graphite outline (#73737E light / #AEAEB9 dark); the resting outline is 0.75 pt using the line token. Focus follows the actual field editor and active window, with a 140 ms border-color transition (80 ms for Reduce Motion). Placeholders use the muted text token.

Detail titles share the `TextInputSurface` focus treatment with find/replace fields: no inner native blue ring, and a 1.5 pt graphite rounded outline only while focused. Their 38 pt surface uses 10 pt horizontal padding and no resting border, preserving the 19 pt semibold heading appearance.

### Card quick actions

Each card header exposes duplicate, delete and expand actions as 28 × 28 pt square buttons with 6 pt corners and 6 pt gaps. Compact buttons use zero alignment insets to keep their visible width and height equal. They retain shared hover/press/focus feedback and named tooltips. Actions target the card UUID directly, independent of the selection or open detail windows. Delete uses the existing undoable removal path and disables while that card is processing. Header text truncates before the action group; its remaining area stays draggable.
