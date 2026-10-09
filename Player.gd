#cd "S:\My Documents\little-duelers"
# git add .
# git commit -m "message"
#git push

# cd #cd other location
# git pull

extends CharacterBody2D

@export var speed: float = 500.0
var player_id: int = 1
var is_ai: bool = false 

# Health & Match settings
var max_health: int = 3
var current_health: int = 3
var lives: int = 3

# Class Selection details from lobby
var character_class: String = "Slingshotter"
var selected_ability: String = "None"

# Cooldown system parameters
var normal_cooldown_time: float = 0.4    
var special_cooldown_time: float = 1.8   
var time_since_last_normal: float = 0.0  

# 3-Charge Special System variables
var special_charges: int = 3
var special_charge_timer: float = 0.0    
var max_special_charges: int = 3

# Active Class Ability variables
var active_ability_cooldown_time: float = 5.0 
var time_since_last_ability: float = 0.0
var is_ability_ready: bool = true

# Cowboy class ammo counter variables
var max_ammo: int = 6
var current_ammo: int = 6
var is_reloading: bool = false
var reload_timer: float = 0.0
var reload_duration: float = 1.2

# Ability state flags
var is_recons_eye_active: bool = false
var recons_eye_timer: float = 0.0
var jerry_miculek_charges: int = 2

# AI tracking references
var ai_reaction_timer: float = 0.0
var ai_target_vector: Vector2 = Vector2.ZERO

func setup_player(id: int, brain_enabled: bool, chosen_class: String, chosen_ability: String) -> void:
	player_id = id
	is_ai = brain_enabled
	character_class = chosen_class
	selected_ability = chosen_ability

	# Apply Class Modifier Balances
	match character_class:
		"Recon":
			speed = 600.0 
			active_ability_cooldown_time = 8.0
		"Slingshotter":
			speed = 475.0 
			active_ability_cooldown_time = 4.0
		"Cowboy":
			speed = 400.0 
			normal_cooldown_time = 0.15 
			active_ability_cooldown_time = 6.0
			current_ammo = max_ammo

	time_since_last_normal = normal_cooldown_time
	time_since_last_ability = active_ability_cooldown_time
	ai_target_vector = position

func _ready() -> void:
	# Wait one frame for the network handshake system to finish setting tokens
	await get_tree().process_frame
	
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	if multiplayer.multiplayer_peer != null:
		await get_tree().process_frame
	
	# (Your existing arena extraction and setup logic continues here identically...)
	if not is_instance_valid(arena): return

	# Determine character specifications from our spawned name node identity
	if name == "Player1":
		setup_player(1, false, arena.p1_selected_character, arena.p1_selected_skill)
		lives = arena.starting_lives_setting
		current_health = max_health
		# Set ColorRect child tint for Player 1
		$ColorRect.color = Color(0.2, 0.6, 1.0) # Radiant blue
	elif name == "Player2":
		setup_player(2, arena.vs_ai_mode, arena.p2_selected_character, arena.p2_selected_skill)
		lives = arena.starting_lives_setting
		current_health = max_health
		$ColorRect.color = Color(1.0, 0.3, 0.3) # Crimson red

	print("✅ Hybrid Player Initialized over LAN Spawner: ", name)

