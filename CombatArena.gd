extends Node2D

var player1: CharacterBody2D
var player2: CharacterBody2D

# HUD and Menu UI pointers
var p1_hud_label: Label
var p2_hud_label: Label
var p1_bars: Array[TextureProgressBar] = []
var p2_bars: Array[TextureProgressBar] = []

var menu_layer: CanvasLayer
var game_active: bool = false

# Match settings state tracking data
var vs_ai_mode: bool = false
var p1_selected_character: String = "Slingshotter"
var p1_selected_skill: String = "Piercing Shot"
var p2_selected_character: String = "Slingshotter"
var p2_selected_skill: String = "Piercing Shot"
var selected_map: String = "Standard Field"
var starting_lives_setting: int = 3

# HUD progress bar pointers
var p1_ability_bar: TextureProgressBar
var p2_ability_bar: TextureProgressBar
var p1_abilities_container: VBoxContainer
var p2_abilities_container: VBoxContainer

# --- NEW: P2P NETWORKING VARIABLES ---
const DEFAULT_PORT = 8910
var ip_input_field: LineEdit

func _ready() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	var bg = ColorRect.new()
	bg.size = Vector2(screen_width, screen_height)
	bg.color = Color(0.08, 0.09, 0.12)
	add_child(bg)
	
	# Connect Godot's built-in multiplayer signals to track connections
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	show_main_menu(screen_width, screen_height)

# --- 1. MAIN MENU SCREEN WITH NETWORK HOOKS ---
func show_main_menu(screen_width: float, screen_height: float) -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	
	var container = CenterContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(container)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	container.add_child(vbox)
	
	var title = Label.new()
	title.text = "🎯 TOP-DOWN P2P ARCADE DUEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	vbox.add_child(title)
	
	# Fetch our clean LAN address from the helper routine
	var host_ip = get_my_local_ip()
	
	# NEW: Network Broadcast Info Banner Label
	var ip_label = Label.new()
	ip_label.text = "YOUR MATCH IP: " + host_ip
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2)) # Golden color highlight
	ip_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(ip_label)
	
	# Local VS AI Option Button
	var btn_ai = Button.new()
	btn_ai.text = "VS COMPUTER BOT (OFFLINE)"
	btn_ai.custom_minimum_size = Vector2(320, 50)
	btn_ai.pressed.connect(func(): 
		vs_ai_mode = true
		menu_layer.queue_free()
		show_match_setup_screen()
	)
	vbox.add_child(btn_ai)
	
	var hr = HSeparator.new()
	vbox.add_child(hr)
	
	var net_lbl = Label.new()
	net_lbl.text = "--- LAN MULTIPLAYER SECTION ---"
	net_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(net_lbl)
	
	var btn_host = Button.new()
	btn_host.text = "🖥️ HOST LAN LOBBY"
	btn_host.custom_minimum_size = Vector2(320, 50)
	btn_host.pressed.connect(_on_host_pressed)
	vbox.add_child(btn_host)
	
	ip_input_field = LineEdit.new()
	ip_input_field.placeholder_text = "Enter Host's Local IP Address (e.g. 192.168.1.50)"
	ip_input_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ip_input_field)
	
	var btn_join = Button.new()
	btn_join.text = "🔌 JOIN LAN LOBBY"
	btn_join.custom_minimum_size = Vector2(320, 50)
	btn_join.pressed.connect(_on_join_pressed)
	vbox.add_child(btn_join)

# --- NEW: P2P SOCKET INITIALIZATIONS ---
func _on_host_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 2) # Limit to 2 players max
	if error != OK:
		print("❌ Failed to initialize host server socket node structure!")
		return
	
	multiplayer.multiplayer_peer = peer
	vs_ai_mode = false
	print("📡 Server initialized on port ", DEFAULT_PORT, ". Waiting for peers to join...")
	
	menu_layer.queue_free()
	show_match_setup_screen()
	
