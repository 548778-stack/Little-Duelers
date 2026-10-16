extends CharacterBody2D

@export var speed: float = 500.0
var player_id: int = 1

# Health & Match settings variables
var max_health: float = 3.0
var current_health: float = 3.0
var lives: int = 3

var character_class: String = "Slingshotter"
var selected_ability: String = "None"

var normal_cooldown_time: float = 0.4    
var time_since_last_normal: float = 0.0  

# Inside Player.gd -> Update your _ready() loop:

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	# --- 🌐 FORCE SYNCHRONIZER AUTHORITY OVERRIDE ---
	var sync_node = get_node_or_null("MultiplayerSynchronizer")
	if sync_node:
		sync_node.set_multiplayer_authority(get_multiplayer_authority())
		print("🖥️ Player1 Synchronizer authority successfully locked to Host.")
	
	# Configure Player 1 from the synchronized arena lobby data
	character_class = arena.p1_selected_character if name == "Player1" else arena.p2_selected_character
	selected_ability = arena.p1_selected_skill if name == "Player1" else arena.p2_selected_skill
	lives = arena.starting_lives_setting
	current_health = max_health
	
	# Color it Blue for Player 1
	if has_node("ColorRect"):
		$ColorRect.color = Color(0.2, 0.6, 1.0)
		
	# Apply balances
	match character_class:
		"Recon": speed = 600.0
		"Slingshotter": speed = 475.0
		"Cowboy": speed = 400.0

func _physics_process(delta: float) -> void:
	time_since_last_normal += delta
	
	# 🛡️ THE LAN HARDWARE GUARD: Only allow inputs if this terminal is the Host!
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	# Read the Host keyboard movements natively
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	
	# Clamp positions inside the designated LEFT half quadrants boundary tracks
	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	position.x = clampf(position.x, 40.0, mid_x - 30.0)

func _input(event: InputEvent) -> void:
	# Network Guard: Only track inputs if this terminal physically controls Player 1
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	# Mouse Left Click: Normal Attack
	if event.is_action_pressed("attack_normal"):
		if has_method("is_reloading") and get("is_reloading"): return
		if character_class == "Cowboy" and get("current_ammo") <= 0:
			if has_method("start_reload"): call("start_reload")
			return
			
		if time_since_last_normal >= normal_cooldown_time:
			fire_projectile("normal")
			time_since_last_normal = 0.0
			if character_class == "Cowboy" and "current_ammo" in self:
				set("current_ammo", get("current_ammo") - 1)
				if get("current_ammo") <= 0: 
					if has_method("start_reload"): call("start_reload")
				
	# Mouse Right Click: Special Attack (FIXED)
	elif event.is_action_pressed("attack_special"):
		if "special_charges" in self and get("special_charges") > 0:
			fire_projectile("special")
			set("special_charges", get("special_charges") - 1)
			print("🔵 P1 fired Special Attack!")
			
	# Mouse Wheel Click / Scroll: Active Class Ability (FIXED)
	elif event.is_action_pressed("attack_ability"):
		if has_method("try_use_ability"):
			call("try_use_ability")
			print("🔵 P1 cast Class Ability!")

@rpc("any_peer", "call_local", "reliable")
func network_spawn_projectile(type: String, start_pos: Vector2, fire_dir: Vector2) -> void:
	local_spawn_projectile(type, start_pos, fire_dir)

# Paste this function at the very bottom of your Player.gd file:

func fire_projectile(type: String, vertical_spread_offset: float = 0.0) -> void:
	# Compute crosshair travel target vector based on where the local mouse click clicked!
	var target_mouse_pos = get_global_mouse_position()
	var fire_direction = global_position.direction_to(target_mouse_pos)
	
	# If online, we broadcast the shot execution so it spawns on both screens simultaneously
	if multiplayer.multiplayer_peer != null:
		rpc("network_spawn_projectile", type, global_position, fire_direction, vertical_spread_offset)
	else:
		local_spawn_projectile(type, global_position, fire_direction, vertical_spread_offset)

func local_spawn_projectile(type: String, start_pos: Vector2, fire_dir: Vector2, spread_offset: float = 0.0) -> void:
	var arena = get_parent()
	var bullet = Area2D.new()
	bullet.set_script(preload("res://Projectile.gd"))
	bullet.attacker_id = 1 # Player 1 owns this laser
	bullet.damage_type = type
	
	# Pass custom damage attributes straight down into the bullet
	var base_damage = 1.0
	var crit_chance = 0.15
	if character_class == "Cowboy":
		base_damage = 1.4
		crit_chance = 0.25
	if type == "special": base_damage = 2.0
	elif type == "marksman_normal": crit_chance = 1.0 
		
	var rolled_crit = randf() < crit_chance
	if rolled_crit: base_damage *= 2.0
		
	bullet.set_meta("damage_amount", base_damage)
	bullet.set_meta("is_critical", rolled_crit)
	
	arena.add_child(bullet)
	bullet.global_position = start_pos + (fire_dir * 45.0) + Vector2(0, spread_offset)
	
	if bullet.has_method("set_vector_trajectory"):
		bullet.set_vector_trajectory(fire_dir)


func take_damage(amount: float, _is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if lives <= 0: return
	if is_crit_hit: get_parent().spawn_crit_hit_marker(global_position)
	current_health -= amount
	get_parent().spawn_hit_particles(global_position, Color(0.2, 0.6, 1.0))
	if current_health <= 0.0:
		lives -= 1
		current_health = max_health
		if lives <= 0: get_parent().trigger_game_over(1)

# Helper methods for the Arena HUD updates to read safely
func get_ammo_string() -> String:
	return ""

func get_ability_status_string() -> String:
	return " [SKILL READY]"

func get_ability_cooldown_percentage() -> float:
	return 1.0

func get_individual_bar_progress(_index: int) -> float:
	return 1.0
