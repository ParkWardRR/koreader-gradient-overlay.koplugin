# Gradient Overlay for KOReader

[![License](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://opensource.org/license/bsd-3-clause)


A KOReader plugin that renders a horizontal color gradient beneath each text line to aid visual tracking on color e‑ink, computed locally with no network calls, with automatic night‑mode support, engine‑aware geometry when available, cached rendering, and per‑book profiles. [web:34][web:2]

Status: Untested and work in progress — community testing and contributions are highly encouraged to validate alignment across engines, formats, and devices. [web:122][web:89]

Note: This project emulates a color‑gradient reading aid similar in visual effect to certain browser tools such as “BeeLine Reader,” but it is independent, offline, and does not include or use any proprietary code or services. [web:89][web:99]

## Features
| Feature | Details |
| --- | --- |
| Local segmentation | Pluggable breaks: smart rules, thirds, halves, optional tokenizer if available; no network or cloud dependencies. [web:56][web:36] |
| Engine‑aware geometry | Attempts to read real line rectangles from the active engine/view; falls back to estimation otherwise. [web:70][web:36] |
| Night‑mode support | Auto palette and opacity switching with per‑book overrides for edge cases. [web:2][web:49] |
| Cached rendering | Precomputed gradient strips and partial refresh requests for faster page turns and less ghosting. [web:112][web:114] |

## Installation
Create a folder named koreader/frontend/plugins/koreader-gradient-overlay.koplugin, copy init.lua and _meta.lua into it, restart KOReader, then in‑book open Menu → Gradient Overlay → Toggle / Settings. [web:34][web:2]

## Usage
Enable the overlay, choose a segmentation method, and select a color preset; the plugin auto‑switches palettes for night mode and stores per‑book preferences via DocSettings. [web:2][web:49]

## Settings
| Setting | Options | Notes |
| --- | --- | --- |
| Segmentation | smart, thirds, halves, tokenizer | Tokenizer mode uses a local Lua tokenizer if present; otherwise falls back to smart rules. [web:56][web:36] |
| Palettes | light/night left+right colors | Separate opacity per mode to maintain contrast on dark backgrounds. [web:2][web:36] |
| Rendering | bar height %, vertical offset, partial refresh | Uses UIManager:setDirty for targeted refresh on e‑ink devices. [web:112][web:34] |

## Contributing
This repository is untested/WIP and needs real‑device validation; reports and PRs from color e‑ink devices (for example, Bigme B6) are especially helpful. [web:122][web:34]

Development workflow: fork the repository, copy the plugin folder to koreader/frontend/plugins/koreader-gradient-overlay.koplugin on a device or emulator, restart KOReader, and use the in‑book menu to toggle settings and observe redraw behavior. [web:34][web:2]

Testing guidance: compare alignment while switching fonts, margins, and justification; verify engine‑derived line rectangles versus estimated layout; capture screenshots where gradient seams drift from glyph bounds. [web:2][web:36]

Performance tips: leverage partial refresh to limit repaint area, and prefer cached gradient strips to reduce fill operations and latency on page turns. [web:112][web:114]

Issue reports: include device model, KOReader version, document format (EPUB/PDF/…), segmentation method, palette, and screenshots illustrating any misalignment or refresh artifacts. [web:89][web:122]

Pull requests: keep changes focused, describe the rationale and testing steps, and update documentation snippets in this README if behavior or settings change. [web:89][web:99]

## Roadmap
Engine‑specific line/word rectangle mapping across EPUB/PDF with better handling for RTL and vertical text, device‑tuned color presets for common panels, and a minimal tokenizer hook guide for multi‑language tuning. [web:70][web:34]

## License
BSD 3‑Clause; include the full license text in source and distribution artifacts in accordance with attribution and no‑endorsement requirements. [web:130][web:125]