func _on_join_pressed() -> void:
	var target_ip = ip_input_field.text.strip_edges()
	
	# If the input box is left completely blank, fallback to hosting machine loopback local test mode
	if target_ip == "":
		target_ip = "127.0.0.1"
		
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, DEFAULT_PORT)
	if error != OK:
		print("❌ Connection initialization request failure!")
		return
		
	multiplayer.multiplayer_peer = peer
	vs_ai_mode = false
	print("🔌 Attempting connection handshake with host address: ", target_ip)
	
	menu_layer.queue_free()

func _on_peer_connected(id: int) -> void:
	print("✅ Peer connected successfully! Network ID assigned: ", id)
	# If we are the host server machine and our friend connected, let's sync up!
	if multiplayer.is_server():
		rpc("sync_lobby_and_start", selected_map, starting_lives_setting, p1_selected_character, p1_selected_skill, p2_selected_character, p2_selected_skill)

func _on_peer_disconnected(id: int) -> void:
	print("🚨 Peer client disconnected: ", id)
	game_active = false
	get_tree().reload_current_scene()

# --- 2. MATCH SETUP SCREEN LAYOUT ---
func show_match_setup_screen() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 20)
	menu_layer.add_child(main_vbox)
	
	var header = Label.new()
	header.text = "⚙️ LOBBY: MATCH CONFIGURATION"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 28)
	main_vbox.add_child(header)
	
	var columns_hbox = HBoxContainer.new()
	columns_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns_hbox.add_theme_constant_override("separation", 50)
	main_vbox.add_child(columns_hbox)
	
	# P1 COLUMN
	var p1_panel = PanelContainer.new()
	p1_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_hbox.add_child(p1_panel)
	var p1_vbox = VBoxContainer.new()
	p1_vbox.add_theme_constant_override("separation", 15)
	p1_panel.add_child(p1_vbox)
	var p1_title = Label.new()
	p1_title.text = "🔵 PLAYER 1 CONFIG"
	p1_title.add_theme_font_size_override("font_size", 20)
	p1_vbox.add_child(p1_title)
	
	var p1_char_lbl = Label.new()
	p1_char_lbl.text = "Select Character Class:"
	p1_vbox.add_child(p1_char_lbl)
	for character_name in ["Recon", "Slingshotter", "Cowboy"]:
		var btn = Button.new()
		btn.text = character_name
		btn.pressed.connect(func(): 
			p1_selected_character = character_name
			update_ability_list(1, character_name)
		)
		p1_vbox.add_child(btn)
		
	var p1_skill_lbl = Label.new()
	p1_skill_lbl.text = "Available Abilities:"
	p1_vbox.add_child(p1_skill_lbl)
	p1_abilities_container = VBoxContainer.new()
	p1_vbox.add_child(p1_abilities_container)

	# CENTER MATCH RULES AREA COLUMN
	var center_panel = PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_hbox.add_child(center_panel)
	var center_vbox = VBoxContainer.new()
	center_vbox.add_theme_constant_override("separation", 15)
	center_panel.add_child(center_vbox)
	var center_title = Label.new()
	center_title.text = "🌍 ARENA SETTINGS"
	center_title.add_theme_font_size_override("font_size", 20)
	center_vbox.add_child(center_title)
	
	var map_lbl = Label.new()
	map_lbl.text = "Select Map Arena:"
	center_vbox.add_child(map_lbl)
	for map_name in ["Standard Field", "Obstacle Heavy Chaos", "Open Empty Plain"]:
		var btn = Button.new()
		btn.text = map_name
		btn.pressed.connect(func(): selected_map = map_name)
		center_vbox.add_child(btn)
		
	var rules_lbl = Label.new()
	rules_lbl.text = "Adjust Match Lives Limit Pool:"
	center_vbox.add_child(rules_lbl)
	for stock_count in [3, 5, 7]:
		var btn = Button.new()
		btn.text = str(stock_count) + " Total Stocks"
		btn.pressed.connect(func(): starting_lives_setting = stock_count)
		center_vbox.add_child(btn)

	# P2 COLUMN
	var p2_panel = PanelContainer.new()
	p2_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_hbox.add_child(p2_panel)
	var p2_vbox = VBoxContainer.new()
	p2_vbox.add_theme_constant_override("separation", 15)
	p2_panel.add_child(p2_vbox)
	var p2_title = Label.new()
	p2_title.text = "🔴 COMPUTER BOT CONFIG" if vs_ai_mode else "🔴 PLAYER 2 CONFIG"
	p2_title.add_theme_font_size_override("font_size", 20)
	p2_vbox.add_child(p2_title)
	
	var p2_char_lbl = Label.new()
	p2_char_lbl.text = "Select Character Class:"
	p2_vbox.add_child(p2_char_lbl)
	for character_name in ["Recon", "Slingshotter", "Cowboy"]:
		var btn = Button.new()
		btn.text = character_name
		btn.pressed.connect(func(): 
			p2_selected_character = character_name
			update_ability_list(2, character_name)
		)
		p2_vbox.add_child(btn)
		
	var p2_skill_lbl = Label.new()
	p2_skill_lbl.text = "Available Abilities:"
	p2_vbox.add_child(p2_skill_lbl)
	p2_abilities_container = VBoxContainer.new()
	p2_vbox.add_child(p2_abilities_container)

	update_ability_list(1, p1_selected_character)
	update_ability_list(2, p2_selected_character)

	var footer_spacer = Control.new()
	footer_spacer.custom_minimum_size = Vector2(0, 10)
	main_vbox.add_child(footer_spacer)
	
	var start_btn = Button.new()
	start_btn.text = "🚀 START COMBAT arena"
	start_btn.custom_minimum_size = Vector2(400, 60)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.add_theme_font_size_override("font_size", 22)
	start_btn.pressed.connect(_on_setup_finished)
	main_vbox.add_child(start_btn)

