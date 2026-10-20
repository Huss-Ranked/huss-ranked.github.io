extends Node

# --- NETWORKING CONFIGURATION ---
const PORT: int = 8080
const LOCALHOST: String = "127.0.0.1"

var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()

# --- LOCAL SAVE & LEADERBOARD DATA ---
const JUMP_SAVE_PATH: String = "user://player_data.json"
const LEADERBOARD_CACHE_PATH: String = "user://leaderboard_cache.json"

var local_jump_count: int = 0
var local_nickname: String = "Player"
var player_nicknames: Dictionary = {}
var leaderboard_data: Dictionary = {}

# --- 3D & UI NODES ---
var world_root: Node3D = null
var menu_canvas: CanvasLayer = null
var leaderboard_canvas: CanvasLayer = null
var hud_canvas: CanvasLayer = null
var console_list: VBoxContainer = null
var players_container: Node3D = null
var spawner: MultiplayerSpawner = null

var nickname_input: LineEdit = null
var pending_error_message: String = ""

func _ready() -> void:
	_load_jump_data()
	_load_leaderboard_cache()

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_build_main_menu()

func _unhandled_input(_event: InputEvent) -> void:
	if world_root and Input.is_action_just_pressed("ui_cancel"):
		_return_to_main_menu()

# ==============================================================================
# SAVE / LOAD & LEADERBOARD PERSISTENCE
# ==============================================================================

func _load_jump_data() -> void:
	if FileAccess.file_exists(JUMP_SAVE_PATH):
		var file = FileAccess.open(JUMP_SAVE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				local_jump_count = json.data.get("jump_count", 0)
				local_nickname = json.data.get("nickname", "Player")
			file.close()

func save_jump_data() -> void:
	var file = FileAccess.open(JUMP_SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"jump_count": local_jump_count,
			"nickname": local_nickname
		}
		file.store_string(JSON.stringify(data))
		file.close()

func _load_leaderboard_cache() -> void:
	if FileAccess.file_exists(LEADERBOARD_CACHE_PATH):
		var file = FileAccess.open(LEADERBOARD_CACHE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var raw_data = json.data
				if raw_data is Dictionary:
					for k in raw_data:
						leaderboard_data[int(k) if k.is_valid_int() else k] = raw_data[k]
			file.close()

func _save_leaderboard_cache() -> void:
	var file = FileAccess.open(LEADERBOARD_CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(leaderboard_data))
		file.close()

func clear_leaderboard_data() -> void:
	leaderboard_data.clear()
	
	# Delete the cache file if it exists
	if FileAccess.file_exists(LEADERBOARD_CACHE_PATH):
		DirAccess.remove_absolute(LEADERBOARD_CACHE_PATH)
		
	# Broadcast cleared state if hosting
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		sync_game_state.rpc(player_nicknames, leaderboard_data)

# ==============================================================================
# IN-GAME NETWORK CONSOLE LOGGING
# ==============================================================================

func log_console(message: String) -> void:
	print(message)
	if console_list:
		var lbl = Label.new()
		lbl.text = message
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
		console_list.add_child(lbl)
		
		if console_list.get_child_count() > 30:
			console_list.get_child(0).queue_free()

func _build_hud_console() -> void:
	hud_canvas = CanvasLayer.new()
	add_child(hud_canvas)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 160)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(10, -170)
	hud_canvas.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 150)
	panel.add_child(scroll)

	console_list = VBoxContainer.new()
	scroll.add_child(console_list)

	log_console("[System] Network Console initialized.")

# ==============================================================================
# MAIN MENU & LEADERBOARD UI
# ==============================================================================

func _build_main_menu() -> void:
	_clear_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	menu_canvas = CanvasLayer.new()
	add_child(menu_canvas)

	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_CENTER)
	menu_canvas.add_child(container)

	# Error Banner Display
	if pending_error_message != "":
		var err_panel = PanelContainer.new()
		var err_lbl = Label.new()
		err_lbl.text = pending_error_message
		err_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err_lbl.add_theme_color_override("font_color", Color(1, 0.35, 0.35))
		err_panel.add_child(err_lbl)
		container.add_child(err_panel)
		
		var err_spacer = Control.new()
		err_spacer.custom_minimum_size = Vector2(0, 10)
		container.add_child(err_spacer)
		
		pending_error_message = ""

	var nick_label = Label.new()
	nick_label.text = "Enter Nickname:"
	nick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(nick_label)

	nickname_input = LineEdit.new()
	nickname_input.text = local_nickname
	nickname_input.placeholder_text = "Player Name"
	nickname_input.custom_minimum_size = Vector2(240, 35)
	nickname_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(nickname_input)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer)

	var join_btn = Button.new()
	join_btn.text = "Start / Join Game"
	join_btn.custom_minimum_size = Vector2(240, 45)
	join_btn.pressed.connect(_on_join_online_pressed)
	container.add_child(join_btn)

	var leaderboard_btn = Button.new()
	leaderboard_btn.text = "Leaderboard"
	leaderboard_btn.custom_minimum_size = Vector2(240, 45)
	leaderboard_btn.pressed.connect(_show_leaderboard_ui)
	container.add_child(leaderboard_btn)

	var clear_btn = Button.new()
	clear_btn.text = "Clear Leaderboard"
	clear_btn.custom_minimum_size = Vector2(240, 45)
	clear_btn.pressed.connect(_on_clear_leaderboard_pressed)
	container.add_child(clear_btn)

	var quit_btn = Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(240, 45)
	quit_btn.pressed.connect(func(): get_tree().quit())
	container.add_child(quit_btn)

