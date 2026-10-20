extends Node

# --- NETWORKING CONFIGURATION ---
const PORT: int = 8080
const LOCALHOST: String = "127.0.0.1"

var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()

# --- 3D & UI NODES ---
var world_root: Node3D = null
var menu_canvas: CanvasLayer = null
var players_container: Node3D = null
var spawner: MultiplayerSpawner = null

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_build_main_menu()

# ==============================================================================
# MAIN MENU UI
# ==============================================================================

func _build_main_menu() -> void:
	menu_canvas = CanvasLayer.new()
	add_child(menu_canvas)

	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_CENTER)
	menu_canvas.add_child(container)

	var join_btn = Button.new()
	join_btn.text = "Join Online Game"
	join_btn.custom_minimum_size = Vector2(240, 50)
	join_btn.pressed.connect(_on_join_online_pressed)
	container.add_child(join_btn)

	var quit_btn = Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(240, 50)
	quit_btn.pressed.connect(func(): get_tree().quit())
	container.add_child(quit_btn)

func _on_join_online_pressed() -> void:
	if menu_canvas:
		menu_canvas.queue_free()
		menu_canvas = null

	_build_3d_environment()
	_auto_connect_or_host()

# ==============================================================================
# AUTOMATIC CONNECT OR HOST
# ==============================================================================

func _auto_connect_or_host() -> void:
	print("[Network] Attempting to connect to existing local session...")
	multiplayer.multiplayer_peer = null
	peer = WebSocketMultiplayerPeer.new()

	var err = peer.create_client("ws://" + LOCALHOST + ":" + str(PORT))
	if err == OK:
		multiplayer.multiplayer_peer = peer
		get_tree().create_timer(0.2).timeout.connect(_check_connection_timeout)
	else:
		_start_hosting()

func _check_connection_timeout() -> void:
	if peer and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print("[Network] No active host found. Becoming the Host...")
		_start_hosting()

func _start_hosting() -> void:
	multiplayer.multiplayer_peer = null
	peer = WebSocketMultiplayerPeer.new()

	var err = peer.create_server(PORT)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		print("[Host] Server created successfully on port ", PORT)
		_spawn_player(1)
	else:
		print("[Host] Error starting server: ", err)

# ==============================================================================
# MULTIPLAYER CALLBACKS
# ==============================================================================

func _on_connected_to_server() -> void:
	print("[Client] Connected to server! Assigned Peer ID: ", multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	print("[Client] Connection failed. Switching to Host...")
	_start_hosting()

func _on_peer_connected(id: int) -> void:
	print("[Network] Peer connected: ", id)
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	print("[Network] Peer disconnected: ", id)
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
	spawner.spawn_function = _custom_spawn_player
	world_root.add_child(spawner)
	spawner.spawn_path = players_container.get_path()

func _spawn_player(peer_id: int) -> void:
	if spawner:
		spawner.spawn(peer_id)

func _custom_spawn_player(peer_id: Variant) -> Node:
	var id = int(peer_id)
	var player = NetworkPlayer.new(id)
	player.name = str(id)
	return player

# ==============================================================================
# PLAYER CHARACTER CLASS
# ==============================================================================

class NetworkPlayer extends CharacterBody3D:
	var peer_id: int
	var camera: Camera3D
	var mouse_sensitivity: float = 0.003
	var speed: float = 8.0

	func _init(id: int = 1) -> void:
		peer_id = id

	func _ready() -> void:
		# Set authority on both the Player character AND the Synchronizer
		set_multiplayer_authority(peer_id)

		var sync = MultiplayerSynchronizer.new()
		sync.name = "Sync"
		sync.set_multiplayer_authority(peer_id)
		
		var config = SceneReplicationConfig.new()
		config.add_property(NodePath(":position"))
		config.add_property(NodePath(":rotation"))
		sync.replication_config = config
		add_child(sync)

		# Visual Capsule Mesh
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

		# Collision Shape
		var col = CollisionShape3D.new()
		var cap_shape = CapsuleShape3D.new()
		cap_shape.height = 1.8
		cap_shape.radius = 0.4
		col.shape = cap_shape
		col.position.y = 0.9
		add_child(col)

		# Setup camera only if this client owns this player
		if is_multiplayer_authority():
			camera = Camera3D.new()
			camera.position = Vector3(0, 1.5, 0)
			add_child(camera)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	func _unhandled_input(event: InputEvent) -> void:
		if not is_multiplayer_authority():
			return

		if Input.is_action_just_pressed("ui_cancel"):
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * mouse_sensitivity)
			if camera:
				camera.rotate_x(-event.relative.y * mouse_sensitivity)
				camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	func _physics_process(delta: float) -> void:
		if not is_multiplayer_authority():
			return

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		var input_dir := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): input_dir.z -= 1
		if Input.is_key_pressed(KEY_S): input_dir.z += 1
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_key_pressed(KEY_D): input_dir.x += 1

		var direction = (transform.basis * input_dir).normalized()
		if direction != Vector3.ZERO:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)

		if not is_on_floor():
			velocity.y -= 20.0 * delta

		move_and_slide()
