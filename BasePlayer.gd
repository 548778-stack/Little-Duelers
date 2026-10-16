extends CharacterBody2D
class_name BasePlayer # 🚀 This allows other scripts to inherit from it!

# --- YOUR PRESERVED VARIABLES ---
@export var speed: float = 500.0
const SPEED = 300.0
@onready var color_rect = $ColorRect
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

# Cooldown Clocks
var local_ability_timer: float = 5.0
var special_charge_timer: float = 0.0

func _enter_tree() -> void:
	# If we are online, automatically convert our Peer ID name string back into an integer
	# and lock the machine's hardware authority right at birth!
	if multiplayer.multiplayer_peer != null and name.is_valid_int():
		set_multiplayer_authority(name.to_int())
		print("⚡ Node ", name, " early authority locked to peer ID: ", name.to_int())

func _ready() -> void:
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	# FIXED: Determine player_id and colors cleanly by checking server status!
	if multiplayer.multiplayer_peer != null:
		if is_multiplayer_authority():
			player_id = 1 if multiplayer.is_server() else 2
		else:
			player_id = 2 if multiplayer.is_server() else 1
	else:
		# Offline mode fallback
		player_id = 1 if name == "Player1" else 2

	# Tint colors perfectly without hardcoded name matching
	if has_node("ColorRect"):
		if multiplayer.multiplayer_peer != null:
			# If the node's owner is the Server, paint it Blue. If it's the Client guest, paint it Red!
			if is_multiplayer_authority() == multiplayer.is_server():
				$ColorRect.color = Color(0.2, 0.6, 1.0) # Host Blue
			else:
				$ColorRect.color = Color(1.0, 0.3, 0.3) # Guest Red
		else:
			$ColorRect.color = Color(0.2, 0.6, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.3)

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	time_since_last_normal += delta
	local_ability_timer += delta
	
	# Special Charge Recharging
	if special_charges < 3:
		special_charge_timer += delta
		if special_charge_timer >= 1.8:
			special_charges += 1
			special_charge_timer = 0.0
			
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	
	# FIXED: Clamp screen quadrants based on server/client status rather than text names!
	var view_size = get_viewport_rect().size
	var mid_x = view_size.x / 2.0
	position.y = clampf(position.y, 40.0, view_size.y - 40.0)
	
	if multiplayer.multiplayer_peer != null:
		# If this instance is owned by the server machine, lock it left. Otherwise, lock it right!
		if is_multiplayer_authority() == multiplayer.is_server():
			position.x = clampf(position.x, 40.0, mid_x - 30.0)
		else:
			position.x = clampf(position.x, mid_x + 30.0, view_size.x - 40.0)

func _input(event: InputEvent) -> void:
	if multiplayer.multiplayer_peer != null and not is_multiplayer_authority():
		return
		
	var arena = get_parent()
	if not is_instance_valid(arena): return
	
	var target_mouse_pos = get_global_mouse_position()
	var fire_direction = global_position.direction_to(target_mouse_pos)

	if event.is_action_pressed("attack_normal"):
		if is_reloading: return
		if character_class == "Cowboy" and current_ammo <= 0:
			if arena.has_method("start_reload"): arena.start_reload()
			return
			
		if time_since_last_normal >= normal_cooldown_time:
			# ROUTE VIA SERVER RPC: Send spawn instructions to the master server pipeline [0.1]
			rpc_id(1, "request_server_bullet_spawn", "normal", global_position, fire_direction, player_id, character_class)
			time_since_last_normal = 0.0

	elif event.is_action_pressed("attack_special"):
		if special_charges > 0:
			rpc_id(1, "request_server_bullet_spawn", "special", global_position, fire_direction, player_id, character_class)
			special_charges -= 1

	elif event.is_action_pressed("attack_ability"):
		var active_skill = arena.p1_selected_skill if player_id == 1 else arena.p2_selected_skill
		if local_ability_timer < arena.active_ability_cooldown_time: return
		
		# Map your skills out cleanly
		if active_skill == "Recons Eye":
			for i in range(-1, 2):
				var spread_angle = i * 0.18
				var rotated_dir = fire_direction.rotated(spread_angle)
				rpc_id(1, "request_server_bullet_spawn", "tracking_normal", global_position, rotated_dir, player_id, character_class)
		else:
			var bullet_type = "bouncing_normal"
			if active_skill == "Piercing Shot": bullet_type = "piercing_special"
			elif active_skill == "Marksman": bullet_type = "marksman_normal"
			rpc_id(1, "request_server_bullet_spawn", bullet_type, global_position, fire_direction, player_id, character_class)
			
		local_ability_timer = 0.0

