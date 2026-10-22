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
		var allowed_sender = 1 if (side == 1 or selection_type == "map" or selection_type == "lives") else NetworkManager.guest_peer_id
		if sender != allowed_sender: return

	match selection_type:
		"class":
			if not character_data.has(value): return
			NetworkManager.lobby_data[side]["character"] = value
			NetworkManager.lobby_data[side]["ability"] = character_data[value]["abilities"][0]
		"ability":
			NetworkManager.lobby_data[side]["ability"] = value
		"map":
			NetworkManager.selected_map = value
		"lives":
			NetworkManager.starting_lives = value.to_int()
	_refresh_ui_from_data()

func _refresh_ui_from_data() -> void:
	for side in [1, 2]:
		var character = NetworkManager.lobby_data[side]["character"]
		var label = p1_choice_label if side == 1 else p2_choice_label
		if label: label.text = "P%d Class: %s" % [side, character]
		var prefix = "P%d" % side
		var color = Color(0.2, 0.6, 1.0) if side == 1 else Color(1.0, 0.3, 0.3)
		_highlight_selected_button_group([prefix + "Recon", prefix + "Slingshotter", prefix + "Cowboy"], prefix + character, color)
		update_abilities_ui(side, character)

	var map_value = NetworkManager.selected_map
	var target_btn = "MapStandard" if map_value == "Standard Field" else ("MapChaos" if map_value == "Obstacle Heavy Chaos" else "MapPlain")
	_highlight_selected_button_group(["MapStandard", "MapChaos", "MapPlain"], target_btn, Color(0.2, 1.0, 0.5))
	_highlight_selected_button_group(["Lives3", "Lives5", "Lives7"], "Lives" + str(NetworkManager.starting_lives), Color(0.2, 1.0, 0.5))

func update_abilities_ui(side: int, character_name: String) -> void:
	var target_container = p1_abilities_container if side == 1 else p2_abilities_container
	if not target_container: return
	for child in target_container.get_children(): child.queue_free()

	if character_data.has(character_name):
		var chosen = NetworkManager.lobby_data[side]["ability"]
		for ability_string in character_data[character_name]["abilities"]:
			var btn = Button.new()
			btn.text = ability_string
			btn.custom_minimum_size = Vector2(180, 35)
			btn.disabled = not _can_edit_side(side)
			if ability_string == chosen:
				btn.self_modulate = Color(0.2, 1.0, 0.5)
			var a = ability_string
			btn.pressed.connect(func(): _request_selection(side, "ability", a))
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
