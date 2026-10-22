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
	# Each player node is named after the peer that controls it ("1" = host, guest = its peer ID).
	if NetworkManager.is_online() and name.is_valid_int():
		set_multiplayer_authority(name.to_int())

# Should THIS machine read the keyboard/mouse for this player?
func _is_locally_controlled() -> bool:
	if NetworkManager.is_online():
		return is_multiplayer_authority()
	return name == "1"  # offline: the keyboard drives player 1 only

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
	if not _is_locally_controlled(): return
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
	if not _is_locally_controlled(): return
	var target_mouse_pos = get_global_mouse_position()
	var fire_direction = global_position.direction_to(target_mouse_pos)

	if event.is_action_pressed("attack_normal"):
		if is_reloading or (character_class == "Cowboy" and current_ammo <= 0): return
		if time_since_last_normal >= normal_cooldown_time:
			# Ask the HOST (peer 1) to create the bullet. call_local lets the host shoot too.
			request_server_bullet_spawn.rpc_id(1, "normal", global_position, fire_direction)
			time_since_last_normal = 0.0
			if character_class == "Cowboy": current_ammo -= 1

@rpc("any_peer", "call_local", "reliable")
func request_server_bullet_spawn(type: String, start_pos: Vector2, fire_dir: Vector2) -> void:
	if not multiplayer.is_server(): return
	# Only the player who owns this node may fire its bullets.
	if NetworkManager.is_online() and multiplayer.get_remote_sender_id() != get_multiplayer_authority(): return
	var arena = get_parent()
	if arena.has_method("spawn_projectile"):
		arena.spawn_projectile(type, start_pos + (fire_dir * 45.0), fire_dir, player_id)

func get_ammo_string() -> String:
	if character_class != "Cowboy": return ""
	var bars = ""
	for i in range(current_ammo): bars += "|"
	return " [AMMO: " + bars + "]"

func get_ability_status_string() -> String:
	return " [READY]" if local_ability_timer >= 5.0 else " [CD]"

# Damage is decided ONLY on the host, then the result is sent to everyone.
func take_damage(amount: float, is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if not multiplayer.is_server(): return
	if lives <= 0: return
	var final_damage = amount
	if character_class == "Recon" and is_special_hit: final_damage += 1.0

	var new_health = current_health - final_damage
	var new_lives = lives
	if new_health <= 0.0:
		new_lives -= 1
		new_health = max_health
	_apply_damage_result.rpc(new_health, new_lives, is_crit_hit)

@rpc("any_peer", "call_local", "reliable")
func _apply_damage_result(new_health: float, new_lives: int, is_crit_hit: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1: return  # only the host decides damage
	var lost_life = new_lives < lives
	current_health = new_health
	lives = new_lives

	var arena = get_parent()
	if is_crit_hit: arena.spawn_crit_hit_marker(global_position)
	var particle_color = Color(1.0, 0.85, 0.2) if is_crit_hit else (Color(0.2, 0.6, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.3))
	arena.spawn_hit_particles(global_position, particle_color)

	if lost_life:
		if character_class == "Cowboy": current_ammo = max_ammo
		if lives <= 0:
			set_physics_process(false)
			arena.trigger_game_over(player_id)

func lose_life() -> void:
	# Kept for compatibility; routes through the synced damage path.
	if multiplayer.is_server() and lives > 0:
		_apply_damage_result.rpc(max_health, lives - 1, false)

func get_ability_cooldown_percentage() -> float:
	var arena = get_parent()
	if not is_instance_valid(arena): return 1.0
	return clampf(local_ability_timer / arena.active_ability_cooldown_time, 0.0, 1.0)

func get_individual_bar_progress(bar_index: int) -> float:
	if special_charges > bar_index: return 1.0
	elif special_charges == bar_index: return clampf(special_charge_timer / 1.8, 0.0, 1.0)
	return 0.0
