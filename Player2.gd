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
	character_class = arena.p2_selected_character if name == "Player2" else arena.p1_selected_character
	selected_ability = arena.p2_selected_skill if name == "Player2" else arena.p1_selected_skill
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
	
	# 🛡️ THE LAN HARDWARE GUARD: Only read keys if we are the Guest!
	if multiplayer.multiplayer_peer != null:
		if is_multiplayer_authority():
			var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			velocity = direction * speed
			move_and_slide()
			
			# Clamp positions inside the designated RIGHT half quadrants
			var view_size = get_viewport_rect().size
			var mid_x = view_size.x / 2.0
			position.y = clampf(position.y, 40.0, view_size.y - 40.0)
			position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)
			
			# 🚀 FORCE UPLOAD: Upload our exact position directly to the Host PC!
			rpc_id(1, "upload_position_to_server", global_position)
	else:
		# Offline path fallback
		var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = direction * speed
		move_and_slide()

@rpc("any_peer", "call_remote", "unreliable")
func upload_position_to_server(guest_pos: Vector2) -> void:
	# The Host PC receives this and forces Player 2 to move to match your screen!
	global_position = guest_pos

func _input(event: InputEvent) -> void:
	# Network Guard: Only track inputs if this terminal physically controls Player 2
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	# Mouse Left Click: Normal Attack
	if event.is_action_pressed("attack_normal"):
		if time_since_last_normal >= normal_cooldown_time:
			var target_mouse_pos = get_global_mouse_position()
			var fire_direction = global_position.direction_to(target_mouse_pos)
			rpc_id(1, "request_server_projectile_spawn", "normal", global_position, fire_direction)
			time_since_last_normal = 0.0
			
	# Mouse Right Click: Special Attack (FIXED FOR LAN)
	elif event.is_action_pressed("attack_special"):
		var target_mouse_pos = get_global_mouse_position()
		var fire_direction = global_position.direction_to(target_mouse_pos)
		# Tell the Host Server to register and spawn Player 2's Special Bullet
		rpc_id(1, "request_server_projectile_spawn", "special", global_position, fire_direction)
		print("🔴 P2 requested Special Attack spawn on Host.")
			
	# Mouse Wheel Click / Scroll: Active Class Ability (FIXED FOR LAN)
	elif event.is_action_pressed("attack_ability"):
		var target_mouse_pos = get_global_mouse_position()
		var fire_direction = global_position.direction_to(target_mouse_pos)
		# Send a map request based on whichever ability string choice you picked in the lobby!
		var ability_bullet_type = "bouncing_normal" # Default fallback
		if selected_ability == "Piercing Shot": ability_bullet_type = "piercing_special"
		elif selected_ability == "Marksman": ability_bullet_type = "marksman_normal"
		elif selected_ability == "Recons Eye": ability_bullet_type = "tracking_normal"
		
		rpc_id(1, "request_server_projectile_spawn", ability_bullet_type, global_position, fire_direction)
		print("🔴 P2 requested Class Ability spawn on Host: ", selected_ability)


@rpc("any_peer", "call_local", "reliable")
func request_server_projectile_spawn(type: String, start_pos: Vector2, fire_dir: Vector2) -> void:
	# Only execute this logic on the Master Host machine [0.1]
	if multiplayer.is_server():
		var arena = get_parent()
		var bullet = Area2D.new()
		bullet.set_script(preload("res://Projectile.gd"))
		bullet.attacker_id = 2 # Strictly owned by Player 2
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