func _on_clear_leaderboard_pressed() -> void:
	clear_leaderboard_data()
	pending_error_message = "Leaderboard data successfully cleared!"
	_build_main_menu()

func _show_leaderboard_ui() -> void:
	_clear_ui()

	leaderboard_canvas = CanvasLayer.new()
	add_child(leaderboard_canvas)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(320, 300)
	leaderboard_canvas.add_child(panel)

	var container = VBoxContainer.new()
	panel.add_child(container)

	var title = Label.new()
	title.text = "--- JUMP LEADERBOARD ---"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 200)
	container.add_child(scroll)

	var list = VBoxContainer.new()
	scroll.add_child(list)

	var display_data = leaderboard_data.duplicate()
	if display_data.is_empty():
		display_data[local_nickname] = local_jump_count

	for player_key in display_data:
		var label = Label.new()
		label.text = str(player_key) + ": " + str(display_data[player_key]) + " Jumps"
		list.add_child(label)

	var back_btn = Button.new()
	back_btn.text = "Back to Menu"
	back_btn.pressed.connect(_build_main_menu)
	container.add_child(back_btn)

func _clear_ui() -> void:
	if menu_canvas:
		menu_canvas.queue_free()
		menu_canvas = null
	if leaderboard_canvas:
		leaderboard_canvas.queue_free()
		leaderboard_canvas = null
	if hud_canvas:
		hud_canvas.queue_free()
		hud_canvas = null
		console_list = null

func _on_join_online_pressed() -> void:
	if nickname_input and nickname_input.text.strip_edges() != "":
		local_nickname = nickname_input.text.strip_edges()
		save_jump_data()

	_clear_ui()
	_build_3d_environment()
	_build_hud_console()
	_auto_connect_or_host()

func _return_to_main_menu(error_msg: String = "") -> void:
	pending_error_message = error_msg
	_cleanup_network()
	if world_root:
		world_root.queue_free()
		world_root = null
	_build_main_menu()

func _cleanup_network() -> void:
	multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
		peer = WebSocketMultiplayerPeer.new()

# ==============================================================================
# NETWORKING & CONNECTIVITY
# ==============================================================================

func _auto_connect_or_host() -> void:
	_cleanup_network()
	log_console("[Network] Probing for host on " + LOCALHOST + ":" + str(PORT) + "...")

	var err = peer.create_client("ws://" + LOCALHOST + ":" + str(PORT))
	if err == OK:
		multiplayer.multiplayer_peer = peer
		get_tree().create_timer(0.3).timeout.connect(_check_connection_timeout)
	else:
		_start_hosting()

func _check_connection_timeout() -> void:
	if peer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		log_console("[Network] No active host found. Initializing server...")
		_start_hosting()

func _start_hosting() -> void:
	_cleanup_network()

	var err = peer.create_server(PORT)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		log_console("[Host] Server online on port " + str(PORT))
		_spawn_player(1)
		register_player_info(1, local_nickname, local_jump_count)
	else:
		log_console("[Host] ERROR starting server: Code " + str(err))

# --- NETWORK RPC SYNC ---

@rpc("any_peer", "call_local", "reliable")
func register_player_info(peer_id: int, nickname: String, jumps: int) -> void:
	player_nicknames[peer_id] = nickname
	leaderboard_data[nickname] = jumps
	_save_leaderboard_cache()

	if players_container and players_container.has_node(str(peer_id)):
		var p_node = players_container.get_node(str(peer_id))
		if p_node.has_method("set_nickname_label"):
			p_node.set_nickname_label(nickname)

	if multiplayer.is_server():
		sync_game_state.rpc(player_nicknames, leaderboard_data)

@rpc("authority", "call_local", "reliable")
func sync_game_state(nicknames: Dictionary, leaderboard: Dictionary) -> void:
	player_nicknames = nicknames
	leaderboard_data = leaderboard
	_save_leaderboard_cache()

	if players_container:
		for id in player_nicknames:
			if players_container.has_node(str(id)):
				var p_node = players_container.get_node(str(id))
				if p_node.has_method("set_nickname_label"):
					p_node.set_nickname_label(player_nicknames[id])

# --- NETWORK CALLBACKS ---

func _on_connected_to_server() -> void:
	var my_id = multiplayer.get_unique_id()
	log_console("[Client] Connected to host! Assigned Peer ID: " + str(my_id))
	register_player_info.rpc_id(1, my_id, local_nickname, local_jump_count)

