extends CharacterBody2D

# --- YOUR ORIGINAL VARIABLES (PRESERVED PERFECTLY) ---
@export var speed: float = 500.0
var player_id: int = 1

# Health & Match settings variables
var max_health: float = 3.0
var current_health: float = 3.0
var lives: int = 3
var local_ability_timer: float = 5.0 # Tracks your own skill clock locally!

var character_class: String = "Slingshotter"
var selected_ability: String = "None"

var normal_cooldown_time: float = 0.4    
var time_since_last_normal: float = 0.0  

var is_reloading: bool = false
var current_ammo: int = 6
var max_ammo: int = 6
var special_charges: int = 3

func _ready() -> void:
	# Automatically determine if we are P1 or P2 by our scene tree node name
	if name == "Player1":
		player_id = 1
	elif name == "Player2":
		player_id = 2
		
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	# Color code the box visuals dynamically based on our ID
	if has_node("ColorRect"):
		if player_id == 1:
			$ColorRect.color = Color(0.2, 0.6, 1.0) # Radiant Blue
		else:
			$ColorRect.color = Color(1.0, 0.3, 0.3) # Crimson Red

func _physics_process(delta: float) -> void:
	time_since_last_normal += delta
	local_ability_timer += delta
	
	# 🛡️ LOCAL INPUT GUARD: Server drives P1, Client drives P2
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server() and player_id != 1: return
		if not multiplayer.is_server() and player_id != 2: return
		
	# Process pure 2D WASD movements natively
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	
	# Enforce 4-Quadrant territory boundary tracks
	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	
	if player_id == 1:
		position.x = clampf(position.x, 40.0, mid_x - 30.0)
	else:
		position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)