func update_ability_list(player_num: int, class_type: String) -> void:
	var container = p1_abilities_container if player_num == 1 else p2_abilities_container
	for child in container.get_children(): child.queue_free()
	var valid_skills: Array[String] = []
	match class_type:
		"Recon": valid_skills = ["Recons Eye", "Recons Will"]
		"Slingshotter": valid_skills = ["Piercing Shot", "Bouncing Shot"]
		"Cowboy": valid_skills = ["Marksman", "Jerry Miculek"]
		
	if player_num == 1: p1_selected_skill = valid_skills[0]
	else: p2_selected_skill = valid_skills[0]
	
	for skill in valid_skills:
		var btn = Button.new()
		btn.text = skill
		btn.pressed.connect(func():
			if player_num == 1: p1_selected_skill = skill
			else: p2_selected_skill = skill
		)
		container.add_child(btn)

func _on_setup_finished() -> void:
	if vs_ai_mode or not multiplayer.multiplayer_peer != null:
		menu_layer.queue_free()
		start_match()
	else:
		print("📡 Host launching match. Distributing rules payload across LAN network sockets...")
		rpc("sync_lobby_and_start", selected_map, starting_lives_setting, p1_selected_character, p1_selected_skill, p2_selected_character, p2_selected_skill)

# --- RPC CALL: NETWORK PAYLOAD MIRROR ---
@rpc("any_peer", "call_local", "reliable")
func sync_lobby_and_start(m_map, m_lives, p1_c, p1_s, p2_c, p2_s) -> void:
	selected_map = m_map
	starting_lives_setting = m_lives
	p1_selected_character = p1_c
	p1_selected_skill = p1_s
	p2_selected_character = p2_c
	p2_selected_skill = p2_s
	
	if is_instance_valid(menu_layer):
		menu_layer.queue_free()
	start_match()

func spawn_center_obstacles(screen_width: float, screen_height: float, min_c: int, max_c: int) -> void:
	var center_x = screen_width / 2
	var number_of_obstacles = randi_range(min_c, max_c)
	var sector_height = screen_height / number_of_obstacles
	for i in range(number_of_obstacles):
		if randf() > 0.7: continue
		var obstacle = StaticBody2D.new()
		obstacle.name = "Obstacle_" + str(i)
		add_child(obstacle)
		var rand_y = (i * sector_height) + randf_range(40.0, sector_height - 40.0)
		obstacle.position = Vector2(center_x + randf_range(-50.0, 50.0), rand_y)
		var block_width = randf_range(30.0, 60.0)
		var block_height = randf_range(50.0, 110.0)
		var visual = ColorRect.new()
		visual.size = Vector2(block_width, block_height)
		visual.position = -visual.size / 2
		visual.color = Color(0.35, 0.38, 0.42)
		obstacle.add_child(visual)
		var collider = CollisionShape2D.new()
		var box_shape = RectangleShape2D.new()
		box_shape.size = visual.size
		collider.shape = box_shape
		obstacle.add_child(collider)

