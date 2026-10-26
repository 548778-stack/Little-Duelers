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
var active_ability_cooldown_time: float = 5.0
var p1_bars: Array[TextureProgressBar] = []
var p2_bars: Array[TextureProgressBar] = []

const PLAYER_SCENE = preload("res://Player.tscn")

const PROJECTILE_SCENE = preload("res://Projectile.tscn")
const ENEMY_BOT_SCENE = preload("res://EnemyBot.tscn")

@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

func _ready() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y

	# The MultiplayerSpawner builds every player and projectile on ALL machines
	# using _build_spawned_node(), so each copy gets the right class/direction.
	spawner.spawn_function = _build_spawned_node

	var bg = ColorRect.new()
	bg.name = "Background"
	bg.size = Vector2(1152, 648)
	bg.color = Color(0.08, 0.09, 0.12)
	bg.show_behind_parent = true  # so the center lines from _draw() show on top
	add_child(bg)
	move_child(bg, 0)
	var scene_bg = get_node_or_null("Background")
	if scene_bg and scene_bg != bg: scene_bg.show_behind_parent = true

	setup_hud(screen_width)
	game_active = true
	queue_redraw()

	selected_map = NetworkManager.selected_map
	starting_lives_setting = NetworkManager.starting_lives
	vs_ai_mode = NetworkManager.vs_ai
	p1_selected_character = NetworkManager.lobby_data[1]["character"]
	p1_selected_skill = NetworkManager.lobby_data[1]["ability"]
	p2_selected_character = NetworkManager.lobby_data[2]["character"]
	p2_selected_skill = NetworkManager.lobby_data[2]["ability"]

	if not NetworkManager.is_online():
		_build_obstacles(_generate_obstacle_list(screen_width, screen_height))
		# Offline: just build both players locally.
		add_child(_build_spawned_node(_player_spawn_data(1, 1, Vector2(120, screen_height / 2))), true)
		add_child(_build_spawned_node(_player_spawn_data(2, 2, Vector2(screen_width - 120, screen_height / 2))), true)
	else:
		if multiplayer.is_server():
			NetworkManager.all_peers_loaded.connect(_spawn_online_players, CONNECT_ONE_SHOT)
		# Tell the host "my arena is loaded". The host spawns once both machines report in.
		NetworkManager.report_scene_loaded.rpc_id(1)

func _spawn_online_players() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	# The host rolls the random obstacles once and sends the same list to both machines.
	_build_obstacles.rpc(_generate_obstacle_list(screen_width, screen_height))
	spawner.spawn(_player_spawn_data(1, 1, Vector2(120, screen_height / 2)))
	spawner.spawn(_player_spawn_data(2, NetworkManager.guest_peer_id, Vector2(screen_width - 120, screen_height / 2)))

func _player_spawn_data(side: int, peer_id: int, pos: Vector2) -> Dictionary:
	var choices = NetworkManager.lobby_data[side]
	return {
		"kind": "player",
		"side": side,
		"peer_id": peer_id,
		"character": choices["character"],
		"ability": choices["ability"],
		"lives": NetworkManager.starting_lives,
		"pos": pos,
	}

# Called by the host (only the host may call spawn_projectile) to create a networked bullet.
func spawn_projectile(type: String, pos: Vector2, dir: Vector2, attacker_id: int, damage: float = 1.0, is_crit: bool = false) -> void:
	if not multiplayer.is_server() or not game_active: return
	var data = {"kind": "projectile", "type": type, "pos": pos, "dir": dir, "attacker": attacker_id, "damage": damage, "crit": is_crit}
	if NetworkManager.is_online():
		spawner.spawn(data)
	else:
		add_child(_build_spawned_node(data), true)

# Runs on EVERY peer for each spawn. Must return a node that is NOT yet in the tree.
func _build_spawned_node(data: Dictionary) -> Node:
	if data["kind"] == "projectile":
		var bullet = PROJECTILE_SCENE.instantiate()
		bullet.attacker_id = data["attacker"]
		bullet.damage_type = data["type"]
		bullet.damage_amount = data.get("damage", 1.0)
		bullet.is_critical = data.get("crit", false)
		bullet.position = data["pos"]
		bullet.set_vector_trajectory(data["dir"])
		return bullet

	var side: int = data["side"]
	var use_bot = vs_ai_mode and side == 2 and not NetworkManager.is_online()
	var player_instance = ENEMY_BOT_SCENE.instantiate() if use_bot else PLAYER_SCENE.instantiate()
	# Node name = owning peer ID. BasePlayer._enter_tree() uses it to set authority,
	# and it must be identical on both machines for RPCs to reach the right node.
	player_instance.name = str(data["peer_id"])
	player_instance.character_class = data["character"]
	player_instance.selected_ability = data["ability"]
	player_instance.lives = data["lives"]
	player_instance.position = data["pos"]
	if side == 1: player1 = player_instance
	else: player2 = player_instance
	return player_instance

