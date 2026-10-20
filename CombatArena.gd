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

# Update the top functions inside your CombatArena.gd script file:

func _ready() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	# Create map obstacles container node
	var obstacles_node = Node2D.new()
	obstacles_node.name = "Obstacles"
	add_child(obstacles_node)
	
	setup_hud(screen_width)
	game_active = true
	queue_redraw()
	
	# Extract global configuration configurations straight from background NetworkManager
	selected_map = NetworkManager.selected_map
	starting_lives_setting = NetworkManager.starting_lives
	
	# --- 🛡️ INSTRUCTION FIXED: PULL DATA FROM AUTOLOAD INSTEAD OF OVERWRITING IT ---
	# We safely extract the exact selections from the NetworkManager so your HUD can read them!
	p1_selected_character = NetworkManager.player_choices.get(1, {}).get("class", "Slingshotter")
	p1_selected_skill = NetworkManager.player_choices.get(1, {}).get("ability", "Piercing Shot")
	
	# Pull lookups for Player 2 / Bot using key 2 or "guest" keys
	var p2_key = 2 if NetworkManager.player_choices.has(2) else "guest"
	p2_selected_character = NetworkManager.player_choices.get(p2_key, {}).get("class", "Slingshotter")
	p2_selected_skill = NetworkManager.player_choices.get(p2_key, {}).get("ability", "Piercing Shot")
	
	print("📊 Arena HUD Sync: P1=", p1_selected_character, " [", p1_selected_skill, "] | P2=", p2_selected_character, " [", p2_selected_skill, "]")
	
	# Clear obstacles container node if choice string demands clear plain geometry
	if selected_map == "Open Empty Plain" or selected_map == "clear":
		if has_node("Obstacles"): get_node("Obstacles").queue_free()
		print("🧼 Map Setup: Choice string is 'clear'. Deleted obstacles container layer successfully!")
	else:
		if multiplayer.multiplayer_peer == null or multiplayer.is_server():
			var min_obs = 3 if selected_map == "Standard Field" else 6
			var max_obs = 5 if selected_map == "Obstacles Chaos" else 9
			generate_map_obstacles(screen_width, screen_height, min_obs, max_obs)
			
	# --- 🚀 EVENT-DRIVEN SIGNALS FRAMEWORK (DESTRUCTIVE OVERWRITES DELETED) ---
	if multiplayer.multiplayer_peer == null or NetworkManager.vs_ai:
		# Offline fallback spawning targets use unified Player.tscn
		spawn_player(1, Vector2(120, screen_height / 2))
		spawn_player(2, Vector2(screen_width - 120, screen_height / 2))
	else:
		if multiplayer.is_server():
			spawn_player(1, Vector2(120, screen_height / 2))
			multiplayer.peer_connected.connect(func(id):
				spawn_player(id, Vector2(screen_width - 120, screen_height / 2))
			)

func spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	var player_instance = PLAYER_SCENE.instantiate()
	player_instance.name = str(peer_id)
	
	# --- 🤖 INSTRUCTION FIXED: FIX THE BOT BEHAVIOR SCRIPT ASSIGNMENT ---
	# If we are in single-player AI mode and spawning Player 2, transform this node into a functioning bot!
	if NetworkManager.vs_ai and peer_id == 2:
		player_instance.set_script(preload("res://EnemyAI.gd"))
		print("🤖 AI Injector: Successfully attached EnemyAI.gd script onto Node ID: ", player_instance.name)
	
	# Retrieve the selected data settings from the global autoload
	var final_lookup_key = peer_id
	if not NetworkManager.player_choices.has(final_lookup_key):
		if peer_id != 1 and NetworkManager.player_choices.has(2):
			final_lookup_key = 2
		elif NetworkManager.player_choices.has("guest"):
			final_lookup_key = "guest"
			
	var choices = NetworkManager.player_choices.get(final_lookup_key, {"class": "Slingshotter", "ability": "Piercing Shot"})
	
	player_instance.character_class = choices.get("class", "Slingshotter")
	player_instance.selected_ability = choices.get("ability", "Piercing Shot")
	player_instance.lives = NetworkManager.starting_lives
	
	if peer_id == 1: 
		player1 = player_instance
	else: 
		player2 = player_instance
		
	add_child(player_instance, true) 
	player_instance.global_position = spawn_position
	print("🚀 Spawner Hook: Instantiated Node ID ", player_instance.name, " as class: ", player_instance.character_class)

