extends Area2D

var speed: float = 700.0
var direction: float = 1.0 
var attacker_id: int = 1
var damage_type: String = "normal"

# --- 360 DEGREE MOUSE TRAJECTORY VECTOR ---
var velocity_vector: Vector2 = Vector2.RIGHT

var target_initial_y: float = -999.0
var marksman_redirected: bool = false

# --- BOUNCING MECHANICS STACKS ---
var bounce_count: int = 0
var max_bounces: int = 3

func set_vector_trajectory(dir_vector: Vector2) -> void:
	velocity_vector = dir_vector.normalized()
	# Rotate the visual laser rectangle to face the direct travel line perfectly
	rotation = velocity_vector.angle()

func _ready() -> void:
	var visual = ColorRect.new()
	
	match damage_type:
		"special":
			visual.size = Vector2(24, 12)
			visual.color = Color(1.0, 0.85, 0.2)
			speed = 900.0
		"piercing_special":
			visual.size = Vector2(24, 8)
			visual.color = Color(0.8, 0.2, 1.0)
			speed = 950.0
		"tracking_normal":
			visual.size = Vector2(16, 6)
			visual.color = Color(0.2, 1.0, 0.4)
			speed = 600.0
		"marksman_normal":
			visual.size = Vector2(16, 6)
			visual.color = Color(1.0, 0.5, 0.0)
			speed = 800.0
		"bouncing_normal":
			# NEW: Visually render the Slingshotter's bouncing projectile block
			visual.size = Vector2(16, 8)
			visual.color = Color(0.0, 0.9, 1.0) # Bright Glowing Neon Cyan
			speed = 750.0
		_:
			visual.size = Vector2(16, 6)
			visual.color = Color(1.0, 1.0, 1.0)
			
	visual.position = -visual.size / 2 
	add_child(visual)
	
	var collision = CollisionShape2D.new()
	var box_shape = RectangleShape2D.new()
	box_shape.size = visual.size
	collision.shape = box_shape
	add_child(collision)
	
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var arena = get_parent()
	var enemy = arena.player2 if attacker_id == 1 else arena.player1
	
	var is_tracking_bullet = (damage_type == "tracking_normal")
	
	# --- 🤠 RESTORED: FIXED POSITION MARKSMAN LOCK ---
	if damage_type == "marksman_normal" and is_instance_valid(enemy):
		# Capture the target coordinates ONLY ONCE when crossing the center lane threshold
		if target_initial_y == -999.0 and abs(position.x - 576.0) < 200.0:
			# FIX: Save the entire stationary 2D position vector where the enemy is standing right now!
			# We use a custom metadata slot to freeze this vector permanently
			set_meta("marksman_target_pos", enemy.global_position)
			marksman_redirected = true
		
		if marksman_redirected:
			is_tracking_bullet = true

	# --- 🛡️ UNIVERSAL SMOOTH STEERING & RECOVERY MATRIX ---
	if is_tracking_bullet:
		var target_dir = Vector2.ZERO
		
		# RECON KIT: Heat-seeking tracking checks enemy coordinates live
		if damage_type == "tracking_normal" and is_instance_valid(enemy):
			target_dir = global_position.direction_to(enemy.global_position).normalized()
		# COWBOY KIT: Marksman guides itself strictly to the frozen historical coordinates!
		elif damage_type == "marksman_normal" and has_meta("marksman_target_pos"):
			var fixed_pos = get_meta("marksman_target_pos")
			target_dir = global_position.direction_to(fixed_pos).normalized()
			
			# If the bullet reaches its target height, let it cruise forward naturally on its axis
			if global_position.distance_to(fixed_pos) < 20.0 or (direction > 0 and global_position.x > fixed_pos.x) or (direction < 0 and global_position.x < fixed_pos.x):
				is_tracking_bullet = false # Turn off steering so it flies straight out
		
		# Only process steering if we have a valid target path locked
		if target_dir != Vector2.ZERO:
			# 2. Obstacle Evasion Radar
			var avoidance_force = Vector2.ZERO
			for child in arena.get_children():
				if child.name.begins_with("Obstacle_"):
					var dist = global_position.distance_to(child.global_position)
					if dist < 110.0:
						var approach_check = velocity_vector.dot(global_position.direction_to(child.global_position))
						if approach_check > 0.0:
							var away_dir = child.global_position.direction_to(global_position)
							var strength = (110.0 - dist) / 110.0
							avoidance_force += away_dir * strength * 4.0

			# 3. Combine trajectory pull and avoidance push seamlessly
			var final_steering_dir = (target_dir + avoidance_force).normalized()
			
			# 4. Smooth turning calculation
			var turn_weight = 8.0 if damage_type == "marksman_normal" else 5.0
			velocity_vector = velocity_vector.move_toward(final_steering_dir, delta * turn_weight).normalized()
			rotation = velocity_vector.angle()

	# --- UNIFIED FLIGHT MOTION PHYSICS ---
	global_position += velocity_vector * speed * delta
	
	var view_size = get_viewport_rect().size
	
	# --- SLINGSHOTTER BOUNCING SHOT ENGINE ---
	if damage_type == "bouncing_normal":
		var hit_wall = false
		if global_position.y <= 15.0:
			global_position.y = 15.0
			velocity_vector.y = abs(velocity_vector.y)
			hit_wall = true
		elif global_position.y >= view_size.y - 15.0:
			global_position.y = view_size.y - 15.0
			velocity_vector.y = -abs(velocity_vector.y)
			hit_wall = true
			
		if global_position.x <= 15.0:
			global_position.x = 15.0
			velocity_vector.x = abs(velocity_vector.x)
			hit_wall = true
		elif global_position.x >= view_size.x - 15.0:
			global_position.x = view_size.x - 15.0
			velocity_vector.x = -abs(velocity_vector.x)
			hit_wall = true
			
		if hit_wall:
			bounce_count += 1
			rotation = velocity_vector.angle()
			if arena.has_method("spawn_hit_particles"):
				arena.spawn_hit_particles(global_position, Color(1.0, 1.0, 1.0))
			if bounce_count >= max_bounces:
				queue_free()
				return
	else:
		# Standard boundary cleanup rule
		if position.x < -50 or position.x > view_size.x + 50 or position.y < -50 or position.y > view_size.y + 50:
			queue_free()



func _on_body_entered(body: Node) -> void:
	if body.name.begins_with("Obstacle_"):
		if damage_type == "piercing_special": return 
		queue_free()
		return

	if body.has_method("take_damage"):
		if body.player_id != attacker_id:
			# Safely extract the custom damage values and critical modifiers we attached [0.1]
			var damage_val = 1.0
			var is_crit = false
			
			if has_meta("damage_amount"):
				damage_val = get_meta("damage_amount")
			if has_meta("is_critical"):
				is_crit = get_meta("is_critical")
				
			# If a normal bullet didn't register custom metadata, fall back to default rules
			if not has_meta("damage_amount"):
				if damage_type == "special": damage_val = 2.0
				
			var is_special = damage_type.contains("special")
			
			# Deliver the precise floating point damage payload!
			body.take_damage(damage_val, is_special, is_crit)
			queue_free()