func _process(_delta: float) -> void:
	if not game_active: return

	if not is_instance_valid(player1) and has_node("1"): player1 = get_node("1")
	if not is_instance_valid(player2):
		var p2_name = str(NetworkManager.guest_peer_id) if NetworkManager.is_online() else "2"
		if has_node(p2_name): player2 = get_node(p2_name)

	if is_instance_valid(player1):
		var ammo_info = player1.get_ammo_string() if player1.has_method("get_ammo_string") else ""
		var skill_info = player1.get_ability_status_string() if player1.has_method("get_ability_status_string") else ""
		p1_hud_label.text = "  💙 P1 Lives: " + str(player1.lives) + " | HP: " + str(snappedf(player1.current_health, 0.1)) + "/" + str(player1.max_health) + ammo_info + skill_info
		if player1.has_method("get_ability_cooldown_percentage"): p1_ability_bar.value = player1.get_ability_cooldown_percentage() * 100.0
		if player1.has_method("get_individual_bar_progress"):
			for i in range(3): p1_bars[i].value = player1.get_individual_bar_progress(i) * 100.0

	if is_instance_valid(player2):
		var ammo_info = player2.get_ammo_string() if player2.has_method("get_ammo_string") else ""
		var skill_info = player2.get_ability_status_string() if player2.has_method("get_ability_status_string") else ""
		p2_hud_label.text = skill_info + ammo_info + " | P2 Lives: " + str(player2.lives) + " | HP: " + str(snappedf(player2.current_health, 0.1)) + "/" + str(player2.max_health) + " ❤️  "
		if player2.has_method("get_ability_cooldown_percentage"): p2_ability_bar.value = player2.get_ability_cooldown_percentage() * 100.0
		if player2.has_method("get_individual_bar_progress"):
			for i in range(3): p2_bars[i].value = player2.get_individual_bar_progress(i) * 100.0

func _draw() -> void:
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	draw_line(Vector2(screen_width / 2.0, 0), Vector2(screen_width / 2.0, screen_height), Color(0.25, 0.28, 0.35, 0.6), 4.0)
	draw_line(Vector2(0, screen_height / 2.0), Vector2(screen_width, screen_height / 2.0), Color(0.25, 0.28, 0.35, 0.6), 4.0)

# --- OBSTACLES -----------------------------------------------------------------

# Host only: roll random obstacle positions/sizes. Returns an Array of [position, size].
func _generate_obstacle_list(screen_width: float, screen_height: float) -> Array:
	var list: Array = []
	if selected_map == "Open Empty Plain": return list
	var min_c = 3
	var max_c = 5
	if selected_map == "Obstacle Heavy Chaos":
		min_c = 6
		max_c = 9
	var center_x = screen_width / 2.0
	var count = randi_range(min_c, max_c)
	var sector_height = screen_height / count
	for i in range(count):
		if randf() > 0.7: continue
		var rand_y = (i * sector_height) + randf_range(40.0, max(41.0, sector_height - 40.0))
		var pos = Vector2(center_x + randf_range(-50.0, 50.0), rand_y)
		var obs_size = Vector2(randf_range(30.0, 60.0), randf_range(50.0, 110.0))
		list.append([pos, obs_size])
	return list

# Builds the same obstacles on every machine (host sends the list).
@rpc("authority", "call_local", "reliable")
func _build_obstacles(list: Array) -> void:
	for i in range(list.size()):
		var obs_position: Vector2 = list[i][0]
		var obs_size: Vector2 = list[i][1]
		var obstacle = StaticBody2D.new()
		obstacle.name = "Obstacle_" + str(i)
		obstacle.position = obs_position
		var visual = ColorRect.new()
		visual.size = obs_size
		visual.position = -obs_size / 2
		visual.color = Color(0.35, 0.38, 0.42)
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		obstacle.add_child(visual)
		var collider = CollisionShape2D.new()
		var box_shape = RectangleShape2D.new()
		box_shape.size = obs_size
		collider.shape = box_shape
		obstacle.add_child(collider)
		add_child(obstacle, true)