func _process(delta: float) -> void:
	if not game_active: return
	active_ability_cooldown_time = NetworkManager.starting_lives # Lock matching scales
	
	if player1 == null and has_node("1"): player1 = get_node("1")
	if player2 == null:
		if has_node("2"): player2 = get_node("2")
		else:
			for peer in multiplayer.get_peers():
				if has_node(str(peer)): player2 = get_node(str(peer))

	if is_instance_valid(player1):
		var ammo_info = player1.get_ammo_string() if player1.has_method("get_ammo_string") else ""
		var skill_info = player1.get_ability_status_string() if player1.has_method("get_ability_status_string") else ""
		p1_hud_label.text = "  💙 P1 Lives: " + str(player1.lives) + " | HP: " + str(snappedf(player1.current_health, 0.1)) + "/" + str(player1.max_health) + ammo_info + skill_info
		var p1_timer = player1.get("local_ability_timer")
		if p1_timer != null: p1_ability_bar.value = (p1_timer / 5.0) * 100.0
		if player1.has_method("get_individual_bar_progress"):
			for i in range(3): p1_bars[i].value = player1.get_individual_bar_progress(i) * 100.0

	if is_instance_valid(player2):
		var ammo_info = player2.get_ammo_string() if player2.has_method("get_ammo_string") else ""
		var skill_info = player2.get_ability_status_string() if player2.has_method("get_ability_status_string") else ""
		p2_hud_label.text = skill_info + ammo_info + " | P2 Lives: " + str(player2.lives) + " | HP: " + str(snappedf(player2.current_health, 0.1)) + "/" + str(player2.max_health) + " ❤️  "
		var p2_timer = player2.get("local_ability_timer")
		if p2_timer != null: p2_ability_bar.value = (p2_timer / 5.0) * 100.0
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
	

# --- 🎯 INSTRUCTION FIXED: THE "R" RESET BUTTON INTERCEPTOR ---
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			print("🔄 Reset Triggered: Cleaning match data entries and returning to the Lobby...")
			
			# Completely stripped out reload_current_scene()!
			# Instead, we cleanly route players backward through your established scene workflow
			if multiplayer.multiplayer_peer != null:
				if multiplayer.is_server():
					# Host forces both screens back to the lobby staging room simultaneously via RPC!
					NetworkManager.rpc("change_scene", "res://Lobby.tscn")
				else:
					print("⏳ Guest pressed R. Waiting for Host to trigger lobby reset...")
			else:
				# Offline single-player mode transitions locally
				get_tree().change_scene_to_file("res://Lobby.tscn")

