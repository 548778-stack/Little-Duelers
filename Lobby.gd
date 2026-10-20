extends Control

# FIXED PATHS: Looking directly for the top-level nested buttons
@onready var start_match_button = $"StartMatchButton" as Button
@onready var p1_abilities_container = find_child("P1AbilitiesContainer", true, false) as VBoxContainer
@onready var p2_abilities_container = find_child("P2AbilitiesContainer", true, false) as VBoxContainer
@onready var p1_choice_label = find_child("P1ChoiceLabel", true, false) as Label
@onready var p2_choice_label = find_child("P2ChoiceLabel", true, false) as Label

func _ready() -> void:
	# --- 🌐 CONNECT THE MANUALLY PRESSED SIGNALS DYNAMICALLY ---
	# Automatically maps your class choices based on server status
	_connect_lobby_button("ReconButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		rpc("sync_lobby_selection", target_id, "class", "Recon")
	)
	_connect_lobby_button("SlingshotterButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		rpc("sync_lobby_selection", target_id, "class", "Slingshotter")
	)
	_connect_lobby_button("CowboyButton", func():
		var target_id = 1 if multiplayer.is_server() else multiplayer.get_unique_id()
		rpc("sync_lobby_selection", target_id, "class", "Cowboy")
	)
	
	# --- FIXED CRASH 3: Redirected map and lives buttons to call our correct RPC function name! ---
	_connect_lobby_button("MapStandard", func(): rpc("sync_lobby_selection", 1, "map", "Standard Field"))
	_connect_lobby_button("MapChaos", func(): rpc("sync_lobby_selection", 1, "map", "Obstacle Heavy Chaos"))
	_connect_lobby_button("MapPlain", func(): rpc("sync_lobby_selection", 1, "map", "Open Empty Plain"))
	
	_connect_lobby_button("Lives3", func(): rpc("sync_lobby_selection", 1, "lives", "3"))
	_connect_lobby_button("Lives5", func(): rpc("sync_lobby_selection", 1, "lives", "5"))
	_connect_lobby_button("Lives7", func(): rpc("sync_lobby_selection", 1, "lives", "7"))

	# Manage button visibility based on server permissions
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

# --- 📡 THE VALID REGISTERED LOBBY RPC WRAPPER TAG ---
@rpc("any_peer", "call_local", "reliable")
func sync_lobby_selection(peer_id: int, selection_type: String, value: String) -> void:
	var is_p1 = (peer_id == 1)
	
	match selection_type:
		"class":
			if is_p1:
				GlobalLobby.lobby_selections[1] = value
				GlobalLobby.lobby_skills[1] = "Recons Eye" if value == "Recon" else ("Piercing Shot" if value == "Slingshotter" else "Marksman")
				if p1_choice_label: p1_choice_label.text = "P1 Class: " + value
				# VISUAL FEEDBACK TOGGLE: Highlight the selected character button for P1 side
				_highlight_selected_button_group(["ReconButton", "SlingshotterButton", "CowboyButton"], value + "Button")
			else:
				GlobalLobby.lobby_selections[peer_id] = value
				GlobalLobby.lobby_selections["guest"] = value
				GlobalLobby.lobby_skills[peer_id] = "Recons Eye" if value == "Recon" else ("Piercing Shot" if value == "Slingshotter" else "Marksman")
				GlobalLobby.lobby_skills["guest"] = GlobalLobby.lobby_skills[peer_id]
				if p2_choice_label: p2_choice_label.text = "P2 Class: " + value
				# VISUAL FEEDBACK TOGGLE: Highlight the selected character button for P2 side
				_highlight_selected_button_group(["ReconButton", "SlingshotterButton", "CowboyButton"], value + "Button")
				
			# Populate Abilities Container dynamically on both screens
			var target_container = p1_abilities_container if is_p1 else p2_abilities_container
			if target_container:
				for child in target_container.get_children():
					child.queue_free()
					
				var valid_skills: Array[String] = []
				match value:
					"Recon": valid_skills = ["Recons Eye", "Recons Will"]
					"Slingshotter": valid_skills = ["Piercing Shot", "Bouncing Shot"]
					"Cowboy": valid_skills = ["Marksman", "Jerry Miculek"]
					
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
			GlobalLobby.selected_map = value
			# VISUAL TOGGLE FEEDBACK: Highlight selected map button on both screens!
			var map_slice = value.get_slice(" ", 0)
			_highlight_selected_button_group(["MapStandard", "MapChaos", "MapPlain"], "Map" + map_slice)
			print("🌍 Central Map Sync: ", value)
			
		"lives":
			GlobalLobby.starting_lives_setting = value.to_int()
			# VISUAL TOGGLE FEEDBACK: Highlight selected lives button on both screens!
			_highlight_selected_button_group(["Lives3", "Lives5", "Lives7"], "Lives" + value)
			print("🔢 Central Stock Sync: ", value, " Lives")

func _on_start_match_pressed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		print("🚀 Host launching match. Executing screen transaction...")
		rpc("launch_combat_arena", "res://CombatArena.tscn")

@rpc("any_peer", "call_local", "reliable")
func launch_combat_arena(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _connect_lobby_button(btn_name: String, callback: Callable) -> void:
	var btn = find_child(btn_name, true, false) as Button
	if btn:
		if btn.pressed.is_connected(callback): return
		btn.pressed.connect(callback)

func _highlight_selected_button_group(group_names: Array, chosen_name: String) -> void:
	# VISUAL CONFIRMATION: Loops through a row group, lighting up the active pick gold/green!
	for node_name in group_names:
		var btn = find_child(node_name, true, false) as Button
		if btn:
			if node_name.to_lower().contains(chosen_name.to_lower()) or chosen_name.to_lower().contains(node_name.to_lower()):
				btn.self_modulate = Color(0.2, 1.0, 0.5) # Vibrant Glowing Neon Green
			else:
				btn.self_modulate = Color(1.0, 1.0, 1.0) # Reset unselected choices back to white standard