# --- HUD -----------------------------------------------------------------------

func setup_hud(screen_width: float) -> void:
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	main_hbox.custom_minimum_size = Vector2(screen_width, 100)
	main_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(main_hbox)

	# Progress bars need a texture or they're invisible.
	var img = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var white_texture = ImageTexture.create_from_image(img)

	var p1_ui = _build_hud_column(main_hbox, white_texture, false, Color(0.4, 0.75, 1.0))
	var p2_ui = _build_hud_column(main_hbox, white_texture, true, Color(1.0, 0.4, 0.4))
	p1_hud_label = p1_ui[0]; p1_bars = p1_ui[1]; p1_ability_bar = p1_ui[2]
	p2_hud_label = p2_ui[0]; p2_bars = p2_ui[1]; p2_ability_bar = p2_ui[2]

func _build_hud_column(parent: Control, tex: Texture2D, right_side: bool, color: Color) -> Array:
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vbox)

	var label = Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	if right_side: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(label)

	# 3 yellow special-charge bars
	var bars_row = HBoxContainer.new()
	if right_side: bars_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(bars_row)
	var bars: Array[TextureProgressBar] = []
	for i in range(3):
		var bar = TextureProgressBar.new()
		bar.custom_minimum_size = Vector2(50, 6)
		bar.nine_patch_stretch = true
		bar.texture_progress = tex
		bar.tint_progress = Color(1.0, 0.85, 0.2)
		bars_row.add_child(bar)
		bars.append(bar)

	# Green ability cooldown bar
	var ability_bar = TextureProgressBar.new()
	ability_bar.custom_minimum_size = Vector2(162, 6)
	ability_bar.nine_patch_stretch = true
	# Without SHRINK, the bar stretches across half the screen and overlaps the obstacles.
	ability_bar.size_flags_horizontal = Control.SIZE_SHRINK_END if right_side else Control.SIZE_SHRINK_BEGIN
	ability_bar.texture_progress = tex
	ability_bar.tint_progress = Color(0.2, 1.0, 0.5)
	vbox.add_child(ability_bar)
	return [label, bars, ability_bar]

# --- GAME OVER -----------------------------------------------------------------

func trigger_game_over(eliminated_player_id: int) -> void:
	if not game_active: return
	game_active = false
	var winner_id = 2 if eliminated_player_id == 1 else 1

	if is_instance_valid(player1): player1.set_physics_process(false)
	if is_instance_valid(player2): player2.set_physics_process(false)

	for node in [p1_hud_label, p2_hud_label, p1_ability_bar, p2_ability_bar]:
		if is_instance_valid(node): node.visible = false
	for bar in p1_bars + p2_bars:
		if is_instance_valid(bar): bar.visible = false

	var win_canvas_layer = CanvasLayer.new()
	win_canvas_layer.name = "VictoryCanvasLayer"
	add_child(win_canvas_layer)

	var bg_overlay = ColorRect.new()
	bg_overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	win_canvas_layer.add_child(bg_overlay)
	bg_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center = CenterContainer.new()
	bg_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var win_label = Label.new()
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 48)
	win_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	win_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	win_label.add_theme_constant_override("outline_size", 12)
	win_label.text = "🏆 PLAYER " + str(winner_id) + " WINS! 🏆"
	vbox.add_child(win_label)

	var btn = Button.new()
	btn.text = "PLAY AGAIN"
	btn.custom_minimum_size = Vector2(220, 50)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_play_again_pressed)
	if NetworkManager.is_online() and not multiplayer.is_server():
		btn.text = "WAITING FOR HOST..."
		btn.disabled = true
	vbox.add_child(btn)

	var help_label = Label.new()
	help_label.text = "Host: press 'R' to return to Lobby"
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_size_override("font_size", 14)
	help_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(help_label)

func _on_play_again_pressed() -> void:
	if not NetworkManager.is_online():
		get_tree().change_scene_to_file("res://CombatArena.tscn")
	elif multiplayer.is_server():
		NetworkManager.change_scene.rpc("res://CombatArena.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if not NetworkManager.is_online():
			get_tree().change_scene_to_file("res://Lobby.tscn")
		elif multiplayer.is_server():
			NetworkManager.change_scene.rpc("res://Lobby.tscn")

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
