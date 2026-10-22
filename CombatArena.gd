extends Node2D

var player1: CharacterBody2D
var player2: CharacterBody2D

var vs_ai_mode: bool = false
var selected_map: String = "Standard Field"
var starting_lives_setting: int = 3
var game_active: bool = false

var p1_selected_character: String = "Slingshotter"
var p1_selected_skill: String = "Piercing Shot"
var p2_selected_character: String = "Slingshotter"
var p2_selected_skill: String = "Piercing Shot"

var p1_hud_label: Label
var p2_hud_label: Label
var p1_ability_bar: TextureProgressBar
var p2_ability_bar: TextureProgressBar
var p1_bars: Array[TextureProgressBar] = []
var p2_bars: Array[TextureProgressBar] = []

const PLAYER_SCENE = preload("res://Player.tscn")

func _ready() -> void:
	# INSTRUCTION FIXED: Completely cleaned out all Git merge conflict markers (<<<<<<<, =======, >>>>>>>)! [1.4]
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.size = Vector2(1152, 648)
	bg.color = Color(0.08, 0.09, 0.12)
	add_child(bg)
	move_child(bg, 0)
	
	setup_hud(screen_width)
	game_active = true
	queue_redraw()
	
	selected_map = NetworkManager.selected_map
	starting_lives_setting = NetworkManager.starting_lives
	
	if selected_map == "Open Empty Plain":
		if has_node("Obstacles"): get_node("Obstacles").queue_free()
	else:
		if multiplayer.multiplayer_peer == null or multiplayer.is_server():
			generate_map_obstacles(screen_width, screen_height, 3, 5)
			
	if multiplayer.multiplayer_peer == null or NetworkManager.vs_ai:
		spawn_player(1, Vector2(120, screen_height / 2))
		spawn_player(2, Vector2(screen_width - 120, screen_height / 2))
	else:
		if multiplayer.is_server():
			spawn_player(1, Vector2(120, screen_height / 2))
			multiplayer.peer_connected.connect(func(id): spawn_player(id, Vector2(screen_width - 120, screen_height / 2)))

func spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	var player_instance = PLAYER_SCENE.instantiate()
	player_instance.name = str(peer_id)
	
	if NetworkManager.vs_ai and peer_id == 2:
		player_instance.set_script(preload("res://EnemyAI.gd"))
	
	var lookup_key = peer_id if NetworkManager.lobby_data.has(peer_id) else "guest"
	if peer_id != 1 and NetworkManager.lobby_data.has(2): lookup_key = 2
	
	var choices = NetworkManager.lobby_data.get(lookup_key, {"character": "Slingshotter", "ability": "Piercing Shot"})
	player_instance.character_class = choices["character"]
	player_instance.selected_ability = choices["ability"]
	player_instance.lives = NetworkManager.starting_lives
	
	if peer_id == 1: player1 = player_instance
	else: player2 = player_instance
		
	add_child(player_instance, true)
	player_instance.global_position = spawn_position

func _process(delta: float) -> void:
	if not game_active: return
	
	if player1 == null and has_node("1"): player1 = get_node("1")
	if player2 == null:
		# INSTRUCTION FIXED: Replaced static text lookups to search dynamic numeric peer strings! [0.1]
		if has_node("2"): player2 = get_node("2")
		elif multiplayer.multiplayer_peer != null:
			for peer in multiplayer.get_peers():
				if has_node(str(peer)): player2 = get_node(str(peer))

	if is_instance_valid(player1):
		var ammo_info = player1.get_ammo_string() if player1.has_method("get_ammo_string") else ""
		var skill_info = player1.get_ability_status_string() if player1.has_method("get_ability_status_string") else ""
		p1_hud_label.text = "  💙 P1 Lives: " + str(player1.lives) + " | HP: " + str(snappedf(player1.current_health, 0.1)) + "/" + str(player1.max_health) + ammo_info + skill_info
		if player1.get("local_ability_timer") != null: p1_ability_bar.value = (player1.local_ability_timer / 5.0) * 100.0

	if is_instance_valid(player2):
		var ammo_info = player2.get_ammo_string() if player2.has_method("get_ammo_string") else ""
		var skill_info = player2.get_ability_status_string() if player2.has_method("get_ability_status_string") else ""
		p2_hud_label.text = skill_info + ammo_info + " | P2 Lives: " + str(player2.lives) + " | HP: " + str(snappedf(player2.current_health, 0.1)) + "/" + str(player2.max_health) + " ❤️ "
		if player2.get("local_ability_timer") != null: p2_ability_bar.value = (player2.local_ability_timer / 5.0) * 100.0

