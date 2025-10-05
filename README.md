# Gradient Overlay for KOReader <!-- [web:34][web:36] -->

[![License](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://opensource.org/license/bsd-3-clause)



A KOReader plugin that renders a horizontal color gradient beneath each text line to aid visual tracking on color e‑ink, computed locally with no network calls, with automatic night‑mode support and per‑book profiles. <!-- [web:2][web:36] -->

Status: Untested and work in progress; community testing and contributions are highly encouraged. <!-- [web:129][web:89] -->

> Note: This project emulates a color‑gradient reading aid similar in visual effect to tools like “BeeLine Reader,” but it is independent, offline, and does not include or use any proprietary code or services. <!-- [web:89][web:99] -->

## Key features
- Local break calculation per line with pluggable segmentation: smart rules, thirds, halves, optional tokenizer if available. <!-- [web:56][web:36] -->
- Engine‑aware geometry probing for better line alignment, with graceful fallback to estimated rows. <!-- [web:70][web:36] -->
- Automatic night‑mode palette and opacity switching, with per‑book overrides via DocSettings. <!-- [web:2][web:49] -->
- Cached gradient strips and partial refresh requests for faster page turns and reduced ghosting. <!-- [web:112][web:114] -->

## Installation
1. Create a folder: `koreader/frontend/plugins/koreader-gradient-overlay.koplugin/`. <!-- [web:34][web:36] -->
2. Copy `init.lua` and `_meta.lua` into that folder and restart KOReader. <!-- [web:34][web:36] -->
3. In a book, open Menu → Gradient Overlay → Toggle / Settings. <!-- [web:2][web:34] -->

## Usage
- Toggle the overlay on/off, pick a segmentation method, and select a color preset; night mode detection will switch palettes automatically. <!-- [web:2][web:112] -->
- Per‑book overrides: the plugin stores palette, opacity, and segmentation preferences per title. <!-- [web:49][web:36] -->
- Designed for color e‑ink like the Bigme B6; it will render on grayscale but with reduced effect. <!-- [web:2][web:34] -->

## Settings overview
- Segmentation: smart | thirds | halves | tokenizer (if LuaNLP is installed). <!-- [web:56][web:36] -->
- Palettes: light/night left/right colors and per‑mode opacity. <!-- [web:2][web:34] -->
- Rendering: bar height %, vertical offset, and partial refresh usage. <!-- [web:112][web:2] -->

## Roadmap
- Prefer exact line/word rectangles from each engine where available (EPUB/PDF), and improve mapping for RTL/vertical layouts. <!-- [web:70][web:36] -->
- Add device‑tuned presets for common color e‑ink panels and publish a small calibration page. <!-- [web:34][web:36] -->
- Document a minimal tokenizer hook with examples and language notes. <!-- [web:56][web:99] -->

## Contributing
This project welcomes issues, PRs, device reports, and screenshots—especially alignment feedback on different formats and engines; please see CONTRIBUTING.md. <!-- [web:89][web:129] -->

## License
BSD 3‑Clause; see LICENSE in this repository. <!-- [web:130][web:128] -->
