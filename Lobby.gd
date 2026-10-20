extends Control

@onready var start_match_button = $StartMatchButton as Button

# Dynamic Column Containers (Ensure these node paths match your Lobby.tscn layout names!)
@onready var p1_abilities_container = find_child("P1AbilitiesContainer", true, false) as VBoxContainer
@onready var p2_abilities_container = find_child("P2AbilitiesContainer", true, false) as VBoxContainer
@onready var p1_choice_label = find_child("P1ChoiceLabel", true, false) as Label
@onready var p2_choice_label = find_child("P2ChoiceLabel", true, false) as Label

func _ready() -> void:
	# --- 🌐 INSTRUCTION FIXED: DYNAMIC HARDWARE BUTTON ROUTING ---
	# Instead of separate P1/P2 hooks, your buttons route automatically by checking server status!
	_connect_button("ReconButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		rpc("sync_lobby_selection", target_id, "class", "Recon")
	)
	_connect_button("SlingshotterButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		rpc("sync_lobby_selection", target_id, "class", "Slingshotter")
	)
	_connect_button("CowboyButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		rpc("sync_lobby_selection", target_id, "class", "Cowboy")
	)
	
	# --- CENTRAL COLUMN SELECTIONS (MAPS & LIVES) ---
	_connect_button("MapStandard", func(): rpc("sync_lobby_selection", 1, "map", "Standard Field"))
	_connect_button("MapChaos", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Obstacle Heavy Chaos"))
	_connect_button("MapPlain", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Open Empty Plain"))
	
	_connect_button("Lives3", func(): rpc("sync_lobby_selection", 1, "lives", "3"))
	_connect_button("Lives5", func(): rpc("sync_lobby_selection", 1, "lives", "5"))
	_connect_button("Lives7", func(): rpc("sync_lobby_selection", 1, "lives", "7"))

	# Manage Start button permissions exclusively for Host server machine
	if multiplayer.multiplayer_peer != null:
		if not multiplayer.is_server():
			if start_match_button:
				start_match_button.text = "WAITING FOR HOST..."
				start_match_button.disabled = true
		else:
			if start_match_button: start_match_button.pressed.connect(_on_start_match_pressed)
	else:
		if start_match_button: start_match_button.pressed.connect(_on_start_match_pressed)

# --- 📡 INSTRUCTION FIXED: THE UNIFIED LOBBY SELECTION RPC ---
@rpc("any_peer", "call_local", "reliable")
func sync_lobby_selection(peer_id: int, selection_type: String, value: String) -> void:
	var is_p1 = (peer_id == 1)
	
	match selection_type:
		"class":
			# 1. Update Global Singelton data registry vault values
			if is_p1:
				GlobalLobby.lobby_selections[1] = value
				GlobalLobby.lobby_skills[1] = "Recons Eye" if value == "Recon" else ("Piercing Shot" if value == "Slingshotter" else "Marksman")
				if p1_choice_label: p1_choice_label.text = "P1 Class: " + value
			else:
				GlobalLobby.lobby_selections[peer_id] = value
				GlobalLobby.lobby_selections["guest"] = value
				GlobalLobby.lobby_skills[peer_id] = "Recons Eye" if value == "Recon" else ("Piercing Shot" if value == "Slingshotter" else "Marksman")
				GlobalLobby.lobby_skills["guest"] = GlobalLobby.lobby_skills[peer_id]
				if p2_choice_label: p2_choice_label.text = "P2 Class: " + value
				
			# 2. INSTRUCTION FIXED: POPULATE THE ABILITIES CONTAINER DYNAMICALLY
			var target_container = p1_abilities_container if is_p1 else p2_abilities_container
			if target_container:
				# Clear old child nodes completely using queue_free()
				for child in target_container.get_children():
					child.queue_free()
					
				# Filter out specialized layout perk lists
				var valid_skills: Array[String] = []
				match value:
					"Recon": valid_skills = ["Recons Eye", "Recons Will"]
					"Slingshotter": valid_skills = ["Piercing Shot", "Bouncing Shot"]
					"Cowboy": valid_skills = ["Marksman", "Jerry Miculek"]
					
				# Instance and add new matching buttons into the VBox so they visually pop up on both screens!
				for skill in valid_skills:
					var skill_btn = Button.new()
					skill_btn.text = skill
					skill_btn.custom_minimum_size = Vector2(180, 35)
					skill_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
					
					skill_btn.pressed.connect(func():
						rpc("sync_lobby_selection", peer_id, "ability", skill)
					)
					target_container.add_child(skill_btn)
					
		"ability":
			if is_p1:
				GlobalLobby.lobby_skills[1] = value
				print("💙 P1 Locked Ability: ", value)
			else:
				GlobalLobby.lobby_skills[peer_id] = value
				GlobalLobby.lobby_skills["guest"] = value
				print("🔴 P2 Locked Ability: ", value)
				
		"map":
			# INSTRUCTION FIXED: Update central variable and highlight chosen button layout
			GlobalLobby.selected_map = value
			_highlight_selected_button_group(["MapStandard", "MapChaos", "MapPlain"], "Map" + value.get_slice(" ", 0))
			print("🌍 Central Map Sync: ", value)
			
		"lives":
			# INSTRUCTION FIXED: Update central variable and highlight chosen button layout
			GlobalLobby.starting_lives_setting = value.to_int()
			_highlight_selected_button_group(["Lives3", "Lives5", "Lives7"], "Lives" + value)
			print("🔢 Central Stock Sync: ", value, " Lives")

func _on_start_match_pressed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		print("🚀 Host launching match. Executing screen transaction...")
		rpc("launch_combat_arena", "res://CombatArena.tscn")

@rpc("any_peer", "call_local", "reliable")
func launch_combat_arena(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _connect_button(btn_name: String, callback: Callable) -> void:
	var btn = find_child(btn_name, true, false) as Button
	if btn: btn.pressed.connect(callback)

func _highlight_selected_button_group(group_names: Array, chosen_name: String) -> void:
	# Loops through a selection row, highlighting the clicked option while resetting others!
	for node_name in group_names:
		var btn = find_child(node_name, true, false) as Button
		if btn:
			if node_name.begins_with(chosen_name) or chosen_name.begins_with(node_name):
				btn.self_modulate = Color(0.2, 1.0, 0.5) # Glowing Neon Green Highlight!
			else:
				btn.self_modulate = Color(1.0, 1.0, 1.0) # Reset color back to flat standard white
