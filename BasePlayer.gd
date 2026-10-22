extends CharacterBody2D
class_name BasePlayer

@export var speed: float = 500.0
var player_id: int = 1
var max_health: float = 3.0
var current_health: float = 3.0
var lives: int = 3
var character_class: String = "Slingshotter"
var selected_ability: String = "None"
var normal_cooldown_time: float = 0.4    
var time_since_last_normal: float = 0.0  
var is_reloading: bool = false
var current_ammo: int = 6
var max_ammo: int = 6
var special_charges: int = 3
var local_ability_timer: float = 5.0
var special_charge_timer: float = 0.0

func _enter_tree() -> void:
	if multiplayer.multiplayer_peer != null and name.is_valid_int():
		set_multiplayer_authority(name.to_int())

func _ready() -> void:
	await get_tree().physics_frame
	match character_class:
		"Recon": speed = 600.0
		"Slingshotter": speed = 475.0
		"Cowboy":
			speed = 400.0
			normal_cooldown_time = 0.15
			current_ammo = max_ammo
	current_health = max_health
	time_since_last_normal = normal_cooldown_time
	
	if name == "1" or name == "Player1":
		player_id = 1
		if has_node("ColorRect"): $ColorRect.color = Color(0.2, 0.6, 1.0)
	else:
		player_id = 2
		if has_node("ColorRect"): $ColorRect.color = Color(1.0, 0.3, 0.3)

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority(): return
	time_since_last_normal += delta
	local_ability_timer += delta
	
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	
	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	if name == "1" or name == "Player1": position.x = clampf(position.x, 40.0, mid_x - 30.0)
	else: position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)

func _input(event: InputEvent) -> void:
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority(): return
	var arena = get_parent()
	var target_mouse_pos = get_global_mouse_position()
	var fire_direction = global_position.direction_to(target_mouse_pos)

	if event.is_action_pressed("attack_normal"):
		if is_reloading or (character_class == "Cowboy" and current_ammo <= 0): return
		if time_since_last_normal >= normal_cooldown_time:
			# INSTRUCTION FIXED: Modern dot-syntax RPC routing!
			request_server_bullet_spawn.rpc("normal", global_position, fire_direction, player_id, character_class)
			time_since_last_normal = 0.0
			if character_class == "Cowboy": current_ammo -= 1

# INSTRUCTION FIXED: Tag modified to call_remote to block clients from local phantom firing desyncs! [1.2]
@rpc("any_peer", "call_remote", "reliable")
func request_server_bullet_spawn(type: String, start_pos: Vector2, fire_dir: Vector2, owner_id: int, owner_class: String) -> void:
	if multiplayer.is_server():
		var arena = get_parent()
		var projectile_scene = preload("res://Projectile.tscn")
		var bullet = projectile_scene.instantiate()
		bullet.attacker_id = owner_id
		bullet.damage_type = type
		arena.add_child(bullet, true)
		bullet.global_position = start_pos + (fire_dir * 45.0)
		if bullet.has_method("set_vector_trajectory"): bullet.set_vector_trajectory(fire_dir)

func get_ammo_string() -> String:
	if character_class != "Cowboy": return ""
	var bars = ""
	for i in range(current_ammo): bars += "|"
	return " [AMMO: " + bars + "]"

func get_ability_status_string() -> String:
	return " [READY]" if local_ability_timer >= 5.0 else " [CD]"

func take_damage(amount: float, is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if lives <= 0: return
	var final_damage = amount
	if character_class == "Recon" and is_special_hit: final_damage += 1.0
	if is_crit_hit: get_parent().spawn_crit_hit_marker(global_position)
	
	current_health -= final_damage
	var particle_color = Color(1.0, 0.85, 0.2) if is_crit_hit else (Color(0.2, 0.6, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.3))
	get_parent().spawn_hit_particles(global_position, particle_color)
	if current_health <= 0.0: lose_life()

func lose_life() -> void:
	lives -= 1
	current_health = max_health 
	if character_class == "Cowboy": current_ammo = max_ammo
	if lives <= 0:
		set_physics_process(false)
		get_parent().trigger_game_over(player_id)


func get_ability_cooldown_percentage() -> float:
	var arena = get_parent()
	if not is_instance_valid(arena): return 1.0
	return clampf(local_ability_timer / arena.active_ability_cooldown_time, 0.0, 1.0)

func get_individual_bar_progress(bar_index: int) -> float:
	if special_charges > bar_index: return 1.0
	elif special_charges == bar_index: return clampf(special_charge_timer / 1.8, 0.0, 1.0)
	return 0.0