func _input(event: InputEvent) -> void:
	# Prevent machines from reading each other's mouse clicks
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server() and player_id != 1: return
		if not multiplayer.is_server() and player_id != 2: return

	var arena = get_parent()
	if not is_instance_valid(arena): return

	# --- MOUSE LEFT CLICK: PRIMARY LAUNCHER ---
	if event.is_action_pressed("attack_normal"):
		if is_reloading: return
		if character_class == "Cowboy" and current_ammo <= 0:
			if arena.has_method("start_reload"): arena.start_reload()
			return
			
		if time_since_last_normal >= normal_cooldown_time:
			# RESTORED: Direct script instantiation path! [0.1]
			var bullet = Area2D.new()
			bullet.set_script(preload("res://Projectile.gd"))
			bullet.attacker_id = player_id
			bullet.damage_type = "normal"
			
			var base_damage = 1.4 if character_class == "Cowboy" else 1.0
			var crit_chance = 0.25 if character_class == "Cowboy" else 0.15
			var rolled_crit = randf() < crit_chance
			if rolled_crit: base_damage *= 2.0
			
			bullet.set_meta("damage_amount", base_damage)
			bullet.set_meta("is_critical", rolled_crit)
			
			arena.add_child(bullet)
			
			var target_mouse_pos = get_global_mouse_position()
			var fire_direction = global_position.direction_to(target_mouse_pos)
			bullet.global_position = global_position + (fire_direction * 45.0)
			
			if bullet.has_method("set_vector_trajectory"):
				bullet.set_vector_trajectory(fire_direction)
				
			time_since_last_normal = 0.0
			if character_class == "Cowboy":
				current_ammo -= 1

	# --- MOUSE RIGHT CLICK: SPECIAL FIRE AMMUNITION ---
	elif event.is_action_pressed("attack_special"):
		if special_charges > 0:
			var bullet = Area2D.new()
			bullet.set_script(preload("res://Projectile.gd"))
			bullet.attacker_id = player_id
			bullet.damage_type = "special"
			bullet.set_meta("damage_amount", 2.0)
			bullet.set_meta("is_critical", false)
			
			arena.add_child(bullet)
			
			var target_mouse_pos = get_global_mouse_position()
			var fire_direction = global_position.direction_to(target_mouse_pos)
			bullet.global_position = global_position + (fire_direction * 45.0)
			
			if bullet.has_method("set_vector_trajectory"):
				bullet.set_vector_trajectory(fire_direction)
				
			special_charges -= 1

	elif event.is_action_pressed("attack_ability"):
		var active_skill = arena.p1_selected_skill if player_id == 1 else arena.p2_selected_skill
		
		if local_ability_timer < arena.active_ability_cooldown_time:
			print("⏳ Skill is recharging! Your local clock is at: ", local_ability_timer)
			return
			
		var target_mouse_pos = get_global_mouse_position()
		var fire_direction = global_position.direction_to(target_mouse_pos)
		
		if active_skill == "Recons Eye":
			print("👁️ Spawning RECON'S EYE 3-Shot Fan Array!")
			for i in range(-1, 2):
				var bullet = Area2D.new()
				bullet.set_script(preload("res://Projectile.gd"))
				bullet.attacker_id = player_id
				bullet.damage_type = "tracking_normal"
				bullet.set_meta("damage_amount", 1.0)
				bullet.set_meta("is_critical", false)
				
				arena.add_child(bullet)
				
				var spread_angle = i * 0.18
				var rotated_direction = fire_direction.rotated(spread_angle)
				bullet.global_position = global_position + (rotated_direction * 45.0)
				
				if bullet.has_method("set_vector_trajectory"):
					bullet.set_vector_trajectory(rotated_direction)
		else:
			var bullet_type = ""
			var base_damage = 1.0
			var is_crit = false
			
			if active_skill == "Piercing Shot":
				bullet_type = "piercing_special"
				base_damage = 2.0
			elif active_skill == "Bouncing Shot":
				bullet_type = "bouncing_normal"
				base_damage = 1.0
			elif active_skill == "Marksman":
				bullet_type = "marksman_normal"
				base_damage = 2.8
				is_crit = true
			else:
				bullet_type = "bouncing_normal"
			
			var bullet = Area2D.new()
			bullet.set_script(preload("res://Projectile.gd"))
			bullet.attacker_id = player_id
			bullet.damage_type = bullet_type
			
			bullet.set_meta("damage_amount", base_damage)
			bullet.set_meta("is_critical", is_crit)
			
			arena.add_child(bullet)
			bullet.global_position = global_position + (fire_direction * 45.0)
			
			if bullet.has_method("set_vector_trajectory"):
				bullet.set_vector_trajectory(fire_direction)
				
			print("🎯 Cast Ability successfully: ", active_skill, " -> ", bullet_type)
				
		local_ability_timer = 0.0
		print("🎯 Cast Ability successfully! Local clock reset to 0.0.")



# --- RESTORED: P2P PROJECTILE SYNCHRONIZATION HOOK ---
@rpc("any_peer", "call_local", "reliable")
func network_spawn_projectile(type: String, start_pos: Vector2, fire_dir: Vector2, spread_offset: float) -> void:
	local_spawn_projectile(type, start_pos, fire_dir, spread_offset)

func local_spawn_projectile(type: String, start_pos: Vector2, fire_dir: Vector2, spread_offset: float = 0.0) -> void:
	var arena = get_parent()
	var bullet = Area2D.new()
	bullet.set_script(preload("res://Projectile.gd"))
	bullet.attacker_id = player_id
	bullet.damage_type = type
	
	# Process custom damage attributes straight down into the bullet
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
	
	# Add child to the scene tree FIRST so coordinates compute accurately
	arena.add_child(bullet)
	bullet.global_position = start_pos + (fire_dir * 45.0) + Vector2(0, spread_offset)
	
	if bullet.has_method("set_vector_trajectory"):
		bullet.set_vector_trajectory(fire_dir)
	else:
		bullet.direction = 1.0 if fire_dir.x > 0 else -1.0

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
