local _ = require("gettext")
return {
    name = "gradient_overlay",
    fullname = _("Gradient Overlay"),
    description = _([[Color-gradient line-tracking overlay for KOReader. This plugin locally computes break indices per line (no network) to approximate color-gradient reading aids sometimes known from browser tools. It supports auto night mode detection and separate palettes per theme.]]),
}
