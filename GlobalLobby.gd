extends Node

# --- THE LIFELONG MULTIPLAYER DATA VAULT ---
# This dictionary lives safely in memory across scene switches [0.1].
var lobby_selections: Dictionary = {
	1: "Slingshotter",
	"guest": "Slingshotter"
}

var lobby_skills: Dictionary = {
	1: "Piercing Shot",
	"guest": "Piercing Shot"
}

var selected_map: String = "Standard Field"
var starting_lives_setting: int = 3