func _physics_process(delta: float) -> void:
	# P2P NETWORK SHIELD: Drop computing inputs if this machine does not own this specific character block!
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	time_since_last_normal += delta
	time_since_last_ability += delta
			
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			current_ammo = max_ammo
			is_reloading = false

	if special_charges < max_special_charges:
		special_charge_timer += delta
		if special_charge_timer >= special_cooldown_time:
			special_charges += 1
			special_charge_timer = 0.0
	else:
		special_charge_timer = 0.0

	# --- UNLOCKED 2D MOVEMENT VECTOR ENGINE ---
	var direction = Vector2.ZERO
	if is_ai:
		process_ai_behavior(delta)
		if position.distance_to(ai_target_vector) > 15.0:
			direction = position.direction_to(ai_target_vector)
	else:
		# Both computers use the exact same WASD tokens safely now!
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			
	# Inside Player.gd -> _physics_process(delta) function:
	velocity = direction * speed
	move_and_slide()
	
	# --- NEW: QUADRANT AND TERRITORY LOCKS ---
	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	
	# Enforce vertical bounds universally
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	
	# Restrict horizontal limits depending on Player ID
	if player_id == 1:
		# Player 1 is locked strictly inside the LEFT half (Top-Left & Bottom-Left quadrants)
		position.x = clampf(position.x, 40.0, mid_x - 30.0)
	else:
		# Player 2 is locked strictly inside the RIGHT half (Top-Right & Bottom-Right quadrants)
		position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)

func _input(event: InputEvent) -> void:
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
	if is_ai: return 
	
	# Mouse Left Click: Normal Attack
	if event.is_action_pressed("attack_normal"):
		if is_reloading: return
		if character_class == "Cowboy" and current_ammo <= 0:
			start_reload()
			return
			
		if time_since_last_normal >= normal_cooldown_time:
			fire_projectile("normal")
			time_since_last_normal = 0.0
			if character_class == "Cowboy":
				current_ammo -= 1
				if current_ammo <= 0: start_reload()
				
	# Mouse Right Click: Special Attack
	elif event.is_action_pressed("attack_special"):
		if special_charges > 0:
			fire_projectile("special")
			special_charges -= 1
			
	# Mouse Wheel Click: Active Class Ability
	elif event.is_action_pressed("attack_ability"):
		try_use_ability()

func start_reload() -> void:
	if is_reloading: return
	is_reloading = true
	reload_timer = reload_duration

func try_use_ability() -> void:
	if selected_ability == "Jerry Miculek" and jerry_miculek_charges > 0:
		execute_ability()
		return
	if time_since_last_ability >= active_ability_cooldown_time:
		execute_ability()
		time_since_last_ability = 0.0

func execute_ability() -> void:
	match selected_ability:
		"Recons Eye":
			print("Player ", player_id, " cast Recon's Eye! Firing 3 Homing Trackers in a wide fan spread!")
			var target_mouse_pos = get_global_mouse_position()
			var base_dir = global_position.direction_to(target_mouse_pos)
			
			for i in range(-1, 2):
				# Increased spread weight from 0.12 to 0.25 (approx. 14 degrees per bullet slot)
				# This pushes the top and bottom bullets outward into a visible fan shape at launch.
				var spread_angle = i * 0.75
				var rotated_dir = base_dir.rotated(spread_angle)
				
				if multiplayer.multiplayer_peer != null:
					rpc("network_spawn_projectile", "tracking_normal", global_position, rotated_dir, 0.0)
				else:
					local_spawn_projectile("tracking_normal", global_position, rotated_dir, 0.0)
		"Recons Will":
			print("Player ", player_id, " cast Recon's Will! Firing 5 Shotgun Spread!")
			var target_mouse_pos = get_global_mouse_position()
			var base_dir = global_position.direction_to(target_mouse_pos)
			for i in range(-2, 3):
				var spread_angle = i * 0.15 
				var rotated_dir = base_dir.rotated(spread_angle)
				if multiplayer.multiplayer_peer != null:
					rpc("network_spawn_projectile", "normal", global_position, rotated_dir, 0.0)
				else:
					local_spawn_projectile("normal", global_position, rotated_dir, 0.0)
		"Piercing Shot":
			fire_projectile("piercing_special")
		"Bouncing Shot":
			fire_projectile("bouncing_normal") 
		"Marksman":
			fire_projectile("marksman_normal")
		"Jerry Miculek":
			jerry_miculek_charges -= 1
			current_ammo = max_ammo
			is_reloading = false