# --- THE MASTER SERVER PROJECTILE HOOK ---
@rpc("any_peer", "call_local", "reliable")
func request_server_bullet_spawn(type: String, start_pos: Vector2, fire_dir: Vector2, owner_id: int, owner_class: String) -> void:
	# Only the Server computes and instantiates physics nodes globally [0.1]!
	if multiplayer.is_server() or multiplayer.multiplayer_peer == null:
		var arena = get_parent()
		var bullet = Area2D.new()
		bullet.set_script(preload("res://Projectile.gd"))
		bullet.attacker_id = owner_id
		bullet.damage_type = type
		
		# Set damage values securely on the server side
		var base_damage = 1.4 if owner_class == "Cowboy" and type == "normal" else 1.0
		if type == "special": base_damage = 2.0
		elif type == "marksman_normal": base_damage = 2.8
		
		bullet.set_meta("damage_amount", base_damage)
		bullet.set_meta("is_critical", (type == "marksman_normal"))
		
		arena.add_child(bullet) # Spawner replicates this down to the guest instantly!
		bullet.global_position = start_pos + (fire_dir * 45.0)
		
		if bullet.has_method("set_vector_trajectory"):
			bullet.set_vector_trajectory(fire_dir)

# --- SHARED HUD INTERFACE HELPERS ---
func get_ammo_string() -> String:
	var arena = get_parent()
	if not is_instance_valid(arena): return ""
	if character_class != "Cowboy": return ""
	if is_reloading: return " [RELOADING...]"
	var bars = ""
	for i in range(current_ammo): bars += "|"
	return " [AMMO: " + bars + " " + str(current_ammo) + "/" + str(max_ammo) + "]"

func get_ability_status_string() -> String:
	var arena = get_parent()
	if not is_instance_valid(arena): return ""
	if local_ability_timer >= arena.active_ability_cooldown_time: return " [SKILL READY]"
	return " [SKILL COOLDOWN]"

func get_ability_cooldown_percentage() -> float:
	var arena = get_parent()
	if not is_instance_valid(arena): return 1.0
	return clampf(local_ability_timer / arena.active_ability_cooldown_time, 0.0, 1.0)

func get_individual_bar_progress(bar_index: int) -> float:
	if special_charges > bar_index: return 1.0
	elif special_charges == bar_index: return clampf(special_charge_timer / 1.8, 0.0, 1.0)
	return 0.0

# Append these functions to the very bottom of your BasePlayer.gd file

func take_damage(amount: float, is_special_hit: bool, is_crit_hit: bool = false) -> void:
	if lives <= 0: return
	
	var final_damage = amount
	
	# Apply Recon class passive vulnerability flaw if hit by a heavy skill
	if character_class == "Recon" and is_special_hit:
		final_damage += 1.0
		print("💥 Critical Vulnerability hit! Recon took extra damage!")
		
	# Trigger the floating visual hit marker on successful critical hits
	if is_crit_hit:
		print("🎯 CRITICAL HIT REGISTERED! 2x Damage applied!")
		if get_parent().has_method("spawn_crit_hit_marker"):
			get_parent().spawn_crit_hit_marker(global_position)
	
	current_health -= final_damage
	
	# Trigger particle bursts (Gold for crits, matching theme color for normal hits)
	var particle_color = Color(1.0, 0.85, 0.2) if is_crit_hit else (Color(0.2, 0.6, 1.0) if player_id == 1 else Color(1.0, 0.3, 0.3))
	if get_parent().has_method("spawn_hit_particles"):
		get_parent().spawn_hit_particles(global_position, particle_color)
	
	# Check if current health pool is completely depleted
	if current_health <= 0.0:
		lose_life()

func lose_life() -> void:
	lives -= 1
	current_health = max_health 
	
	# Reload weapon systems instantly on respawn
	if character_class == "Cowboy": 
		current_ammo = max_ammo
		
	# Trigger game over loop if completely out of stock lives
	if lives <= 0:
		set_physics_process(false)
		set_process_unhandled_input(false)
		if get_parent().has_method("trigger_game_over"):
			get_parent().trigger_game_over(player_id)