func _draw() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	var center_x = screen_width / 2.0
	var center_y = screen_height / 2.0
	
	# Choose a color for your boundary lines (e.g., a subtle semi-transparent gray)
	var line_color = Color(0.25, 0.28, 0.35, 0.6)
	var line_thickness = 4.0
	
	# 1. Draw Vertical Split Line (Y-Axis in the middle)
	draw_line(Vector2(center_x, 0), Vector2(center_x, screen_height), line_color, line_thickness)
	
	# 2. Draw Horizontal Split Line (X-Axis in the middle)
	draw_line(Vector2(0, center_y), Vector2(screen_width, center_y), line_color, line_thickness)

# Append this function to the very bottom of your CombatArena.gd file

func get_my_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	
	# PRIORITY 1: Force find your exact high school lab network sequence
	for ip in addresses:
		if ip.begins_with("10.220."):
			return ip
			
	# PRIORITY 2: Standard school LAN ranges
	for ip in addresses:
		if not ":" in ip and ip != "127.0.0.1":
			if ip.begins_with("10.") or ip.begins_with("172."):
				return ip
				
	# PRIORITY 3: Home routers or fallbacks (skipping known virtual networks if possible)
	for ip in addresses:
		if not ":" in ip and ip != "127.0.0.1":
			if ip.begins_with("192.168.") and not ip.contains(".145."):
				return ip
				
	# Final fallback catch-all loop
	for ip in addresses:
		if not ":" in ip and ip != "127.0.0.1":
			return ip
			
	return "127.0.0.1"

# Replace EVERYTHING from start_match() down to the very end of your CombatArena.gd file:

func start_match() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	# Preload the scene instead of a script
	var player_scene = preload("res://Player.tscn")
	
	# ONLY THE HOST/SERVER SPAWNS THE PHYSICAL NODES
	if multiplayer.is_server() or multiplayer.multiplayer_peer == null:
		# --- SPAWN PLAYER 1 ---
		player1 = player_scene.instantiate()
		player1.name = "Player1"
		add_child(player1) # MultiplayerSpawner automatically duplicates this to the guest!
		player1.position = Vector2(120, screen_height / 2)
		player1.setup_player(1, false, p1_selected_character, p1_selected_skill)
		player1.lives = starting_lives_setting
		
		if multiplayer.multiplayer_peer != null:
			player1.set_multiplayer_authority(1)
			# Add synchronizer
			var sync1 = MultiplayerSynchronizer.new()
			var config1 = SceneReplicationConfig.new()
			config1.add_property(^":position")
			sync1.replication_config = config1
			player1.add_child(sync1)

		# --- SPAWN PLAYER 2 ---
		player2 = player_scene.instantiate()
		player2.name = "Player2"
		add_child(player2) # MultiplayerSpawner automatically duplicates this to the guest!
		player2.position = Vector2(screen_width - 120, screen_height / 2)
		player2.setup_player(2, vs_ai_mode, p2_selected_character, p2_selected_skill)
		player2.lives = starting_lives_setting
		
		if multiplayer.multiplayer_peer != null:
			var client_peer_id = multiplayer.get_peers()[0]
			player2.set_multiplayer_authority(client_peer_id)
			# Add synchronizer
			var sync2 = MultiplayerSynchronizer.new()
			var config2 = SceneReplicationConfig.new()
			config2.add_property(^":position")
			sync2.replication_config = config2
			player2.add_child(sync2)
	# --- ALL MACHINES RUN CODE BELOW (HUD, Visuals, Map) ---
	# Note: If your setup_player() function handles adding the ColorRect and Colliders, 
	# make sure it runs inside the Player.gd's _ready() function so the guest gets visuals too!
	
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		var min_obs = 3 if selected_map == "Standard Field" else 6
		var max_obs = 5 if selected_map == "Standard Field" else 9
		if selected_map != "Open Empty Plain":
			generate_and_sync_obstacles(screen_width, screen_height, min_obs, max_obs)
	
	setup_hud(screen_width)
	game_active = true
	queue_redraw()


