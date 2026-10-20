extends Control

@onready var start_match_button = $"StartMatchButton" as Button
@onready var p1_abilities_container = find_child("P1AbilitiesContainer", true, false) as VBoxContainer
@onready var p2_abilities_container = find_child("P2AbilitiesContainer", true, false) as VBoxContainer
@onready var p1_choice_label = find_child("P1ChoiceLabel", true, false) as Label
@onready var p2_choice_label = find_child("P2ChoiceLabel", true, false) as Label

# --- 📁 INSTRUCTION FIXED: CENTRAL CHARACTER CONFIGURATION DICTIONARY ---
var character_data: Dictionary = {
	"Recon": {
		"color": Color(0.6, 0.2, 1.0), # Purple
		"abilities": ["Recons Eye", "Sensor Dart", "Cloak"]
	},
	"Slingshotter": {
		"color": Color(0.0, 0.9, 1.0), # Neon Cyan
		"abilities": ["Piercing Shot", "Bouncing Shot", "Grapnel Trick"]
	},
	"Cowboy": {
		"color": Color(1.0, 0.5, 0.0), # Desert Orange
		"abilities": ["Marksman", "Jerry Miculek", "Deadeye Reload"]
	}
}

func _ready() -> void:
	# Connect character class selection buttons dynamically based on server status
	_connect_lobby_button("ReconButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		print("🖱️ [LOCAL CLICK] Player clicked character button: Recon")
		rpc("sync_lobby_selection", target_id, "class", "Recon")
	)
	_connect_lobby_button("SlingshotterButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		print("🖱️ [LOCAL CLICK] Player clicked character button: Slingshotter")
		rpc("sync_lobby_selection", target_id, "class", "Slingshotter")
	)
	_connect_lobby_button("CowboyButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		print("🖱️ [LOCAL CLICK] Player clicked character button: Cowboy")
		rpc("sync_lobby_selection", target_id, "class", "Cowboy")
	)
	
	# Connect map and stock life buttons
	_connect_lobby_button("MapStandard", func(): rpc("sync_lobby_selection", 1, "map", "Standard Field"))
	_connect_lobby_button("MapChaos", func(): rpc("sync_lobby_selection", 1, "map", "Obstacle Heavy Chaos"))
	_connect_lobby_button("MapPlain", func(): rpc("sync_lobby_selection", 1, "map", "Open Empty Plain"))
	
	_connect_lobby_button("Lives3", func(): rpc("sync_lobby_selection", 1, "lives", "3"))
	_connect_lobby_button("Lives5", func(): rpc("sync_lobby_selection", 1, "lives", "5"))
	_connect_lobby_button("Lives7", func(): rpc("sync_lobby_selection", 1, "lives", "7"))

	# Handle host start button permissions
	if multiplayer.multiplayer_peer != null:
		if not multiplayer.is_server():
			if start_match_button:
				start_match_button.text = "WAITING FOR HOST..."
				start_match_button.disabled = true
		else:
			if start_match_button and not start_match_button.pressed.is_connected(_on_start_match_pressed):
				start_match_button.pressed.connect(_on_start_match_pressed)
	else:
		if start_match_button and not start_match_button.pressed.is_connected(_on_start_match_pressed):
			start_match_button.pressed.connect(_on_start_match_pressed)

