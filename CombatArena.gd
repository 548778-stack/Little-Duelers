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

# --- P2P NETWORKING CONSTANTS ---
const DEFAULT_PORT = 8910

func _ready() -> void:
	# Connect Godot's built-in multiplayer signals to track connections
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Visual layout scenes: Main menu is handled directly by your MainMenu.tscn now!
	print("🎯 Arena Initialized. Waiting for menu selection hooks...")

func _on_host_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 2)
	if error != OK:
		print("❌ Failed to initialize host server socket!")
		return
	
	multiplayer.multiplayer_peer = peer
	vs_ai_mode = false
	print("📡 Server initialized on port ", DEFAULT_PORT)

func _on_join_pressed(target_ip: String) -> void:
	var ip = target_ip.strip_edges()
	if ip == "": ip = "127.0.0.1"
		
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		print("❌ Connection request failure!")
		return
		
	multiplayer.multiplayer_peer = peer
	vs_ai_mode = false
	print("🔌 Connecting to host address: ", ip)

func _on_peer_connected(id: int) -> void:
	print("✅ Peer connected successfully! ID: ", id)
	if multiplayer.is_server():
		rpc("sync_lobby_and_start", selected_map, starting_lives_setting, p1_selected_character, p1_selected_skill, p2_selected_character, p2_selected_skill)

func _on_peer_disconnected(id: int) -> void:
	print("🚨 Peer client disconnected: ", id)
	game_active = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()

@rpc("any_peer", "call_local", "reliable")
func sync_lobby_and_start(m_map, m_lives, p1_c, p1_s, p2_c, p2_s) -> void:
	selected_map = m_map
	starting_lives_setting = m_lives
	p1_selected_character = p1_c
	p1_selected_skill = p1_s
	p2_selected_character = p2_c
	p2_selected_skill = p2_s
	
	start_match()

# --- 3. ARENA GENERATION & LIVE COMBAT ---
func start_match() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	# Preload the scene instead of constructing nodes manually
	var player_scene = preload("res://Player.tscn")
	
	# ONLY THE HOST/SERVER SPAWNS THE PHYSICAL NODES
	if multiplayer.is_server() or multiplayer.multiplayer_peer == null:
		# --- SPAWN PLAYER 1 ---
		player1 = player_scene.instantiate()
		player1.name = "Player1"
		add_child(player1) # MultiplayerSpawner automatically copies this to the guest!
		player1.position = Vector2(120, screen_height / 2)
		
		if multiplayer.multiplayer_peer != null:
			player1.set_multiplayer_authority(1)

		# --- SPAWN PLAYER 2 ---
		player2 = player_scene.instantiate()
		player2.name = "Player2"
		add_child(player2) # MultiplayerSpawner automatically copies this to the guest!
		player2.position = Vector2(screen_width - 120, screen_height / 2)
		
		if multiplayer.multiplayer_peer != null:
			var client_peer_id = multiplayer.get_peers()[0] if multiplayer.get_peers().size() > 0 else 1
			player2.set_multiplayer_authority(client_peer_id)
			
	# --- ALL MACHINES RUN CODE BELOW (HUD, Visuals, Map) ---
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		var min_obs = 3 if selected_map == "Standard Field" else 6
		var max_obs = 5 if selected_map == "Standard Field" else 9
		if selected_map != "Open Empty Plain":
			generate_and_sync_obstacles(screen_width, screen_height, min_obs, max_obs)
	
	setup_hud(screen_width)
	game_active = true
	queue_redraw()

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
		
		spawn_local_obstacle(i, pos, Vector2(b_width, b_height))
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
	
	# Automatically attach local script pointers if nodes just arrived over the network
	if player1 == null and has_node("Player1"): player1 = get_node("Player1")
	if player2 == null and has_node("Player2"): player2 = get_node("Player2")
	
	if is_instance_valid(player1):
		var ammo_info = player1.get_ammo_string() if player1.has_method("get_ammo_string") else ""
		var skill_info = player1.get_ability_status_string() if player1.has_method("get_ability_status_string") else ""
		p1_hud_label.text = "  💙 P1 Lives: " + str(player1.lives) + " | HP: " + str(player1.current_health) + "/" + str(player1.max_health) + ammo_info + skill_info
		if player1.has_method("get_ability_cooldown_percentage"):
			p1_ability_bar.value = player1.get_ability_cooldown_percentage() * 100.0
		if player1.has_method("get_individual_bar_progress"):
			for i in range(3): p1_bars[i].value = player1.get_individual_bar_progress(i) * 100.0
			
	if is_instance_valid(player2):
		var ammo_info = player2.get_ammo_string() if player2.has_method("get_ammo_string") else ""
		var skill_info = player2.get_ability_status_string() if player2.has_method("get_ability_status_string") else ""
		p2_hud_label.text = skill_info + ammo_info + " | P2 Lives: " + str(player2.lives) + " | HP: " + str(player2.current_health) + "/" + str(player2.max_health) + " ❤️  "
		if player2.has_method("get_ability_cooldown_percentage"):
			p2_ability_bar.value = player2.get_ability_cooldown_percentage() * 100.0
		if player2.has_method("get_individual_bar_progress"):
			for i in range(3): p2_bars[i].value = player2.get_individual_bar_progress(i) * 100.0

func _draw() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	var center_x = screen_width / 2.0
	var center_y = screen_height / 2.0
	var line_color = Color(0.25, 0.28, 0.35, 0.6)
	var line_thickness = 4.0
	
	draw_line(Vector2(center_x, 0), Vector2(center_x, screen_height), line_color, line_thickness)
	draw_line(Vector2(0, center_y), Vector2(screen_width, center_y), line_color, line_thickness)

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
			if multiplayer.multiplayer_peer != null:
				multiplayer.multiplayer_peer.close()
				multiplayer.multiplayer_peer = null
			get_tree().reload_current_scene()
