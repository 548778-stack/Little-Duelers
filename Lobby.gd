extends Control

@onready var start_match_button = $StartMatchButton as Button

func _ready() -> void:
	# Check if we are online or playing solo offline vs the computer bot
	if multiplayer.multiplayer_peer != null:
		# INSTRUCTION FIXED: Only the host machine has permission to see or click the Start Match button!
		if not multiplayer.is_server():
			if start_match_button:
				start_match_button.text = "WAITING FOR HOST..."
				start_match_button.disabled = true
		else:
			if start_match_button:
				start_match_button.pressed.connect(_on_start_match_pressed)
	else:
		# Offline mode fallback connection
		if start_match_button:
			start_match_button.pressed.connect(_on_start_match_pressed)

func _on_start_match_pressed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		print("📡 Host clicked START MATCH inside Lobby. Distributing launch payload across LAN wire...")
		# Trigger the multi-client network scene switch to load CombatArena.tscn simultaneously!
		rpc("launch_combat_arena", "res://CombatArena.tscn")

# --- INSTRUCTION FIXED: THE MULTI-CLIENT MATCH START RPC ---
@rpc("any_peer", "call_local", "reliable")
func launch_combat_arena(scene_path: String) -> void:
	print("⚔️ Entering active combat canvas zone! Swapping file to: ", scene_path)
	get_tree().change_scene_to_file(scene_path)
