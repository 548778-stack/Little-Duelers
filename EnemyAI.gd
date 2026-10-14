extends CharacterBody2D

@export var speed: float = 400.0
var player_id: int = 2
var is_ai: bool = true 

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
var jerry_miculek_charges: int = 2

# AI tracking references
var ai_reaction_timer: float = 0.0
var ai_target_vector: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Read current synchronized state choices straight from the arena manager parent
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	player_id = 2
	character_class = arena.p2_selected_character
	selected_ability = arena.p2_selected_skill
	lives = arena.starting_lives_setting
	
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
	current_health = max_health
	ai_target_vector = position

	# Build visual block shape for the Red Enemy Bot
	var visual = ColorRect.new()
	visual.size = Vector2(40, 80)
	visual.position = Vector2(-20, -40)
	visual.color = Color(1.0, 0.3, 0.3) # Crimson red
	add_child(visual)

	# Build physical collider shape
	var collider = CollisionShape2D.new()
	var box_shape = RectangleShape2D.new()
	box_shape.size = Vector2(40, 80)
	collider.shape = box_shape
	add_child(collider)

	print("🤖 Dedicated EnemyAI Initialized: Class: ", character_class, " | Ability: ", selected_ability)

func _physics_process(delta: float) -> void:
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

	# Run decision matrix processing
	process_ai_behavior(delta)
	
	var direction = Vector2.ZERO
	if position.distance_to(ai_target_vector) > 15.0:
		direction = position.direction_to(ai_target_vector)
			
	velocity = direction * speed
	move_and_slide()
	
	# Clamp positions inside the designated Right Half Territory quadrants
	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)

func process_ai_behavior(delta: float) -> void:
	ai_reaction_timer += delta
	if ai_reaction_timer < 0.08: return
	ai_reaction_timer = 0.0
	
	var arena = get_parent()
	var opponent = arena.player1
	if not is_instance_valid(opponent): return

	var danger_detected = false
	var danger_pos = Vector2.ZERO
	var incoming_bullet_count = 0

	for child in arena.get_children():
		if child.name.begins_with("@Area2D@") or child.has_method("set_vector_trajectory"):
			if child.get("attacker_id") != player_id:
				var dist = global_position.distance_to(child.global_position)
				if dist < 350.0:
					incoming_bullet_count += 1
					if not danger_detected:
						danger_detected = true
						danger_pos = child.global_position

	if danger_detected:
		var dodge_dir = 1.0 if danger_pos.y < global_position.y else -1.0
		ai_target_vector = global_position + Vector2(randf_range(-60, 60), dodge_dir * 180.0)
		if incoming_bullet_count > 2 and time_since_last_ability >= active_ability_cooldown_time:
			try_use_ability()
	elif incoming_bullet_count > 1 or (opponent.time_since_last_normal < 0.15 and abs(position.y - opponent.position.y) < 80.0):
		if abs(ai_target_vector.y - position.y) < 20.0:
			var swing_target_y = arena.get_viewport_rect().size.y - opponent.position.y
			var flank_x_offset = randf_range(100.0, 300.0)
			ai_target_vector = Vector2(arena.get_viewport_rect().size.x / 2.0 + flank_x_offset, swing_target_y)
	else:
		if randf() > 0.85:
			ai_target_vector = opponent.global_position + Vector2(randf_range(50, 200), randf_range(-90.0, 90.0))
		elif position.distance_to(ai_target_vector) < 40.0:
			ai_target_vector = opponent.global_position

	var absolute_dist_x = abs(position.x - opponent.position.x)
	var absolute_dist_y = abs(position.y - opponent.position.y)
	
	if absolute_dist_x > 200.0 and absolute_dist_y < 180.0:
		if time_since_last_ability >= active_ability_cooldown_time:
			match character_class:
				"Recon":
					if selected_ability == "Recons Eye" or (selected_ability == "Recons Will" and absolute_dist_x < 500.0):
						try_use_ability()
				"Slingshotter":
					if selected_ability == "Bouncing Shot" or (selected_ability == "Piercing Shot" and absolute_dist_y < 40.0):
						try_use_ability()
				"Cowboy":
					if selected_ability == "Marksman" and absolute_dist_x > 400.0:
						try_use_ability()
					elif selected_ability == "Jerry Miculek" and current_ammo <= 1:
						try_use_ability()

		if character_class == "Cowboy" and current_ammo <= 0:
			start_reload()
		elif time_since_last_normal >= normal_cooldown_time and not is_reloading:
			var prediction_offset = opponent.velocity * 0.15
			var fire_target = opponent.global_position + prediction_offset
			var fire_direction = global_position.direction_to(fire_target)
			local_spawn_projectile("normal", global_position, fire_direction, 0.0)
			time_since_last_normal = 0.0
			if character_class == "Cowboy":
				current_ammo -= 1

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
			var target_opp = get_parent().player1
			if is_instance_valid(target_opp):
				var base_dir = global_position.direction_to(target_opp.global_position)
				for i in range(-1, 2):
					var spread_angle = i * 0.75
					local_spawn_projectile("tracking_normal", global_position, base_dir.rotated(spread_angle), 0.0)
		"Recons Will":
			var target_opp = get_parent().player1
			if is_instance_valid(target_opp):
				var base_dir = global_position.direction_to(target_opp.global_position)
				for i in range(-2, 3):
					local_spawn_projectile("normal", global_position, base_dir.rotated(i * 0.15), 0.0)
		"Piercing Shot":
			var target_opp = get_parent().player1
			if is_instance_valid(target_opp):
				local_spawn_projectile("piercing_special", global_position, global_position.direction_to(target_opp.global_position), 0.0)
		"Bouncing Shot":
			var target_opp = get_parent().player1
			if is_instance_valid(target_opp):
				local_spawn_projectile("bouncing_normal", global_position, global_position.direction_to(target_opp.global_position), 0.0)
		"Marksman":
			var target_opp = get_parent().player1
			if is_instance_valid(target_opp):
				local_spawn_projectile("marksman_normal", global_position, global_position.direction_to(target_opp.global_position), 0.0)
		"Jerry Miculek":
			jerry_miculek_charges -= 1
			current_ammo = max_ammo
			is_reloading = false

