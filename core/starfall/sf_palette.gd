extends RefCounted
## Shared palette for Operation: Starfall. One place, per the art direction.

const DEEP := Color(0.043, 0.059, 0.098)      # #0b0f19
const NIGHT := Color(0.086, 0.106, 0.180)     # #161b2e
const SHADOW := Color(0.200, 0.255, 0.333)    # #334155
const MID := Color(0.392, 0.455, 0.545)       # #64748b
const HIGH := Color(0.580, 0.639, 0.722)      # #94a3b8
const CYAN := Color(0.220, 0.741, 0.973)      # #38bdf8
const CYAN_DIM := Color(0.110, 0.400, 0.545)
const ORANGE := Color(0.976, 0.451, 0.086)    # #f97316
const RED := Color(0.937, 0.267, 0.267)       # #ef4444
const GOLD := Color(0.918, 0.702, 0.031)      # #eab308
const BLUE := Color(0.118, 0.227, 0.541)      # #1e3a8a
const GREEN := Color(0.204, 0.827, 0.600)     # #34d399
const PAPER := Color(0.796, 0.835, 0.882)     # #cbd5e1
const STAR_DIM := Color(0.392, 0.455, 0.545)
const STAR_BRIGHT := Color(0.796, 0.835, 0.882)

const DEBRIS_COLORS := {
	"scrap": Color(0.392, 0.455, 0.545),
	"panel": BLUE,
	"satellite": HIGH,
	"billboard": CYAN,
	"packaging": GOLD,
	"trophy": GOLD,
	"specimen": GREEN,
}