func trigger_game_over(eliminated_player_id: int) -> void:
	game_active = false
	var winner_id = 2 if eliminated_player_id == 1 else 1
	
	# Stop physics processing on current players
	if is_instance_valid(player1): player1.set_physics_process(false)
	if is_instance_valid(player2): player2.set_physics_process(false)
	
	# --- 1. CLEAN UP THE OVERLAPPING TEXT ---
	# Hide the active gameplay HUD boxes completely right as the game ends!
	if is_instance_valid(p1_hud_label): p1_hud_label.visible = false
	if is_instance_valid(p2_hud_label): p2_hud_label.visible = false
	if is_instance_valid(p1_ability_bar): p1_ability_bar.visible = false
	if is_instance_valid(p2_ability_bar): p2_ability_bar.visible = false
	for bar in p1_bars: if is_instance_valid(bar): bar.visible = false
	for bar in p2_bars: if is_instance_valid(bar): bar.visible = false

	# --- 2. ANCHOR AND CENTER THE POP-UP PANEL ---
	# Create a styled Panel container to house the victory layout
	var win_panel = Panel.new()
	win_panel.name = "VictoryPopUpPanel"
	add_child(win_panel)
	
	# Force the pop-up to use Godot's UI anchors to center itself perfectly on any resolution
	win_panel.custom_minimum_size = Vector2(500, 250)
	win_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	win_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	win_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# Set a centered VBox container to structure the text and buttons cleanly
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	win_panel.add_child(vbox)
	
	# Build the large, clean victory title label text
	var win_label = Label.new()
	win_label.text = "🏆 PLAYER " + str(winner_id) + " WINS! 🏆"
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 32)
	win_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2)) # Glowing Gold
	vbox.add_child(win_label)
	
	# Build the secondary helper instruction label text
	var help_label = Label.new()
	help_label.text = "Press 'R' to return to the character select Lobby"
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(help_label)

	# --- 3. CREATE THE 'PLAY AGAIN' BUTTON ---
	var play_again_btn = Button.new()
	play_again_btn.name = "PlayAgainButton"
	play_again_btn.text = "PLAY AGAIN"
	play_again_btn.custom_minimum_size = Vector2(200, 45)
	play_again_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	vbox.add_child(play_again_btn)
	
	# Network button guard constraints: Only the Host has permission to click the restart trigger
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		play_again_btn.text = "WAITING FOR HOST..."
		play_again_btn.disabled = true
	else:
		play_again_btn.pressed.connect(_on_play_again_pressed)

func _on_play_again_pressed() -> void:
	print("🔄 Play Again Button pressed! Distributing match reload loops...")
	
	if multiplayer.multiplayer_peer == null or NetworkManager.vs_ai:
		# --- OFFLINE RESET LOGIC (VS AI) ---
		# Clear old player instances out of the arena map memory completely
		if is_instance_valid(player1): player1.queue_free()
		if is_instance_valid(player2): player2.queue_free()
		
		# Wipe remaining bullet projectile nodes currently traveling on screen
		for child in get_children():
			if child.name.begins_with("@Area2D@") or child.has_method("set_vector_trajectory"):
				child.queue_free()
		
		# Restore HUD visibility parameters back to true for the next round
		if is_instance_valid(p1_hud_label): p1_hud_label.visible = true
		if is_instance_valid(p2_hud_label): p2_hud_label.visible = true
		if is_instance_valid(p1_ability_bar): p1_ability_bar.visible = true
		if is_instance_valid(p2_ability_bar): p2_ability_bar.visible = true
		for bar in p1_bars: if is_instance_valid(bar): bar.visible = true
		for bar in p2_bars: if is_instance_valid(bar): bar.visible = true
		
		# Delete the popup container panel node
		if has_node("VictoryPopUpPanel"): get_node("VictoryPopUpPanel").queue_free()
		
		# Re-run your clean spawn player methods directly inside the arena locally!
		var screen_width = get_viewport_rect().size.x
		var screen_height = get_viewport_rect().size.y
		game_active = true
		spawn_player(1, Vector2(120, screen_height / 2))
		spawn_player(2, Vector2(screen_width - 120, screen_height / 2))
	else:
		# --- ONLINE NETWORK RESET LOGIC (P2P) ---
		# Host server triggers a synchronized scene reload so both machines jump at the exact same moment
		rpc("sync_online_match_reload")

# --- THE HIGH-LEVEL NETWORK MATCH RELOADER RPC ---
@rpc("any_peer", "call_local", "reliable")
func sync_online_match_reload() -> void:
	print("🔌 Network Sync: Reloading fresh instance of CombatArena.tscn on this machine...")
	get_tree().change_scene_to_file("res://CombatArena.tscn")


func _on_peer_disconnected(id: int) -> void:
	print("🚨 Peer client disconnected from lab row socket: ", id)
	game_active = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()