func _on_connection_failed() -> void:
	log_console("[Client] Connection failed. Switching to Host...")
	_start_hosting()

func _on_server_disconnected() -> void:
	log_console("[Client] Disconnected: Host left the game.")
	_return_to_main_menu("Error: The host left the game. Start another game to reconnect")

func _on_peer_connected(id: int) -> void:
	log_console("[Network] Peer connected: ID " + str(id))
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	log_console("[Network] Peer disconnected: ID " + str(id))
	if players_container and players_container.has_node(str(id)):
		players_container.get_node(str(id)).queue_free()

# ==============================================================================
# 3D WORLD & SPAWNING
# ==============================================================================

func _build_3d_environment() -> void:
	world_root = Node3D.new()
	world_root.name = "3DWorld"
	add_child(world_root)

	var light = DirectionalLight3D.new()
	light.position = Vector3(0, 10, 0)
	light.rotation_degrees = Vector3(-45, 45, 0)
	world_root.add_child(light)

	var floor_body = StaticBody3D.new()
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(50, 50)
	floor_mesh.mesh = plane

	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(50, 0.1, 50)
	floor_shape.shape = box

	floor_body.add_child(floor_mesh)
	floor_body.add_child(floor_shape)
	world_root.add_child(floor_body)

	players_container = Node3D.new()
	players_container.name = "Players"
	world_root.add_child(players_container)

	spawner = MultiplayerSpawner.new()
	spawner.name = "MultiplayerSpawner"
	spawner.spawn_function = _custom_spawn_player
	world_root.add_child(spawner)
	spawner.spawn_path = players_container.get_path()

func _spawn_player(peer_id: int) -> void:
	if spawner:
		spawner.spawn(peer_id)

func _custom_spawn_player(peer_id: Variant) -> Node:
	var id = int(peer_id)
	var player = NetworkPlayer.new(id, self)
	player.name = str(id)
	return player

# ==============================================================================
# PLAYER CHARACTER CLASS
# ==============================================================================

class NetworkPlayer extends CharacterBody3D:
	var peer_id: int
	var main_manager: Node
	var camera: Camera3D
	var name_label: Label3D
	
	var mouse_sensitivity: float = 0.003
	var walk_speed: float = 8.0
	var sprint_speed: float = 14.0
	var jump_velocity: float = 7.0

	func _init(id: int = 1, manager: Node = null) -> void:
		peer_id = id
		main_manager = manager

	func _ready() -> void:
		set_multiplayer_authority(peer_id)

		var sync = MultiplayerSynchronizer.new()
		sync.name = "Sync"
		sync.set_multiplayer_authority(peer_id)
		
		var config = SceneReplicationConfig.new()
		config.add_property(NodePath(":position"))
		config.add_property(NodePath(":rotation"))
		sync.replication_config = config
		add_child(sync)

		var mesh_inst = MeshInstance3D.new()
		var cap = CapsuleMesh.new()
		cap.height = 1.8
		cap.radius = 0.4
		mesh_inst.mesh = cap
		mesh_inst.position.y = 0.9

		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(randf(), randf(), randf())
		mesh_inst.material_override = mat
		add_child(mesh_inst)

		var col = CollisionShape3D.new()
		var cap_shape = CapsuleShape3D.new()
		cap_shape.height = 1.8
		cap_shape.radius = 0.4
		col.shape = cap_shape
		col.position.y = 0.9
		add_child(col)

		name_label = Label3D.new()
		name_label.position = Vector3(0, 2.2, 0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.font_size = 24
		name_label.outline_size = 6
		name_label.text = main_manager.player_nicknames.get(peer_id, "Player " + str(peer_id)) if main_manager else "Player"
		add_child(name_label)

		if is_multiplayer_authority():
			camera = Camera3D.new()
			camera.position = Vector3(0, 1.5, 0)
			add_child(camera)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func set_nickname_label(nickname: String) -> void:
		if name_label:
			name_label.text = nickname

	func _unhandled_input(event: InputEvent) -> void:
		if not is_multiplayer_authority():
			return

		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * mouse_sensitivity)
			if camera:
				camera.rotate_x(-event.relative.y * mouse_sensitivity)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	func _physics_process(delta: float) -> void:
		if not is_multiplayer_authority():
			return

		if Input.is_key_pressed(KEY_TAB):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		if not is_on_floor():
			velocity.y -= 20.0 * delta

		if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = jump_velocity
			
			if main_manager:
				main_manager.local_jump_count += 1
				main_manager.save_jump_data()
				main_manager.register_player_info.rpc(peer_id, main_manager.local_nickname, main_manager.local_jump_count)

		var current_speed = sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed

		var input_dir := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S): input_dir.z += 1
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D): input_dir.x += 1

		var direction = (transform.basis * input_dir).normalized()
		if direction != Vector3.ZERO:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)

		move_and_slide()
