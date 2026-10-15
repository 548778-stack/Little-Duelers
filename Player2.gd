#cd "S:\My Documents\little-duelers"
# git add .
# git commit -m "message"
#git push

# cd #cd other location
# git pull

extends CharacterBody2D

@export var speed: float = 500.0
var player_id: int = 2

# Health & Match settings variables
var max_health: float = 3.0
var current_health: float = 3.0
var lives: int = 3

var character_class: String = "Slingshotter"
var selected_ability: String = "None"

var normal_cooldown_time: float = 0.4    
var time_since_last_normal: float = 0.0  

# Inside Player2.gd -> Update your _ready() loop:

func _ready() -> void:
	# 🛡️ Wait 2 frames to ensure the server has fully assigned peer tokens across the LAN wire
	await get_tree().process_frame
	await get_tree().process_frame
	
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	# --- 🌐 NEW: FORCE SYNCHRONIZER AUTHORITY OVERRIDE ---
	# Find your MultiplayerSynchronizer child node and explicitly give it 
	# the same network peer authority ID assigned to this Player 2 object [0.1]!
	var sync_node = get_node_or_null("MultiplayerSynchronizer")
	if sync_node:
		sync_node.set_multiplayer_authority(get_multiplayer_authority())
		print("🔌 Player2 Synchronizer authority successfully locked to peer ID: ", get_multiplayer_authority())
	
	# Configure Player 2 settings from the synchronized arena lobby data
	character_class = arena.p2_selected_character
	selected_ability = arena.p2_selected_skill
	lives = arena.starting_lives_setting
	current_health = max_health
	
	# Color it Red for Player 2
	if has_node("ColorRect"):
		$ColorRect.color = Color(1.0, 0.3, 0.3)
		
	# Apply balances
	match character_class:
		"Recon": speed = 600.0
		"Slingshotter": speed = 475.0
		"Cowboy": speed = 400.0


func _physics_process(delta: float) -> void:
	time_since_last_normal += delta
	
	# 🛡️ THE LAN HARDWARE GUARD: Only allow inputs if this terminal is the Guest player!
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	# Read the Guest keyboard movements natively
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	
	# Clamp positions inside the designated RIGHT half quadrants boundary tracks
	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)

func _input(event: InputEvent) -> void:
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	if event.is_action_pressed("attack_normal") and time_since_last_normal >= normal_cooldown_time:
		var target_mouse_pos = get_global_mouse_position()
		var fire_direction = global_position.direction_to(target_mouse_pos)
		
		# Send a request to the server to spawn the projectile over the LAN wire
		rpc_id(1, "request_server_projectile_spawn", "normal", global_position, fire_direction)
		time_since_last_normal = 0.0

@rpc("any_peer", "call_local", "reliable")
func request_server_projectile_spawn(type: String, start_pos: Vector2, fire_dir: Vector2) -> void:
	# Passes execution to the Host engine to spawn the laser globally [0.1]
	if multiplayer.is_server():
		var arena = get_parent()
		var bullet = Area2D.new()
		bullet.set_script(preload("res://Projectile.gd"))
		bullet.attacker_id = 2
		bullet.damage_type = type
		arena.add_child(bullet)
		bullet.global_position = start_pos + (fire_dir * 45.0)
		if bullet.has_method("set_vector_trajectory"):
			bullet.set_vector_trajectory(fire_dir)


func take_damage(amount: float, _is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if lives <= 0: return
	if is_crit_hit: get_parent().spawn_crit_hit_marker(global_position)
	current_health -= amount
	get_parent().spawn_hit_particles(global_position, Color(1.0, 0.3, 0.3))
	if current_health <= 0.0:
		lives -= 1
		current_health = max_health
		if lives <= 0: get_parent().trigger_game_over(2)