func local_spawn_projectile(type: String, start_pos: Vector2, fire_dir: Vector2, spread_offset: float) -> void:
	var bullet = Area2D.new()
	bullet.set_script(preload("res://Projectile.gd"))
	bullet.attacker_id = player_id
	bullet.damage_type = type
	
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
	
	get_parent().add_child(bullet)
	bullet.global_position = start_pos + (fire_dir * 45.0) + Vector2(0, spread_offset)
	
	if bullet.has_method("set_vector_trajectory"):
		bullet.set_vector_trajectory(fire_dir)

func take_damage(amount: float, is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if lives <= 0: return
	var final_damage = amount
	if character_class == "Recon" and is_special_hit: final_damage += 1.0
	if is_crit_hit: get_parent().spawn_crit_hit_marker(global_position)
	
	current_health -= final_damage
	var particle_color = Color(1.0, 0.85, 0.2) if is_crit_hit else Color(1.0, 0.3, 0.3)
	get_parent().spawn_hit_particles(global_position, particle_color)
	
	if current_health <= 0.0: lose_life()

func lose_life() -> void:
	lives -= 1
	current_health = max_health 
	if character_class == "Cowboy": current_ammo = max_ammo
	if lives <= 0:
		set_physics_process(false)
		get_parent().trigger_game_over(player_id)

# Helper methods for the Arena HUD updates to read
func get_individual_bar_progress(bar_index: int) -> float:
	if special_charges > bar_index: 
		return 1.0
	elif special_charges == bar_index: 
		return special_charge_timer / special_cooldown_time
	return 0.0

func get_ammo_string() -> String:
	if character_class != "Cowboy": 
		return ""
	if is_reloading: 
		return " [RELOADING...]"
	var bars = ""
	for i in range(current_ammo): 
		bars += "|"
	return " [AMMO: " + bars + " " + str(current_ammo) + "/" + str(max_ammo) + "]"

func get_ability_cooldown_percentage() -> float:
	if selected_ability == "Jerry Miculek": 
		return float(jerry_miculek_charges) / 2.0
	return clampf(time_since_last_ability / active_ability_cooldown_time, 0.0, 1.0)

func get_ability_status_string() -> String:
	match selected_ability:
		"Jerry Miculek": 
			return " [Jerry Charges: " + str(jerry_miculek_charges) + "/2]"
	if time_since_last_ability >= active_ability_cooldown_time: 
		return " [SKILL READY]"
	return " [SKILL COOLDOWN]"
