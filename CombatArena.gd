extends Node2D

var player1: CharacterBody2D
var player2: CharacterBody2D

# --- PRESERVED GAME STATE BALANCES ---
var vs_ai_mode: bool = false
var selected_map: String = "Standard Field"
var starting_lives_setting: int = 3
var game_active: bool = false

var p1_selected_character: String = "Slingshotter"
var p1_selected_skill: String = "Piercing Shot"
var p2_selected_character: String = "Slingshotter"
var p2_selected_skill: String = "Piercing Shot"

var active_ability_cooldown_time: float = 5.0

# HUD Node Pointers
var p1_hud_label: Label
var p2_hud_label: Label
var p1_ability_bar: TextureProgressBar
var p2_ability_bar: TextureProgressBar
var p1_bars: Array[TextureProgressBar] = []
var p2_bars: Array[TextureProgressBar] = []

var lobby_selections: Dictionary = {
	1: "Slingshotter",     # Default fallback for Host (ID 1)
	"guest": "Slingshotter" # Default fallback for incoming Guest
}

var lobby_skills: Dictionary = {
	1: "Piercing Shot",
	"guest": "Piercing Shot"
}


# Preload your unified layout character scene asset
const PLAYER_SCENE = preload("res://Player.tscn")
const BOT_SCENE = preload("res://EnemyBot.tscn")

# Update the _ready() loop inside CombatArena.gd to look exactly like this:
func _ready() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	# Generate dark background slate backdrop
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.size = Vector2(1152, 648)
	bg.color = Color(0.08, 0.09, 0.12)
	add_child(bg)
	move_child(bg, 0)
	
	# Create an explicit Container node to wrap map obstacles cleanly
	var obstacles_node = Node2D.new()
	obstacles_node.name = "Obstacles"
	add_child(obstacles_node)
	
	setup_hud(screen_width)
	game_active = true
	queue_redraw()
	
	# Fetch configurations from background NetworkManager Autoload script variables! [0.1]
	selected_map = NetworkManager.selected_map
	starting_lives_setting = NetworkManager.starting_lives
	
	# INSTRUCTION FIXED: Clear or delete the obstacles node loop if map selection choice is clear/plain
	if selected_map == "Open Empty Plain" or selected_map == "clear":
		if has_node("Obstacles"):
			get_node("Obstacles").queue_free()
			print("🧼 Map Setup: Choice string is 'clear'. Deleted obstacles container layer successfully!")
	else:
		if multiplayer.multiplayer_peer == null or multiplayer.is_server():
			var min_obs = 3 if selected_map == "Standard Field" else 6
			var max_obs = 5 if selected_map == "Standard Field" else 9
			generate_map_obstacles(screen_width, screen_height, min_obs, max_obs)
			
	# --- EVENT-DRIVEN PLAYER INSTANTIATION HANDSHAKES ---
	if multiplayer.multiplayer_peer == null or multiplayer.get_unique_id() == 0:
		# Offline fallback
		spawn_player(1, Vector2(120, screen_height / 2))
		spawn_player(2, Vector2(screen_width - 120, screen_height / 2))
	else:
		if multiplayer.is_server():
			spawn_player(1, Vector2(120, screen_height / 2))
			multiplayer.peer_connected.connect(func(id):
				spawn_player(id, Vector2(screen_width - 120, screen_height / 2))
			)

func spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	# INSTRUCTION FIXED: Read Choices Inside spawn_player() right after running instantiate() [0.1]!
	var p_instance = PLAYER_SCENE.instantiate()
	p_instance.name = str(peer_id)
	
	# Fetch final variable configurations securely out of our background NetworkManager autoload vault [0.1]!
	var client_key = peer_id if NetworkManager.lobby_data.has(peer_id) else "guest"
	p_instance.character_class = NetworkManager.lobby_data[client_key]["character"]
	p_instance.selected_ability = NetworkManager.lobby_data[client_key]["ability"]
	p_instance.lives = NetworkManager.starting_lives
	
	# Pass pointer assignments to global trackers
	if peer_id == 1: player1 = p_instance
	else: player2 = p_instance
		
	add_child(p_instance, true) # Force clean human-readable replication name strings
	p_instance.global_position = spawn_position
	print("🚀 Spawned ", p_instance.character_class, " (Node: ", p_instance.name, ") with ", p_instance.lives, " Stocks.")

