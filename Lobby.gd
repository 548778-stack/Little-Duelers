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
	# INSTRUCTION FIXED: Split connections explicitly out from generic targets into your true team layout nodes!
	_connect_lobby_button("P1Recon", func(): sync_lobby_selection.rpc(1, "class", "Recon"))
	_connect_lobby_button("P1Slingshotter", func(): sync_lobby_selection.rpc(1, "class", "Slingshotter"))
	_connect_lobby_button("P1Cowboy", func(): sync_lobby_selection.rpc(1, "class", "Cowboy"))
	
	# INSTRUCTION FIXED: Input guard lockout block checks NetworkManager.vs_ai state values! [0.1]
	_connect_lobby_button("P2Recon", func():
		if not NetworkManager.vs_ai and multiplayer.multiplayer_peer != null and multiplayer.is_server(): return
		var target_id = 2 if NetworkManager.vs_ai else (multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 2)
		sync_lobby_selection.rpc(target_id, "class", "Recon")
	)
	_connect_lobby_button("P2Slingshotter", func():
		if not NetworkManager.vs_ai and multiplayer.multiplayer_peer != null and multiplayer.is_server(): return
		var target_id = 2 if NetworkManager.vs_ai else (multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 2)
		sync_lobby_selection.rpc(target_id, "class", "Slingshotter")
	)
	_connect_lobby_button("P2Cowboy", func():
		if not NetworkManager.vs_ai and multiplayer.multiplayer_peer != null and multiplayer.is_server(): return
		var target_id = 2 if NetworkManager.vs_ai else (multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 2)
		sync_lobby_selection.rpc(target_id, "class", "Cowboy")
	)
	
	_connect_lobby_button("MapStandard", func(): sync_lobby_selection.rpc(1, "map", "Standard Field"))
	_connect_lobby_button("MapChaos", func(): sync_lobby_selection.rpc(1, "map", "Obstacle Heavy Chaos"))
	_connect_lobby_button("MapPlain", func(): sync_lobby_selection.rpc(1, "map", "Open Empty Plain"))
	
	_connect_lobby_button("Lives3", func(): sync_lobby_selection.rpc(1, "lives", "3"))
	_connect_lobby_button("Lives5", func(): sync_lobby_selection.rpc(1, "lives", "5"))
	_connect_lobby_button("Lives7", func(): sync_lobby_selection.rpc(1, "lives", "7"))

	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		if start_match_button:
			start_match_button.text = "WAITING FOR HOST..."
			start_match_button.disabled = true
	else:
		if start_match_button and not start_match_button.pressed.is_connected(_on_start_match_pressed):
			start_match_button.pressed.connect(_on_start_match_pressed)

func update_abilities_ui(peer_id: int, character_name: String) -> void:
	var target_container = p1_abilities_container if peer_id == 1 else p2_abilities_container
	if not target_container: return
	for child in target_container.get_children(): child.queue_free()
		
	if character_data.has(character_name):
		var abilities_array = character_data[character_name]["abilities"]
		for ability_string in abilities_array:
			var btn = Button.new()
			btn.text = ability_string
			btn.custom_minimum_size = Vector2(180, 35)
			btn.pressed.connect(func(): sync_lobby_selection.rpc(peer_id, "ability", ability_string))
			target_container.add_child(btn)

# INSTRUCTION FIXED: Wrapper declared with exact matching tag configuration properties!
@rpc("any_peer", "call_local", "reliable")
func sync_lobby_selection(peer_id: int, selection_type: String, value: String) -> void:
	match selection_type:
		"class":
			var dict_key = peer_id if peer_id == 1 else "guest"
			NetworkManager.lobby_data[dict_key]["character"] = value
			NetworkManager.lobby_data[dict_key]["ability"] = character_data[value]["abilities"][0]
			if NetworkManager.vs_ai and peer_id == 2:
				NetworkManager.lobby_data[2] = {"character": value, "ability": character_data[value]["abilities"][0]}
			
			if peer_id == 1:
				if p1_choice_label: p1_choice_label.text = "P1 Class: " + value
				_highlight_selected_button_group(["P1Recon", "P1Slingshotter", "P1Cowboy"], "P1" + value, Color(0.2, 0.6, 1.0))
			else:
				if p2_choice_label: p2_choice_label.text = "P2 Class: " + value
				_highlight_selected_button_group(["P2Recon", "P2Slingshotter", "P2Cowboy"], "P2" + value, Color(1.0, 0.3, 0.3))
			update_abilities_ui(peer_id, value)
		"ability":
			var dict_key = peer_id if peer_id == 1 else "guest"
			NetworkManager.lobby_data[dict_key]["ability"] = value
		"map":
			NetworkManager.selected_map = value
			var target_btn = "MapStandard" if value == "Standard Field" else ("MapChaos" if value == "Obstacle Heavy Chaos" else "MapPlain")
			_highlight_selected_button_group(["MapStandard", "MapChaos", "MapPlain"], target_btn, Color(0.2, 1.0, 0.5))
		"lives":
			NetworkManager.starting_lives = value.to_int()
			_highlight_selected_button_group(["Lives3", "Lives5", "Lives7"], "Lives" + value, Color(0.2, 1.0, 0.5))

func _on_start_match_pressed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		# INSTRUCTION FIXED: Modern dot-syntax RPC trigger sequence!
		launch_combat_arena.rpc("res://CombatArena.tscn")

@rpc("any_peer", "call_local", "reliable")
func launch_combat_arena(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _connect_lobby_button(btn_name: String, callback: Callable) -> void:
	var btn = find_child(btn_name, true, false) as Button
	if btn and not btn.pressed.is_connected(callback): btn.pressed.connect(callback)

func _highlight_selected_button_group(group_names: Array, chosen_name: String, highlight_color: Color) -> void:
	for node_name in group_names:
		var btn = find_child(node_name, true, false) as Button
		if btn: btn.self_modulate = highlight_color if node_name.to_lower() == chosen_name.to_lower() else Color.WHITE
