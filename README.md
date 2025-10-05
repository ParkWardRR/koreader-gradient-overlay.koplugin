# Gradient Overlay for KOReader

[![License](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://opensource.org/license/bsd-3-clause)



A KOReader plugin that draws a horizontal color gradient beneath each text line to aid visual tracking on color e‑ink. Computed locally (no network), with automatic night‑mode support, engine‑aware geometry when available, cached rendering, and per‑book profiles. This emulates a BeeLine‑style (beeline) visual effect but is independent and fully offline.

Status: Untested and work in progress — community testing and contributions are encouraged to validate alignment across engines, formats, and devices.

### Features
| Feature | Details |
| --- | --- |
| Local segmentation | Pluggable breaks: smart rules, thirds, halves, optional tokenizer if present; no cloud dependencies. |
| Engine‑aware geometry | Reads real line rectangles when exposed by the active engine; estimates otherwise. |
| Night‑mode support | Auto palette and opacity switching with per‑book overrides. |
| Cached rendering | Precomputed gradient strips and partial refresh for faster turns and less ghosting. |

### Installation
Create koreader/frontend/plugins/koreader-gradient-overlay.koplugin, copy init.lua and _meta.lua into it, then restart KOReader. Example: `mkdir -p koreader/frontend/plugins/koreader-gradient-overlay.koplugin && cp init.lua _meta.lua koreader/frontend/plugins/koreader-gradient-overlay.koplugin/`

### Usage
In-book: Menu → Gradient Overlay → Toggle / Settings. Enable the overlay, choose a segmentation method, and select a color preset. The plugin auto-switches palettes for night mode and stores per‑book preferences via DocSettings.

### Settings
| Setting | Options | Notes |
| --- | --- | --- |
| Segmentation | smart, thirds, halves, tokenizer | Tokenizer uses a local Lua tokenizer if available; otherwise falls back to smart rules. |
| Palettes | light/night left+right colors | Separate opacity per mode to maintain contrast on dark backgrounds. |
| Rendering | bar height %, vertical offset, partial refresh | Uses UIManager:setDirty for targeted refresh on e‑ink devices. |

### Contributing
This is a WIP and needs real‑device validation (e.g., Bigme/Onyx color e‑ink). Keep PRs focused, describe rationale and testing steps, and update README snippets if behavior or settings change.

Testing guidance: Compare alignment across fonts, margins, and justification; verify engine‑derived line rectangles versus estimates; capture screenshots where gradient seams drift from glyph bounds.

Issue reports: Include device model, KOReader version, document format (EPUB/PDF/…), segmentation method, palette, and screenshots showing misalignment or refresh artifacts.

### Roadmap
Engine‑specific line/word rectangle mapping across EPUB/PDF, improved RTL and vertical text handling, device‑tuned color presets, and a minimal tokenizer hook guide for multi‑language tuning.

### License
BSD 3‑Clause. Include the full license text in source and distribution artifacts in accordance with attribution and no‑endorsement requirements.