# --- 🛠️ INSTRUCTION FIXED: DYNAMIC ABILITY SPAWNER FUNCTION ---
func update_abilities_ui(peer_id: int, character_name: String) -> void:
	var is_p1 = (peer_id == 1)
	
	# 1. Determine the target path container based on peer_id
	var target_container = p1_abilities_container if is_p1 else p2_abilities_container
	if not target_container:
		print("⚠️ Error: Abilities container path could not be found.")
		return
		
	# 2. Clear old data completely out of memory using queue_free()
	for child in target_container.get_children():
		child.queue_free()
		
	# 3. Instance new buttons on the fly by reading out of your central dictionary asset folder!
	if character_data.has(character_name):
		var abilities_array = character_data[character_name]["abilities"]
		
		for ability_string in abilities_array:
			var btn = Button.new()
			btn.text = ability_string
			btn.custom_minimum_size = Vector2(180, 35)
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			
			# Wire the dynamic button's pressed signal to track click logs over the LAN wire
			btn.pressed.connect(func():
				print("🎯 [ABILITY CLICK] Peer ID ", peer_id, " clicked ability option button: ", ability_string)
				rpc("sync_lobby_selection", peer_id, "ability", ability_string)
			)
			
			target_container.add_child(btn)
		print("📦 Spawner: Dynamically populated ", character_name, " perks array into ", target_container.name)

@rpc("any_peer", "call_local", "reliable")
func sync_lobby_selection(peer_id: int, selection_type: String, value: String) -> void:
	match selection_type:
		"class":
			print("🖱️ [CLICK LOG] Peer ", peer_id, " selected Character: ", value)
			# INSTRUCTION FIXED: Save choice to global NetworkManager script dict configuration layer!
			NetworkManager.lobby_data[peer_id] = {
				"character": value,
				"ability": character_data[value]["abilities"][0]
			}
			# Mirror backup for safe key lookup fallbacks
			if peer_id != 1: NetworkManager.lobby_data["guest"] = NetworkManager.lobby_data[peer_id]
			
			if peer_id == 1 and p1_choice_label: p1_choice_label.text = "P1 Class: " + value
			elif peer_id != 1 and p2_choice_label: p2_choice_label.text = "P2 Class: " + value
			
			_highlight_selected_button_group(["ReconButton", "SlingshotterButton", "CowboyButton"], value + "Button", character_data[value]["color"])
			update_abilities_ui(peer_id, value)
					
		"ability":
			print("🎯 [CLICK LOG] Peer ", peer_id, " locked in Ability choice: ", value)
			NetworkManager.lobby_data[peer_id]["ability"] = value
			if peer_id != 1: NetworkManager.lobby_data["guest"]["ability"] = value
				
		"map":
			# INSTRUCTION FIXED: Update NetworkManager variable and highlight button group layout
			NetworkManager.selected_map = value
			var map_slice = value.get_slice(" ", 0)
			_highlight_selected_button_group(["MapStandard", "MapChaos", "MapPlain"], "Map" + map_slice, Color(0.2, 1.0, 0.5))
			print("🌍 Central Map Sync locked: ", value)
			
		"lives":
			# INSTRUCTION FIXED: Update NetworkManager variable and highlight button group layout
			NetworkManager.starting_lives = value.to_int()
			_highlight_selected_button_group(["Lives3", "Lives5", "Lives7"], "Lives" + value, Color(0.2, 1.0, 0.5))
			print("🔢 Central Stock Sync locked: ", value, " Lives")

func _on_start_match_pressed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		print("🚀 Host clicked START MATCH. Passing map path transition code down LAN wire...")
		NetworkManager.rpc("change_scene", "res://CombatArena.tscn")

@rpc("any_peer", "call_local", "reliable")
func launch_combat_arena(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _connect_lobby_button(btn_name: String, callback: Callable) -> void:
	var btn = find_child(btn_name, true, false) as Button
	if btn:
		if btn.pressed.is_connected(callback): return
		btn.pressed.connect(callback)

func _highlight_selected_button_group(group_names: Array, chosen_name: String, highlight_color: Color) -> void:
	for node_name in group_names:
		var btn = find_child(node_name, true, false) as Button
		if btn:
			if node_name.to_lower().contains(chosen_name.to_lower()) or chosen_name.to_lower().contains(node_name.to_lower()):
				btn.self_modulate = highlight_color # Sets the button color dynamically from the dictionary color code!
			else:
				btn.self_modulate = Color(1.0, 1.0, 1.0) # Reset unselected button choices back to standard flat white
