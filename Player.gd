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
var max_health: float = 3.0
var current_health: float = 3.0
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

	# --- FIXED: CLEAN WASD DIRECTION CALCULATION ---
	# Both computers use the exact same WASD tokens safely now!
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			
	# Inside Player.gd -> _physics_process(delta) function:
	velocity = direction * speed
	move_and_slide()
	
	# --- QUADRANT AND TERRITORY LOCKS ---
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
	
	# --- 🎰 CRIT AND DAMAGE BALANCING MATRIX ---
	var base_damage = 1.0
	var crit_chance = 0.15 # 15% standard baseline crit chance
	
	# Balance Class Overrides
	if character_class == "Cowboy":
		base_damage = 1.4 # Cowboy bullets deal harder decimal base damage!
		crit_chance = 0.25 # Cowboy gets a 25% crit chance on normal shots
		
	if type == "special":
		base_damage = 2.0
	elif type == "marksman_normal":
		# Cowboy Marksman custom ability is GUARANTEED to critically hit!
		crit_chance = 1.0 
		
	# Roll the random percentage check to see if this bullet crits
	var rolled_crit = randf() < crit_chance
	if rolled_crit:
		base_damage *= 2.0 # Critical strikes deal double damage!
		
	# Pass these custom stats straight down into the projectile instance data fields [0.1]
	bullet.set_meta("damage_amount", base_damage)
	bullet.set_meta("is_critical", rolled_crit)
	
	get_parent().add_child(bullet)
	bullet.global_position = start_pos + (fire_dir * 45.0) + Vector2(0, spread_offset)
	
	if bullet.has_method("set_vector_trajectory"):
		bullet.set_vector_trajectory(fire_dir)
	else:
		bullet.direction = 1.0 if fire_dir.x > 0 else -1.0




# Replace the process_ai_behavior function inside your Player.gd file:

