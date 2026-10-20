extends Control

# --- 🛠️ 1. RESTORED PATH HIERARCHY ---
# We use dynamic find_child lookups so Godot locates your UI nodes no matter where they are nested
@onready var start_match_button = find_child("StartMatchButton", true, false) as Button
@onready var p1_abilities_container = find_child("P1AbilitiesContainer", true, false) as VBoxContainer
@onready var p2_abilities_container = find_child("P2AbilitiesContainer", true, false) as VBoxContainer
@onready var p1_choice_label = find_child("P1ChoiceLabel", true, false) as Label
@onready var p2_choice_label = find_child("P2ChoiceLabel", true, false) as Label

# Central configuration data tracking dictionary
var character_data: Dictionary = {
	"Recon": {"abilities": ["Recons Eye", "Sensor Dart", "Cloak"]},
	"Slingshotter": {"abilities": ["Piercing Shot", "Bouncing Shot", "Grapnel Trick"]},
	"Cowboy": {"abilities": ["Marksman", "Jerry Miculek", "Deadeye Reload"]}
}

func _ready() -> void:
	# Verify that your StartMatchButton path found its target cleanly
	if not start_match_button:
		print("⚠️ Warning: StartMatchButton not found via dynamic search path. Verify node spelling in Lobby.tscn.")

	# --- WIRE UP PLAYER 1 SELECTION BUTTONS ---
	_connect_lobby_button("P1Recon", func():
		var target_id = 1 if multiplayer.multiplayer_peer == null or multiplayer.is_server() else multiplayer.get_unique_id()
		print("Custom Click Log: P1 chose character: Recon")
		rpc("rpc_sync_lobby_choice", target_id, "class", "Recon")
	)
	_connect_lobby_button("P1Slingshotter", func():
		var target_id = 1 if multiplayer.multiplayer_peer == null or multiplayer.is_server() else multiplayer.get_unique_id()
		print("Custom Click Log: P1 chose character: Slingshotter")
		rpc("rpc_sync_lobby_choice", target_id, "class", "Slingshotter")
	)
	_connect_lobby_button("P1Cowboy", func():
		var target_id = 1 if multiplayer.multiplayer_peer == null or multiplayer.is_server() else multiplayer.get_unique_id()
		print("Custom Click Log: P1 chose character: Cowboy")
		rpc("rpc_sync_lobby_choice", target_id, "class", "Cowboy")
	)
	
	# --- WIRE UP PLAYER 2 SELECTION BUTTONS (WITH ONLINE INPUT GUARD) ---
	_connect_lobby_button("P2Recon", func():
		if not NetworkManager.vs_ai and multiplayer.multiplayer_peer != null and multiplayer.is_server():
			print("🚫 Guard Lockout: Host cannot choose characters for a real human guest client!")
			return
		var target_id = 2 if NetworkManager.vs_ai else (multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 2)
		print("Custom Click Log: P2 Setup routed to Slot ID: ", target_id)
		rpc("rpc_sync_lobby_choice", target_id, "class", "Recon")
	)
	_connect_lobby_button("P2Slingshotter", func():
		if not NetworkManager.vs_ai and multiplayer.multiplayer_peer != null and multiplayer.is_server():
			print("🚫 Guard Lockout: Host cannot choose characters for a real human guest client!")
			return
		var target_id = 2 if NetworkManager.vs_ai else (multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 2)
		print("Custom Click Log: P2 Setup routed to Slot ID: ", target_id)
		rpc("rpc_sync_lobby_choice", target_id, "class", "Slingshotter")
	)
	_connect_lobby_button("P2Cowboy", func():
		if not NetworkManager.vs_ai and multiplayer.multiplayer_peer != null and multiplayer.is_server():
			print("🚫 Guard Lockout: Host cannot choose characters for a real human guest client!")
			return
		var target_id = 2 if NetworkManager.vs_ai else (multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 2)
		print("Custom Click Log: P2 Setup routed to Slot ID: ", target_id)
		rpc("rpc_sync_lobby_choice", target_id, "class", "Cowboy")
	)
	
	# --- WIRE UP CENTRAL COLUMN ROW BUTTONS ---
	_connect_lobby_button("MapStandard", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Standard Field"))
	_connect_lobby_button("MapChaos", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Obstacle Heavy Chaos"))
	_connect_lobby_button("MapPlain", func(): rpc("rpc_sync_lobby_choice", 1, "map", "Open Empty Plain"))
	
	_connect_lobby_button("Lives3", func(): rpc("rpc_sync_lobby_choice", 1, "lives", "3"))
	_connect_lobby_button("Lives5", func(): rpc("rpc_sync_lobby_choice", 1, "lives", "5"))
	_connect_lobby_button("Lives7", func(): rpc("rpc_sync_lobby_choice", 1, "lives", "7"))

	# Manage Start Match interface permissions exclusively for Host server
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

# --- 🛠️ 3. DYNAMIC ABILITIES CONTAINER GENERATOR FUNCTION ---
func update_abilities_ui(peer_id: int, character_name: String) -> void:
	var target_container = p1_abilities_container if peer_id == 1 else p2_abilities_container
	if not target_container: return
		
	for child in target_container.get_children():
		child.queue_free()
		
	if character_data.has(character_name):
		var abilities_array = character_data[character_name]["abilities"]
		for ability_string in abilities_array:
			var btn = Button.new()
			btn.text = ability_string
			btn.custom_minimum_size = Vector2(180, 35)
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			
			btn.pressed.connect(func():
				print("🎯 Ability pressed: ", ability_string, " for Player ID: ", peer_id)
				rpc("rpc_sync_lobby_choice", peer_id, "ability", ability_string)
			)
			target_container.add_child(btn)

# --- 📡 2. THE COMPLETED REGISTRATION LOBBY SYNC RPC (FIXED UNIFIED NAME AND ANNOTATION) ---
# Inside Lobby.gd -> Update your rpc_sync_lobby_choice function:

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_lobby_choice(peer_id: int, selection_type: String, value: String) -> void:
	match selection_type:
		"class":
			print("🖱️ Player ID ", peer_id, " chose class character: ", value)
			
			# INSTRUCTION FIXED: Save choice to the Global Autoload on Click using exact structure [0.1]!
			var first_ability = character_data[value]["abilities"][0]
			NetworkManager.player_choices[peer_id] = {"class": value, "ability": first_ability}
			
			# Mirror fallback for safety assignments
			if peer_id != 1: 
				NetworkManager.player_choices["guest"] = {"class": value, "ability": first_ability}
			
			if peer_id == 1:
				if p1_choice_label: p1_choice_label.text = "P1 Class: " + value
				_highlight_selected_button_group(["P1Recon", "P1Slingshotter", "P1Cowboy"], "P1" + value, Color(0.2, 0.6, 1.0))
			else:
				if p2_choice_label: p2_choice_label.text = "P2 Class: " + value
				_highlight_selected_button_group(["P2Recon", "P2Slingshotter", "P2Cowboy"], "P2" + value, Color(1.0, 0.3, 0.3))
				
			update_abilities_ui(peer_id, value)
					
		"ability":
			print("📡 Ability synchronized: ", value)
			# INSTRUCTION FIXED: Update only the ability string inside your global choice dictionary layout [0.1]!
			if NetworkManager.player_choices.has(peer_id):
				NetworkManager.player_choices[peer_id]["ability"] = value
			if peer_id != 1 and NetworkManager.player_choices.has("guest"):
				NetworkManager.player_choices["guest"]["ability"] = value
				
		"map":
			NetworkManager.selected_map = value
			var target_button_name = ""
			if value == "Standard Field": target_button_name = "MapStandard"
			elif value == "Obstacle Heavy Chaos": target_button_name = "MapChaos"
			elif value == "Open Empty Plain": target_button_name = "MapPlain"
			_highlight_selected_button_group(["MapStandard", "MapChaos", "MapPlain"], target_button_name, Color(0.2, 1.0, 0.5))
			
		"lives":
			NetworkManager.starting_lives = value.to_int()
			_highlight_selected_button_group(["Lives3", "Lives5", "Lives7"], "Lives" + value, Color(0.2, 1.0, 0.5))

func _on_start_match_pressed() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		print("🚀 Host launching match panels...")
		NetworkManager.rpc("change_scene", "res://CombatArena.tscn")

func _connect_lobby_button(btn_name: String, callback: Callable) -> void:
	var btn = find_child(btn_name, true, false) as Button
	if btn:
		if btn.pressed.is_connected(callback): return
		btn.pressed.connect(callback)

func _highlight_selected_button_group(group_names: Array, chosen_name: String, highlight_color: Color) -> void:
	for node_name in group_names:
		var btn = find_child(node_name, true, false) as Button
		if btn:
			if node_name.to_lower() == chosen_name.to_lower() or node_name.to_lower().contains(chosen_name.to_lower()) or chosen_name.to_lower().contains(node_name.to_lower()):
				btn.self_modulate = highlight_color
			else:
				btn.self_modulate = Color(1.0, 1.0, 1.0) # Reset back to flat standard white