# NEW RPC ENGINE: Broadcasts the exact obstacle coordinates from the host PC down to the Guest
func generate_and_sync_obstacles(screen_width: float, screen_height: float, min_c: int, max_c: int) -> void:
	var center_x = screen_width / 2
	var number_of_obstacles = randi_range(min_c, max_c)
	var sector_height = screen_height / number_of_obstacles
	
	for i in range(number_of_obstacles):
		if randf() > 0.7: continue
		var rand_y = (i * sector_height) + randf_range(40.0, sector_height - 40.0)
		var pos = Vector2(center_x + randf_range(-50.0, 50.0), rand_y)
		var b_width = randf_range(30.0, 60.0)
		var b_height = randf_range(50.0, 110.0)
		
		# Build it locally on the Host PC screen
		spawn_local_obstacle(i, pos, Vector2(b_width, b_height))
		
		# If online, broadcast these exact sizes and coordinates to the Guest PC instantly
		if multiplayer.multiplayer_peer != null and multiplayer.is_server():
			rpc("spawn_local_obstacle", i, pos, Vector2(b_width, b_height))
			
@rpc("any_peer", "call_remote", "reliable")
func spawn_local_obstacle(id: int, obs_position: Vector2, obs_size: Vector2) -> void:
	var obstacle = StaticBody2D.new()
	obstacle.name = "Obstacle_" + str(id)
	add_child(obstacle)
	obstacle.position = obs_position
	
	var visual = ColorRect.new()
	visual.size = obs_size
	visual.position = -visual.size / 2
	visual.color = Color(0.35, 0.38, 0.42)
	obstacle.add_child(visual)
	
	var collider = CollisionShape2D.new()
	var box_shape = RectangleShape2D.new()
	box_shape.size = obs_size
	collider.shape = box_shape
	obstacle.add_child(collider)

func setup_hud(screen_width: float) -> void:
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	main_hbox.custom_minimum_size = Vector2(screen_width, 100)
	canvas_layer.add_child(main_hbox)
	var img = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var white_texture = ImageTexture.create_from_image(img)
	
	var p1_vbox = VBoxContainer.new()
	p1_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(p1_vbox)
	p1_hud_label = Label.new()
	p1_hud_label.add_theme_font_size_override("font_size", 20)
	p1_hud_label.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	p1_vbox.add_child(p1_hud_label)
	var p1_bars_row = HBoxContainer.new()
	p1_bars_row.add_theme_constant_override("separation", 6)
	p1_vbox.add_child(p1_bars_row)
	p1_bars.clear()
	for i in range(3):
		var bar = TextureProgressBar.new()
		bar.custom_minimum_size = Vector2(50, 6)
		bar.texture_progress = white_texture
		bar.tint_under = Color(0.2, 0.2, 0.2)
		bar.tint_progress = Color(1.0, 0.85, 0.2)
		bar.max_value = 100
		p1_bars_row.add_child(bar)
		p1_bars.append(bar)
	p1_ability_bar = TextureProgressBar.new()
	p1_ability_bar.custom_minimum_size = Vector2(162, 6)
	p1_ability_bar.texture_progress = white_texture
	p1_ability_bar.tint_under = Color(0.15, 0.15, 0.15)
	p1_ability_bar.tint_progress = Color(0.2, 1.0, 0.5)
	p1_ability_bar.max_value = 100
	p1_vbox.add_child(p1_ability_bar)
	
	var middle_spacer = Control.new()
	middle_spacer.custom_minimum_size = Vector2(40, 0)
	main_hbox.add_child(middle_spacer)
	
	var p2_vbox = VBoxContainer.new()
	p2_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(p2_vbox)
	p2_hud_label = Label.new()
	p2_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_hud_label.add_theme_font_size_override("font_size", 20)
	p2_hud_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	p2_vbox.add_child(p2_hud_label)
	var p2_bars_row = HBoxContainer.new()
	p2_bars_row.add_theme_constant_override("separation", 6)
	p2_bars_row.alignment = BoxContainer.ALIGNMENT_END
	p2_vbox.add_child(p2_bars_row)
	p2_bars.clear()
	for i in range(3):
		var bar = TextureProgressBar.new()
		bar.custom_minimum_size = Vector2(50, 6)
		bar.texture_progress = white_texture
		bar.tint_under = Color(0.2, 0.2, 0.2)
		bar.tint_progress = Color(1.0, 0.85, 0.2)
		bar.max_value = 100
		p2_bars_row.add_child(bar)
		p2_bars.append(bar)
	p2_ability_bar = TextureProgressBar.new()
	p2_ability_bar.custom_minimum_size = Vector2(162, 6)
	p2_ability_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	p2_ability_bar.texture_progress = white_texture
	p2_ability_bar.tint_under = Color(0.15, 0.15, 0.15)
	p2_ability_bar.tint_progress = Color(0.2, 1.0, 0.5)
	p2_ability_bar.max_value = 100
	p2_vbox.add_child(p2_ability_bar)

