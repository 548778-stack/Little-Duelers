extends Control

@onready var start_match_button = find_child("StartMatchButton", true, false) as Button
@onready var p1_abilities_container = find_child("P1AbilitiesContainer", true, false) as VBoxContainer
@onready var p2_abilities_container = find_child("P2AbilitiesContainer", true, false) as VBoxContainer
@onready var p1_choice_label = find_child("P1ChoiceLabel", true, false) as Label
@onready var p2_choice_label = find_child("P2ChoiceLabel", true, false) as Label

var character_data: Dictionary = {
	"Recon": {"abilities": ["Recons Eye", "Sensor Dart", "Cloak"]},
	"Slingshotter": {"abilities": ["Piercing Shot", "Bouncing Shot", "Grapnel Trick"]},
	"Cowboy": {"abilities": ["Marksman", "Jerry Miculek", "Deadeye Reload"]}
}

func _ready() -> void:
	for class_name_str in ["Recon", "Slingshotter", "Cowboy"]:
		var c = class_name_str
		_connect_lobby_button("P1" + c, func(): _request_selection(1, "class", c))
		_connect_lobby_button("P2" + c, func(): _request_selection(2, "class", c))

	_connect_lobby_button("MapStandard", func(): _request_selection(0, "map", "Standard Field"))
	_connect_lobby_button("MapChaos", func(): _request_selection(0, "map", "Obstacle Heavy Chaos"))
	_connect_lobby_button("MapPlain", func(): _request_selection(0, "map", "Open Empty Plain"))

	_connect_lobby_button("Lives3", func(): _request_selection(0, "lives", "3"))
	_connect_lobby_button("Lives5", func(): _request_selection(0, "lives", "5"))
	_connect_lobby_button("Lives7", func(): _request_selection(0, "lives", "7"))

	if start_match_button:
		# The .tscn already connects "pressed" -> _on_start_match_pressed, so don't connect twice.
		if NetworkManager.is_online() and not multiplayer.is_server():
			start_match_button.text = "WAITING FOR HOST..."
			start_match_button.disabled = true

	_refresh_ui_from_data()

# --- WHO MAY CHANGE WHAT -----------------------------------------------------

# Which side the local machine controls. Offline: both sides (couch / vs AI).
func _can_edit_side(side: int) -> bool:
	if not NetworkManager.is_online(): return true
	if side == 1: return multiplayer.is_server()
	return not multiplayer.is_server()

func _can_edit_settings() -> bool:
	return not NetworkManager.is_online() or multiplayer.is_server()

func _request_selection(side: int, selection_type: String, value: String) -> void:
	if selection_type == "class" or selection_type == "ability":
		if not _can_edit_side(side): return
	elif not _can_edit_settings():
		return
	sync_lobby_selection.rpc(side, selection_type, value)

# --- SYNCED SELECTION --------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func sync_lobby_selection(side: int, selection_type: String, value: String) -> void:
	# Validate on the receiving end too, so a guest can't change the host's picks.
	if NetworkManager.is_online():
		var sender = multiplayer.get_remote_sender_id()
		
		# FIXED: Replaced 'NetworkManager.guest_peer_id' with the dynamic 'sender' value
		var allowed_sender = 1 if (side == 1 or selection_type == "map" or selection_type == "lives") else sender
		if sender != allowed_sender: return

	match selection_type:
		"class":
			if not character_data.has(value): return
			
			var target_key = 1 if side == 1 else multiplayer.get_remote_sender_id()
			if not NetworkManager.is_online():
				target_key = side # Offline fallback for host vs bot
				
			if NetworkManager.lobby_data.has(target_key):
				NetworkManager.lobby_data[target_key]["character"] = value
				NetworkManager.lobby_data[target_key]["ability"] = character_data[value]["abilities"][0]
		"ability":
			var target_key = 1 if side == 1 else multiplayer.get_remote_sender_id()
			if not NetworkManager.is_online(): target_key = side
			if NetworkManager.lobby_data.has(target_key):
				NetworkManager.lobby_data[target_key]["ability"] = value
		"map":
			NetworkManager.selected_map = value
		"lives":
			NetworkManager.starting_lives = value.to_int()
			
	_refresh_ui_from_data()