func _draw() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	draw_line(Vector2(screen_width / 2.0, 0), Vector2(screen_width / 2.0, screen_height), Color(0.25, 0.28, 0.35, 0.6), 4.0)

func setup_hud(screen_width: float) -> void:
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	main_hbox.custom_minimum_size = Vector2(screen_width, 100)
	canvas_layer.add_child(main_hbox)
	
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(left_vbox)
	p1_hud_label = Label.new()
	p1_hud_label.add_theme_font_size_override("font_size", 20)
	p1_hud_label.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	left_vbox.add_child(p1_hud_label)
	p1_ability_bar = TextureProgressBar.new()
	p1_ability_bar.custom_minimum_size = Vector2(162, 6)
	left_vbox.add_child(p1_ability_bar)
	
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(right_vbox)
	p2_hud_label = Label.new()
	p2_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_hud_label.add_theme_font_size_override("font_size", 20)
	p2_hud_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	right_vbox.add_child(p2_hud_label)
	p2_ability_bar = TextureProgressBar.new()
	p2_ability_bar.custom_minimum_size = Vector2(162, 6)
	right_vbox.add_child(p2_ability_bar)

func generate_map_obstacles(sw, sh, mn, mx) -> void:
	pass

func trigger_game_over(eliminated_player_id: int) -> void:
	game_active = false
	if is_instance_valid(p1_hud_label): p1_hud_label.visible = false
	if is_instance_valid(p2_hud_label): p2_hud_label.visible = false
	var win_canvas_layer = CanvasLayer.new()
	add_child(win_canvas_layer)
	
	var bg_overlay = ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.7)
	win_canvas_layer.add_child(bg_overlay)
	bg_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var win_label = Label.new()
	bg_overlay.add_child(win_label)
	win_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 48)
	win_label.text = "🏆 ROUND OVER 🏆\n\nPress 'R' to Play Again"
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_END
	bg_overlay.add_child(vbox)
	var btn = Button.new()
	btn.text = "PLAY AGAIN"
	btn.custom_minimum_size = Vector2(220, 50)
	btn.pressed.connect(func(): _on_play_again_pressed())
	vbox.add_child(btn)

func _on_play_again_pressed() -> void:
	if multiplayer.multiplayer_peer == null or NetworkManager.vs_ai:
		get_tree().change_scene_to_file("res://CombatArena.tscn")
	else:
		if multiplayer.is_server(): change_match_scene.rpc("res://CombatArena.tscn")

@rpc("any_peer", "call_local", "reliable")
func change_match_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if multiplayer.multiplayer_peer != null and multiplayer.is_server():
			change_match_scene.rpc("res://Lobby.tscn")
		elif multiplayer.multiplayer_peer == null:
			get_tree().change_scene_to_file("res://Lobby.tscn")

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
	



# --- THE HIGH-LEVEL NETWORK MATCH RELOADER RPC ---
@rpc("any_peer", "call_local", "reliable")
func sync_online_match_reload(eliminated_id) -> void:
	print("🔌 Network Sync: Reloading fresh instance of CombatArena.tscn on this machine...")
	get_tree().change_scene_to_file("res://CombatArena.tscn")

	var win_id = 2 if eliminated_id == 1 else 1
	var lbl = Label.new()
	lbl.text = "🏆 PLAYER " + str(win_id) + " WINS! 🏆\nPress 'R' to Restart"
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(lbl)


func _on_peer_disconnected(id: int) -> void:
	print("🚨 Peer client disconnected from lab row socket: ", id)
	game_active = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()