func fire_projectile(type: String, vertical_spread_offset: float = 0.0) -> void:
	# Compute crosshair travel target vector based on where the local mouse click clicked!
	var target_mouse_pos = get_global_mouse_position()
	var fire_direction = global_position.direction_to(target_mouse_pos)
	
	# If online, we broadcast the shot execution so it spawns on both screens simultaneously
	if multiplayer.multiplayer_peer != null:
		rpc("network_spawn_projectile", type, global_position, fire_direction, vertical_spread_offset)
	else:
		local_spawn_projectile(type, global_position, fire_direction, vertical_spread_offset)

# --- NEW: P2P PROJECTILE SYNCHRONIZATION HOOK ---
@rpc("any_peer", "call_local", "reliable")
func network_spawn_projectile(type: String, start_pos: Vector2, fire_dir: Vector2, spread_offset: float) -> void:
	local_spawn_projectile(type, start_pos, fire_dir, spread_offset)

func local_spawn_projectile(type: String, start_pos: Vector2, fire_dir: Vector2, spread_offset: float) -> void:
	var bullet = Area2D.new()
	bullet.set_script(preload("res://Projectile.gd"))
	bullet.attacker_id = player_id
	bullet.damage_type = type
	
	# 1. ALWAYS add the child to the scene tree FIRST so Godot recognizes its coordinates
	get_parent().add_child(bullet)
	
	# 2. NOW it is safe to assign its spatial positions and directions!
	bullet.global_position = start_pos + (fire_dir * 45.0) + Vector2(0, spread_offset)
	
	# 3. Hand off the 360-degree mouse vector calculations downward to the bullet
	if bullet.has_method("set_vector_trajectory"):
		bullet.set_vector_trajectory(fire_dir)
	else:
		# Fallback parameter assignment
		bullet.direction = 1.0 if fire_dir.x > 0 else -1.0



func process_ai_behavior(_delta: float) -> void:
	var arena = get_parent()
	var enemy = arena.player1
	if is_instance_valid(enemy):
		ai_target_vector = enemy.position
		if position.distance_to(enemy.position) < 400.0 and time_since_last_normal >= normal_cooldown_time:
			fire_projectile("normal")
			time_since_last_normal = 0.0

func get_individual_bar_progress(bar_index: int) -> float:
	if special_charges > bar_index: return 1.0
	elif special_charges == bar_index: return special_charge_timer / special_cooldown_time
	return 0.0

func get_ammo_string() -> String:
	if character_class != "Cowboy": return ""
	if is_reloading: return " [RELOADING...]"
	var bars = ""
	for i in range(current_ammo): bars += "|"
	return " [AMMO: " + bars + " " + str(current_ammo) + "/" + str(max_ammo) + "]"

func get_ability_cooldown_percentage() -> float:
	if selected_ability == "Jerry Miculek": return float(jerry_miculek_charges) / 2.0
	return clampf(time_since_last_ability / active_ability_cooldown_time, 0.0, 1.0)

# Update this function at the bottom of Player.gd:
func get_ability_status_string() -> String:
	match selected_ability:
		"Jerry Miculek": 
			return " [Jerry Charges: " + str(jerry_miculek_charges) + "/2]"
		_:
			if time_since_last_ability >= active_ability_cooldown_time: 
				return " [SKILL READY]"
			return " [SKILL COOLDOWN]"

func take_damage(amount: int, is_special_hit: bool) -> void:
	if lives <= 0: return
	var final_damage = amount
	if character_class == "Recon" and is_special_hit: final_damage += 1
	var player_color = Color(0.2, 0.6, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.3)
	get_parent().spawn_hit_particles(global_position, player_color)
	current_health -= final_damage
	if current_health <= 0: lose_life()

func lose_life() -> void:
	lives -= 1
	current_health = max_health 
	if character_class == "Cowboy": current_ammo = max_ammo
	if lives <= 0:
		set_physics_process(false)
		set_process_unhandled_input(false)
		get_parent().trigger_game_over(player_id)