func _refresh_ui_from_data() -> void:
	# FIXED: Ensure we look up standard slots (1 and 2) or any connected client peers safely
	var active_keys = NetworkManager.lobby_data.keys()
	
	for peer_id in active_keys:
		# Convert string keys from RPC packets to integers safely if needed
		var lookup_key = int(peer_id) if str(peer_id).is_valid_int() else peer_id
		if not NetworkManager.lobby_data.has(lookup_key): continue
		
		var character = NetworkManager.lobby_data[lookup_key]["character"]
		var team_id = NetworkManager.lobby_data[lookup_key].get("team", 1)
		
		var player_num = 1
		if str(lookup_key) == "1": player_num = 1
		elif str(lookup_key) == "2" or str(lookup_key) == "guest": player_num = 2
		else: player_num = active_keys.find(peer_id) + 1
			
		var label = find_child("P%dChoiceLabel" % player_num, true, false) as Label
		if label: 
			label.text = "P%d Class: %s (Team %d)" % [player_num, character, team_id]
			
		var prefix = "P%d" % player_num
		var highlight_color = Color(0.2, 0.6, 1.0) if team_id == 1 else Color(1.0, 0.3, 0.3)
		_highlight_selected_button_group(
			[prefix + "Recon", prefix + "Slingshotter", prefix + "Cowboy"], 
			prefix + character, 
			highlight_color
		)
		update_abilities_ui(player_num, lookup_key, character)

	# Safely refresh map and stock life buttons globally
	var map_value = NetworkManager.selected_map
	var target_btn = "MapStandard" if map_value == "Standard Field" else ("MapChaos" if map_value == "Obstacle Heavy Chaos" else "MapPlain")
	_highlight_selected_button_group(["MapStandard", "MapChaos", "MapPlain"], target_btn, Color(0.2, 1.0, 0.5))
	_highlight_selected_button_group(["Lives3", "Lives5", "Lives7"], "Lives" + str(NetworkManager.starting_lives), Color(0.2, 1.0, 0.5))

func update_abilities_ui(player_num: int, lookup_key: Variant, character_name: String) -> void:
	# FIXED: Separate the visual player column (player_num) from the actual network lookup key!
	var target_container = p1_abilities_container if player_num == 1 else p2_abilities_container
	# If you add containers for Player 3 and 4 later, you can add them here:
	if player_num == 3: target_container = find_child("P3AbilitiesContainer", true, false) as VBoxContainer
	if player_num == 4: target_container = find_child("P4AbilitiesContainer", true, false) as VBoxContainer
	
	if not target_container: return
	for child in target_container.get_children(): child.queue_free()

	if character_data.has(character_name) and NetworkManager.lobby_data.has(lookup_key):
		# FIXED: Safely read the ability using the dynamic network key (Peer ID or 1 or 2)
		var chosen = NetworkManager.lobby_data[lookup_key]["ability"]
		
		for ability_string in character_data[character_name]["abilities"]:
			var btn = Button.new()
			btn.text = ability_string
			btn.custom_minimum_size = Vector2(180, 35)
			
			# UI visual feedback check:
			var is_p1 = (player_num == 1)
			btn.disabled = not _can_edit_side(1 if is_p1 else 2) # simplified side lock out
			
			if ability_string == chosen:
				btn.self_modulate = Color(0.2, 1.0, 0.5)
				
			var a = ability_string
			# Route selection through the correct true network lookup key side identity
			btn.pressed.connect(func(): _request_selection(1 if is_p1 else 2, "ability", a))
			target_container.add_child(btn)


# --- START MATCH -------------------------------------------------------------

func _on_start_match_pressed() -> void:
	if not NetworkManager.is_online():
		get_tree().change_scene_to_file("res://CombatArena.tscn")
	elif multiplayer.is_server():
		if multiplayer.get_peers().is_empty():
			start_match_button.text = "NO OPPONENT CONNECTED"
			return
		NetworkManager.change_scene.rpc("res://CombatArena.tscn")

# --- UI HELPERS --------------------------------------------------------------

func _connect_lobby_button(btn_name: String, callback: Callable) -> void:
	var btn = find_child(btn_name, true, false) as Button
	if btn: btn.pressed.connect(callback)

func _highlight_selected_button_group(group_names: Array, chosen_name: String, highlight_color: Color) -> void:
	for node_name in group_names:
		var btn = find_child(node_name, true, false) as Button
		if btn: btn.self_modulate = highlight_color if node_name.to_lower() == chosen_name.to_lower() else Color.WHITE
