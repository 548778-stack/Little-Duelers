extends Control

@onready var start_match_button = $StartMatchButton as Button

# Local UI label pointers (Make sure these node names match your Lobby.tscn setup!)
@onready var p1_choice_label = find_child("P1ChoiceLabel", true, false) as Label
@onready var p2_choice_label = find_child("P2ChoiceLabel", true, false) as Label
@onready var map_choice_label = find_child("MapChoiceLabel", true, false) as Label
@onready var lives_choice_label = find_child("LivesChoiceLabel", true, false) as Label

func _ready() -> void:
	# Connect your character class selection buttons
	_connect_button("P1Recon", func(): rpc("rpc_sync_lobby_choice", 1, "class", "Recon"))
	_connect_button("P1Slingshotter", func(): rpc("rpc_sync_lobby_choice", 1, "class", "Slingshotter"))
	_connect_button("P1Cowboy", func(): rpc("rpc_sync_lobby_choice", 1, "class", "Cowboy"))
	
	_connect_button("P2Recon", func(): rpc("rpc_sync_lobby_choice", multiplayer.get_unique_id(), "class", "Recon"))
	_connect_button("P2Slingshotter", func(): rpc("rpc_sync_lobby_choice", multiplayer.get_unique_id(), "class", "Slingshotter"))
	_connect_button("P2Cowboy", func(): rpc("rpc_sync_lobby_choice", multiplayer.get_unique_id(), "class", "Cowboy"))
	
	# Connect your map layout buttons
	_connect_button("MapStandard", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Standard Field"))
	_connect_button("MapChaos", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Obstacle Heavy Chaos"))
	_connect_button("MapPlain", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Open Empty Plain"))
	
	# Connect your live stock option buttons
	_connect_button("Lives3", func(): rpc("rpc_sync_lobby_choice", 1, "lives", "3"))
	_connect_button("Lives5", func(): rpc("rpc_sync_lobby_choice", 1, "lives", "5"))
	_connect_button("Lives7", func(): rpc("rpc_sync_lobby_choice", 1, "lives", "7"))

	if multiplayer.multiplayer_peer != null:
		if not multiplayer.is_server():
			if start_match_button:
				start_match_button.text = "WAITING FOR HOST..."
				start_match_button.disabled = true
		else:
			if start_match_button: start_match_button.pressed.connect(_on_start_match_pressed)
	else:
		if start_match_button: start_match_button.pressed.connect(_on_start_match_pressed)

# --- THE REAL-TIME UI SYNC COUPLER RPC ---
@rpc("any_peer", "call_local", "reliable")
func rpc_sync_lobby_choice(peer_id: int, type: String, choice_name: String) -> void:
	# 1. Store choices cleanly into the lifelong background global singleton arrays [0.1]
	match type:
		"class":
			if peer_id == 1:
				GlobalLobby.lobby_selections[1] = choice_name
				# Auto-map standard class ability pairs
				GlobalLobby.lobby_skills[1] = "Recons Eye" if choice_name == "Recon" else ("Piercing Shot" if choice_name == "Slingshotter" else "Marksman")
				if p1_choice_label: p1_choice_label.text = "P1 Class: " + choice_name
			else:
				GlobalLobby.lobby_selections[peer_id] = choice_name
				GlobalLobby.lobby_selections["guest"] = choice_name
				GlobalLobby.lobby_skills[peer_id] = "Recons Eye" if choice_name == "Recon" else ("Piercing Shot" if choice_name == "Slingshotter" else "Marksman")
				GlobalLobby.lobby_skills["guest"] = GlobalLobby.lobby_skills[peer_id]
				if p2_choice_label: p2_choice_label.text = "P2 Class: " + choice_name
		"map":
			GlobalLobby.selected_map = choice_name
			if map_choice_label: map_choice_label.text = "Arena Layout: " + choice_name
		"lives":
			GlobalLobby.starting_lives_setting = choice_name.to_int()
			if lives_choice_label: lives_choice_label.text = "Stock Limit: " + choice_name + " Lives"
			
	print("📡 Real-Time Sync: Peer ID ", peer_id, " locked in ", type, " ➔ ", choice_name)

func _on_start_match_pressed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		print("📡 Host clicked START MATCH. Broadcaster launching game loop...")
		rpc("launch_combat_arena", "res://CombatArena.tscn")

@rpc("any_peer", "call_local", "reliable")
func launch_combat_arena(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _connect_button(btn_name: String, callback: Callable) -> void:
	var btn = find_child(btn_name, true, false) as Button
	if btn: btn.pressed.connect(callback)
