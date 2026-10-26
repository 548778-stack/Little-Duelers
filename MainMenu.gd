extends Control

@onready var ip_input = find_child("IPInput", true, false) as LineEdit
@onready var ip_label = find_child("IPLabel", true, false) as Label
@onready var host_button = find_child("HostButton", true, false) as Button
@onready var join_button = find_child("JoinButton", true, false) as Button

var my_ip: String = "127.0.0.1"

func _ready() -> void:
	my_ip = NetworkManager.get_my_local_ip()
	if ip_label:
		ip_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		if NetworkManager.last_status_message != "":
			_set_status(NetworkManager.last_status_message)
			NetworkManager.last_status_message = ""
		else:
			_set_status("YOUR MATCH IP: " + my_ip)

func _set_status(text: String) -> void:
	if ip_label: ip_label.text = text

func _on_host_button_pressed() -> void:
	if NetworkManager.host_game() != OK:
		_set_status(NetworkManager.last_status_message)
		return
	_set_status("HOSTING on " + my_ip + " - waiting for opponent...")
	if host_button: host_button.disabled = true
	if join_button: join_button.disabled = true

func _on_join_button_pressed() -> void:
	var target_ip = ip_input.text.strip_edges() if ip_input else "127.0.0.1"
	if target_ip == "": target_ip = "127.0.0.1"
	if NetworkManager.join_game(target_ip) != OK:
		_set_status(NetworkManager.last_status_message)
		return
	_set_status("Connecting to " + target_ip + "...")
	if host_button: host_button.disabled = true
	if join_button: join_button.disabled = true

func _on_offline_button_pressed() -> void:
	NetworkManager.close_connection()
	NetworkManager.vs_ai = true  # offline = you vs the EnemyAI bot
	get_tree().change_scene_to_file("res://Lobby.tscn")