func process_ai_behavior(delta: float) -> void:
	ai_reaction_timer += delta
	if ai_reaction_timer < 0.08: return # Blazing fast 80ms tick rate response time
	ai_reaction_timer = 0.0
	
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	# Locate our opponent (If AI is P2, opponent is P1)
	var opponent = arena.player1 if player_id == 2 else arena.player2
	if not is_instance_valid(opponent): return

	var danger_detected = false
	var danger_pos = Vector2.ZERO
	var incoming_bullet_count = 0

	# --- 1. SCAN RADAR FOR INCOMING DANGER ---
	for child in arena.get_children():
		if child.name.begins_with("@Area2D@") or child.has_method("set_vector_trajectory"):
			# If this bullet belongs to the other player and is moving towards the AI's half
			if child.get("attacker_id") != player_id:
				var dist = global_position.distance_to(child.global_position)
				if dist < 350.0: # Bullet is approaching danger circle bubble
					incoming_bullet_count += 1
					if not danger_detected:
						danger_detected = true
						danger_pos = child.global_position

	# --- 2. ADAPTIVE DECISION TREE LAYERS ---
	if danger_detected:
		# LAYER A: INCOMING DAMAGE EVASION
		# Slide aggressively away from the incoming projectile vector path height
		var dodge_dir = 1.0 if danger_pos.y < global_position.y else -1.0
		ai_target_vector = global_position + Vector2(randf_range(-60, 60), dodge_dir * 180.0)
		
		# If the player is spamming heavily, try to fire a protective counter-shot while dodging
		if incoming_bullet_count > 2 and time_since_last_ability >= active_ability_cooldown_time:
			try_use_ability()
			
	elif incoming_bullet_count > 1 or (opponent.time_since_last_normal < 0.15 and abs(position.y - opponent.position.y) < 80.0):
		# LAYER B: ANTI-SPAM FLANKING MANEUVER
		# If player is spamming straight shots, break mirroring! Swing out to a wild diagonal angle.
		if abs(ai_target_vector.y - position.y) < 20.0:
			var swing_target_y = arena.get_viewport_rect().size.y - opponent.position.y
			var flank_x_offset = randf_range(100.0, 300.0) if player_id == 2 else randf_range(-300.0, -100.0)
			ai_target_vector = Vector2(arena.get_viewport_rect().size.x / 2.0 + flank_x_offset, swing_target_y)
			
	else:
		# LAYER C: POSITION MIRROR HUNT & ANGLE SEEKING
		# Smooth tracking pursuit, adding slight random micro-shifts so it doesn't stay rigid
		if randf() > 0.85:
			ai_target_vector = opponent.global_position + Vector2(randf_range(50, 200) * (1 if player_id == 2 else -1), randf_range(-90.0, 90.0))
		elif position.distance_to(ai_target_vector) < 40.0:
			ai_target_vector = opponent.global_position

	# --- 3. ATTACK EXECUTION MATRICES ---
	var absolute_dist_x = abs(position.x - opponent.position.x)
	var absolute_dist_y = abs(position.y - opponent.position.y)
	
	# If the AI has a viable shot angle or line-of-sight opportunity
	if absolute_dist_x > 200.0 and absolute_dist_y < 180.0:
		
		# SMART SKILL MANAGEMENT: Smartly use class abilities based on tactical viability!
		if time_since_last_ability >= active_ability_cooldown_time:
			match character_class:
				"Recon":
					# Recon uses Eye immediately to ensure accuracy, or Will if you get too close
					if selected_ability == "Recons Eye" or (selected_ability == "Recons Will" and absolute_dist_x < 500.0):
						try_use_ability()
				"Slingshotter":
					# Slingshotter casts bouncing shot if you hide behind obstacles or move wide
					if selected_ability == "Bouncing Shot" or (selected_ability == "Piercing Shot" and absolute_dist_y < 40.0):
						try_use_ability()
				"Cowboy":
					# Cowboy sniper activates Marksman from range, uses Jerry if completely out of chambers
					if selected_ability == "Marksman" and absolute_dist_x > 400.0:
						try_use_ability()
					elif selected_ability == "Jerry Miculek" and current_ammo <= 1:
						try_use_ability()

		# Standard Primary Fire Loops
		if character_class == "Cowboy" and current_ammo <= 0:
			start_reload()
		elif time_since_last_normal >= normal_cooldown_time and not is_reloading:
			# Predict opponent movement vectors slightly rather than shooting directly back
			var prediction_offset = opponent.velocity * 0.15
			var fire_target = opponent.global_position + prediction_offset
			
			# Call the dynamic firing matrix using the computed directional targets
			var fire_direction = global_position.direction_to(fire_target)
			if multiplayer.multiplayer_peer != null:
				rpc("network_spawn_projectile", "normal", global_position, fire_direction, 0.0)
			else:
				local_spawn_projectile("normal", global_position, fire_direction, 0.0)
			
			time_since_last_normal = 0.0
			if character_class == "Cowboy":
				current_ammo -= 1


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

func take_damage(amount: float, is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if lives <= 0: return
	
	var final_damage = amount
	
	if character_class == "Recon" and is_special_hit:
		final_damage += 1.0
		print("💥 Critical Vulnerability hit! Recon took extra damage!")
		
	# --- NEW: TRIGGER VISUAL CRIT POPUP ---
	if is_crit_hit:
		print("🎯 CRITICAL HIT REGISTERED! 2x Damage applied!")
		# Call our new function on the arena parent to spawn the floating text
		get_parent().spawn_crit_hit_marker(global_position)
	
	current_health -= final_damage
	
	# Flashes golden particles for crits, matching class colors for standard hits
	var particle_color = Color(1.0, 0.85, 0.2) if is_crit_hit else (Color(0.2, 0.6, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.3))
	get_parent().spawn_hit_particles(global_position, particle_color)
	
	if current_health <= 0.0:
		lose_life()

func lose_life() -> void:
	lives -= 1
	current_health = max_health 
	if character_class == "Cowboy": 
		current_ammo = max_ammo
	if lives <= 0:
		set_physics_process(false)
		set_process_unhandled_input(false)
		get_parent().trigger_game_over(player_id)
