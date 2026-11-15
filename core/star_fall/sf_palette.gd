extends RefCounted
## Shared palette for STAR FALL.
## Present-day Earth is bright: daylight blue, living green, warm neutrals.
## The ruined future is dark: teal, ash gray, contaminated violet, cyan tech.

# Present-day Earth.
const SKY := Color("67b7e8")
const SKY_DEEP := Color("3f8fc9")
const GRASS_LIGHT := Color("8ccb5e")
const GRASS := Color("6fb549")
const GRASS_DARK := Color("4c8a33")
const LEAF_LIGHT := Color("a7d96f")
const LEAF := Color("6aa83f")
const LEAF_DARK := Color("3f7229")
const BARK := Color("6b4a2f")
const BARK_DARK := Color("4a3220")
const CONCRETE := Color("cbc5b3")
const CONCRETE_MID := Color("aca592")
const CONCRETE_DARK := Color("857f6f")
const WARM := Color("efe2c4")
const WARM_DARK := Color("d6c39b")
const STEEL := Color("aab6bd")
const STEEL_MID := Color("7d8a92")
const STEEL_DARK := Color("525d64")
const BLUE_ACCENT := Color("2d6fa8")
const EARTH_ORANGE := Color("e08a3c")

# Ruined future. Values are deliberately spread: the ash plain underfoot is
# the lightest surface in the scene, so props, the wreck and the scorch all
# have something to read against.
const RUIN_BG := Color("0b1514")
const RUIN_DARK := Color("16241f")
const RUIN := Color("23332d")
const ASH := Color("44504a")
const ASH_LIGHT := Color("66716a")
const ASH_PLAIN := Color("39463f")
const ASH_PLAIN_LIGHT := Color("4b584f")
const SOOT := Color("101a17")
const VIOLET := Color("5b3f73")
const VIOLET_LIGHT := Color("7f5f9b")
const CYAN := Color("5ee6da")
const CYAN_DIM := Color("2b8b84")
const CYAN_DARK := Color("175550")
const RUST := Color("8a4b2f")
const RUST_LIGHT := Color("b06a44")

# Shared UI.
const INK := Color("101a1c")
const PAPER := Color("e8e4d4")
const PAPER_DIM := Color("b3b0a3")
const GOLD := Color("e5c04a")
const RED := Color("d9534f")
const GREEN_OK := Color("66c96a")

# The blue escape shield, and the one human face the game ever shows close up.
# Nick remains placeholder art in the world; the finale portrait is the one
# deliberately detailed human drawing, because the ending rests on his face.
const SHIELD_BLUE := Color("57c8f5")
const SHIELD_BLUE_LIGHT := Color("b6ecff")
const SHIELD_BLUE_DEEP := Color("1f6c9c")
const SKIN := Color("e2a97e")
const SKIN_LIGHT := Color("f4c79a")
const SKIN_DARK := Color("b87a52")
const HAIR := Color("3a2a22")
const HAIR_LIGHT := Color("5b4233")

const SLOT_NAMES := {
	"computer": "FLIGHT COMPUTER",
	"propulsion": "PROPULSION",
	"power": "POWER PLANT",
	"communications": "COMMUNICATIONS",
	"sensor": "SENSOR",
}