func _process(delta: float) -> void:
	if not game_active: return
	
	# Fetch and map runtime positions down into variables for HUD processing lookups
	if player1 == null:
		if has_node("1"): player1 = get_node("1")
		elif has_node("Player1"): player1 = get_node("Player1")
	if player2 == null:
		if multiplayer.multiplayer_peer != null:
			for peer in multiplayer.get_peers():
				if has_node(str(peer)): player2 = get_node(str(peer))
		if player2 == null and has_node("Player2"): player2 = get_node("Player2")

	# --- P1 TEXT PRINT LINES ---
	if is_instance_valid(player1):
		var ammo_info = player1.get_ammo_string() if player1.has_method("get_ammo_string") else ""
		var skill_info = player1.get_ability_status_string() if player1.has_method("get_ability_status_string") else ""
		p1_hud_label.text = "  💙 P1 Lives: " + str(player1.lives) + " | HP: " + str(snappedf(player1.current_health, 0.1)) + "/" + str(player1.max_health) + ammo_info + skill_info
		
		var p1_timer = player1.get("local_ability_timer")
		if p1_timer != null:
			p1_ability_bar.value = (p1_timer / active_ability_cooldown_time) * 100.0
		if player1.has_method("get_individual_bar_progress"):
			for i in range(3): p1_bars[i].value = player1.get_individual_bar_progress(i) * 100.0

	# --- P2 TEXT PRINT LINES ---
	if is_instance_valid(player2):
		var ammo_info = player2.get_ammo_string() if player2.has_method("get_ammo_string") else ""
		var skill_info = player2.get_ability_status_string() if player2.has_method("get_ability_status_string") else ""
		p2_hud_label.text = skill_info + ammo_info + " | P2 Lives: " + str(player2.lives) + " | HP: " + str(snappedf(player2.current_health, 0.1)) + "/" + str(player2.max_health) + " ❤️  "
		
		var p2_timer = player2.get("local_ability_timer")
		if p2_timer != null:
			p2_ability_bar.value = (p2_timer / active_ability_cooldown_time) * 100.0
		if player2.has_method("get_individual_bar_progress"):
			for i in range(3): p2_bars[i].value = player2.get_individual_bar_progress(i) * 100.0

func _draw() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	draw_line(Vector2(screen_width / 2.0, 0), Vector2(screen_width / 2.0, screen_height), Color(0.25, 0.28, 0.35, 0.6), 4.0)
	draw_line(Vector2(0, screen_height / 2.0), Vector2(screen_width, screen_height / 2.0), Color(0.25, 0.28, 0.35, 0.6), 4.0)

func generate_map_obstacles(screen_width: float, screen_height: float, min_c: int, max_c: int) -> void:
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
	p1_vbox.add_child(p1_bars_row)
	for i in range(3):
		var bar = TextureProgressBar.new()
		bar.custom_minimum_size = Vector2(50, 6)
		bar.texture_progress = white_texture
		bar.tint_progress = Color(1.0, 0.85, 0.2)
		p1_bars_row.add_child(bar)
		p1_bars.append(bar)
	p1_ability_bar = TextureProgressBar.new()
	p1_ability_bar.custom_minimum_size = Vector2(162, 6)
	p1_ability_bar.texture_progress = white_texture
	p1_ability_bar.tint_progress = Color(0.2, 1.0, 0.5)
	p1_vbox.add_child(p1_ability_bar)
	
	var p2_vbox = VBoxContainer.new()
	p2_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(p2_vbox)
	p2_hud_label = Label.new()
	p2_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_hud_label.add_theme_font_size_override("font_size", 20)
	p2_hud_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	p2_vbox.add_child(p2_hud_label)
	var p2_bars_row = HBoxContainer.new()
	p2_bars_row.alignment = BoxContainer.ALIGNMENT_END
	p2_vbox.add_child(p2_bars_row)
	for i in range(3):
		var bar = TextureProgressBar.new()
		bar.custom_minimum_size = Vector2(50, 6)
		bar.texture_progress = white_texture
		bar.tint_progress = Color(1.0, 0.85, 0.2)
		p2_bars_row.add_child(bar)
		p2_bars.append(bar)
	p2_ability_bar = TextureProgressBar.new()
	p2_ability_bar.custom_minimum_size = Vector2(162, 6)
	p2_ability_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	p2_ability_bar.texture_progress = white_texture
	p2_ability_bar.tint_progress = Color(0.2, 1.0, 0.5)
	p2_vbox.add_child(p2_ability_bar)

func spawn_crit_hit_marker(hit_position: Vector2) -> void:
	var marker = Label.new()
	marker.text = "💥 CRIT!"
	add_child(marker)
	marker.global_position = hit_position + Vector2(-30, -20)
	marker.add_theme_font_size_override("font_size", 24)
	marker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	var tween = create_tween().set_parallel(true)
	tween.tween_property(marker, "global_position", marker.global_position + Vector2(0, -50), 0.5)
	tween.tween_property(marker, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(marker.queue_free)

func spawn_hit_particles(hit_position: Vector2, particle_color: Color) -> void:
	var particles = CPUParticles2D.new()
	add_child(particles)
	particles.global_position = hit_position
	particles.amount = 20
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.spread = 180.0
	particles.initial_velocity_min = 120.0
	particles.initial_velocity_max = 200.0
	particles.color = particle_color
	get_tree().create_timer(0.5).timeout.connect(particles.queue_free)
	
func trigger_game_over(eliminated_id: int) -> void:
	game_active = false
	var win_id = 2 if eliminated_id == 1 else 1
	var lbl = Label.new()
	lbl.text = "🏆 PLAYER " + str(win_id) + " WINS! 🏆\nPress 'R' to Restart"
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(lbl)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
			get_tree().reload_current_scene()

func _on_peer_disconnected(id: int) -> void:
	print("🚨 Peer client disconnected from lab row socket: ", id)
	game_active = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()