func _process(_delta: float) -> void:
	if not game_active: return
	if is_instance_valid(player1):
		var ammo_info = player1.get_ammo_string()
		var skill_info = player1.get_ability_status_string()
		p1_hud_label.text = "  💙 P1 Lives: " + str(player1.lives) + " | HP: " + str(player1.current_health) + "/" + str(player1.max_health) + ammo_info + skill_info
		p1_ability_bar.value = player1.get_ability_cooldown_percentage() * 100.0
		for i in range(3): p1_bars[i].value = player1.get_individual_bar_progress(i) * 100.0
	if is_instance_valid(player2):
		var ammo_info = player2.get_ammo_string()
		var skill_info = player2.get_ability_status_string()
		p2_hud_label.text = skill_info + ammo_info + " | P2 Lives: " + str(player2.lives) + " | HP: " + str(player2.current_health) + "/" + str(player2.max_health) + " ❤️  "
		p2_ability_bar.value = player2.get_ability_cooldown_percentage() * 100.0
		for i in range(3): p2_bars[i].value = player2.get_individual_bar_progress(i) * 100.0
		
		
	################## For debugging - checks guest input#########################
	############################DELETE LATER######################################
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		# Check if player2 exists before trying to print its position
		if has_node("CharacterBody2D") or is_instance_valid(player2):
			print("Host Node - Guest Player Position: ", player2.position)
	##################################################################################

func spawn_hit_particles(hit_position: Vector2, particle_color: Color) -> void:
	var particles = CPUParticles2D.new()
	add_child(particles)
	particles.global_position = hit_position
	particles.amount = 25
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 150.0
	particles.initial_velocity_max = 250.0
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 8.0
	particles.color = particle_color
	get_tree().create_timer(particles.lifetime).timeout.connect(particles.queue_free)

func trigger_game_over(eliminated_player_id: int) -> void:
	game_active = false
	var winner_id = 2 if eliminated_player_id == 1 else 1
	if is_instance_valid(player1): player1.set_physics_process(false)
	if is_instance_valid(player2): player2.set_physics_process(false)
	var container = CenterContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	container.add_child(vbox)
	var win_label = Label.new()
	win_label.text = "🏆 PLAYER " + str(winner_id) + " WINS! 🏆"
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 48)
	vbox.add_child(win_label)
	var restart_label = Label.new()
	restart_label.text = "Press 'R' key to return to Main Menu"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(restart_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			# FIXED: Safely wipe network connections before reloading to prevent Host crash
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.close()
				multiplayer.multiplayer_peer = null
			print("🔄 Safely cleaning up network sessions... Returning to Menu.")
			get_tree().reload_current_scene()
