extends Node3D

const WS_URL: String = "ws://localhost:8000/ws"

# 3D Node references
@onready var camera: Camera3D = %Camera3D
@onready var edges_container: Node3D = %EdgesContainer
@onready var nodes_container: Node3D = %NodesContainer
@onready var trace_container: Node3D = %TraceContainer
@onready var packet_orb: MeshInstance3D = %PacketOrb
@onready var selection_ring: MeshInstance3D = %SelectionRing

# UI references
@onready var ws_status_label: Label = %WsStatus
@onready var scenario_badge: Label = %ScenarioBadge
@onready var status_label: Label = %StatusLabel
@onready var src_select: OptionButton = %SrcSelect
@onready var dst_select: OptionButton = %DstSelect
@onready var trace_button: Button = %TraceButton
@onready var reset_cam_btn: Button = %ResetCamBtn
@onready var config_toggle_btn: Button = %ConfigToggleBtn

# Scenario Presets buttons
@onready var btn_healthy: Button = %BtnHealthy
@onready var btn_failover: Button = %BtnFailover
@onready var btn_severed: Button = %BtnSevered
@onready var btn_acl: Button = %BtnACL

# Fault injection / link toggle buttons
@onready var btn_cut_dist1_core: Button = %BtnCutDist1Core
@onready var btn_cut_dist1_edge1: Button = %BtnCutDist1Edge1
@onready var btn_cut_dist2_edge1: Button = %BtnCutDist2Edge1
@onready var btn_restore_all: Button = %BtnRestoreAll

# Device Details Panel references
@onready var device_details_panel: PanelContainer = %DeviceDetailsPanel
@onready var device_name_label: Label = %DeviceNameLabel
@onready var device_role_label: Label = %DeviceRoleLabel
@onready var device_status_label: Label = %DeviceStatusLabel
@onready var device_loopback_label: Label = %DeviceLoopbackLabel
@onready var device_ospf_label: Label = %DeviceOspfLabel
@onready var device_interfaces_list: VBoxContainer = %DeviceInterfacesList
@onready var close_device_btn: Button = %CloseDeviceBtn
@onready var btn_device_set_src: Button = %BtnDeviceSetSrc
@onready var btn_device_view_cfg: Button = %BtnDeviceViewCfg

# Config modal references
@onready var config_modal: PanelContainer = %ConfigModal
@onready var close_config_btn: Button = %CloseConfigBtn
@onready var config_router_select: OptionButton = %ConfigRouterSelect
@onready var config_text_edit: TextEdit = %ConfigTextEdit
@onready var save_config_btn: Button = %SaveConfigBtn

# Camera Orbit & Pan State
var cam_yaw: float = 0.0
var cam_pitch: float = -0.22
var cam_dist: float = 17.0
var cam_target: Vector3 = Vector3(0.0, 0.0, 0.0)
var is_orbiting: bool = false
var is_panning: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var mouse_down_pos: Vector2 = Vector2.ZERO

# WebSocket state
var socket: WebSocketPeer = WebSocketPeer.new()
var is_connected: bool = false
var reconnect_timer: float = 0.0

# Selected Device State
var selected_device_name: String = ""

# 3D Topology Coordinates
var node_positions_3d: Dictionary = {
	"core-r1": Vector3(-6.5, 2.5, 0.0),
	"core-r2": Vector3(-6.5, -2.5, 0.0),
	"dist-r1": Vector3(0.0, 2.5, 0.0),
	"dist-r2": Vector3(0.0, -2.5, 0.0),
	"edge-r1": Vector3(6.5, 2.5, 0.0),
	"edge-r2": Vector3(6.5, -2.5, 0.0)
}

# Detailed Device Metadata
var device_metadata: Dictionary = {
	"core-r1": {
		"role": "Core Layer Router (Primary)",
		"loopback": "10.0.0.1/32",
		"ospf": "Router-ID: 10.0.0.1 (Area 0)",
		"interfaces": [
			{"name": "GigabitEthernet0/0", "ip": "10.1.3.1/24", "peer": "dist-r1", "cost": 10, "edge": ["core-r1", "dist-r1"]},
			{"name": "GigabitEthernet0/1", "ip": "10.1.4.1/24", "peer": "dist-r2", "cost": 20, "edge": ["core-r1", "dist-r2"]},
			{"name": "GigabitEthernet0/2", "ip": "10.1.1.1/24", "peer": "core-r2", "cost": 10, "edge": ["core-r1", "core-r2"]}
		]
	},
	"core-r2": {
		"role": "Core Layer Router (Redundant)",
		"loopback": "10.0.0.2/32",
		"ospf": "Router-ID: 10.0.0.2 (Area 0)",
		"interfaces": [
			{"name": "GigabitEthernet0/0", "ip": "10.2.3.2/24", "peer": "dist-r1", "cost": 20, "edge": ["core-r2", "dist-r1"]},
			{"name": "GigabitEthernet0/1", "ip": "10.2.4.2/24", "peer": "dist-r2", "cost": 10, "edge": ["core-r2", "dist-r2"]},
			{"name": "GigabitEthernet0/2", "ip": "10.1.1.2/24", "peer": "core-r1", "cost": 10, "edge": ["core-r1", "core-r2"]}
		]
	},
	"dist-r1": {
		"role": "Distribution / Spine Switch (Primary)",
		"loopback": "10.0.0.3/32",
		"ospf": "Router-ID: 10.0.0.3 (Area 0)",
		"interfaces": [
			{"name": "GigabitEthernet0/0", "ip": "10.1.3.3/24", "peer": "core-r1 (Upstream)", "cost": 10, "edge": ["core-r1", "dist-r1"]},
			{"name": "GigabitEthernet0/1", "ip": "10.2.3.3/24", "peer": "core-r2 (Upstream)", "cost": 20, "edge": ["core-r2", "dist-r1"]},
			{"name": "GigabitEthernet0/2", "ip": "10.3.5.3/24", "peer": "edge-r1 (Downstream)", "cost": 10, "edge": ["dist-r1", "edge-r1"]},
			{"name": "GigabitEthernet0/3", "ip": "10.3.6.3/24", "peer": "edge-r2 (Downstream)", "cost": 10, "edge": ["dist-r1", "edge-r2"]}
		]
	},
	"dist-r2": {
		"role": "Distribution / Spine Switch (Backup)",
		"loopback": "10.0.0.4/32",
		"ospf": "Router-ID: 10.0.0.4 (Area 0)",
		"interfaces": [
			{"name": "GigabitEthernet0/0", "ip": "10.1.4.4/24", "peer": "core-r1 (Upstream)", "cost": 20, "edge": ["core-r1", "dist-r2"]},
			{"name": "GigabitEthernet0/1", "ip": "10.2.4.4/24", "peer": "core-r2 (Upstream)", "cost": 10, "edge": ["core-r2", "dist-r2"]},
			{"name": "GigabitEthernet0/2", "ip": "10.4.5.4/24", "peer": "edge-r1 (Downstream)", "cost": 10, "edge": ["dist-r2", "edge-r1"]},
			{"name": "GigabitEthernet0/3", "ip": "10.4.6.4/24", "peer": "edge-r2 (Downstream)", "cost": 10, "edge": ["dist-r2", "edge-r2"]}
		]
	},
	"edge-r1": {
		"role": "Edge / Access Router (Host Subnet A)",
		"loopback": "10.0.0.5/32",
		"ospf": "Router-ID: 10.0.0.5 (Area 0)",
		"interfaces": [
			{"name": "GigabitEthernet0/0", "ip": "10.3.5.5/24", "peer": "dist-r1", "cost": 10, "edge": ["dist-r1", "edge-r1"]},
			{"name": "GigabitEthernet0/1", "ip": "10.4.5.5/24", "peer": "dist-r2", "cost": 10, "edge": ["dist-r2", "edge-r1"]},
			{"name": "GigabitEthernet0/2", "ip": "192.168.10.1/24", "peer": "LAN Host (192.168.10.0/24)", "cost": 0, "edge": []}
		]
	},
	"edge-r2": {
		"role": "Edge / Access Router (Host Subnet B)",
		"loopback": "10.0.0.6/32",
		"ospf": "Router-ID: 10.0.0.6 (Area 0)",
		"interfaces": [
			{"name": "GigabitEthernet0/0", "ip": "10.3.6.6/24", "peer": "dist-r1", "cost": 10, "edge": ["dist-r1", "edge-r2"]},
			{"name": "GigabitEthernet0/1", "ip": "10.4.6.6/24", "peer": "dist-r2", "cost": 10, "edge": ["dist-r2", "edge-r2"]},
			{"name": "GigabitEthernet0/2", "ip": "192.168.20.1/24", "peer": "LAN Host (192.168.20.0/24)", "cost": 0, "edge": []}
		]
	}
}

# Topology State
var nodes: Array = []
var edges: Array = []
var active_edges: Array = []
var broken_edges: Array = []
var active_scenario: String = "healthy"

# Trace Animation State
var active_hops: Array = []
var active_status: String = ""
var flash_timer: float = 0.0
var pulse_time: float = 0.0

# Materials cache
var mat_active_link: StandardMaterial3D
var mat_broken_link: StandardMaterial3D
var mat_trace_link: StandardMaterial3D
var mat_router_body: StandardMaterial3D
var mat_router_active: StandardMaterial3D
var mat_packet_orb: StandardMaterial3D
var mat_selection_ring: StandardMaterial3D


func _ready() -> void:
	_init_materials()
	_init_packet_orb()
	_init_selection_ring()
	_update_camera_transform()

	# Dropdowns initialization
	src_select.clear()
	src_select.add_item("core-r1", 0)
	src_select.add_item("core-r2", 1)
	src_select.selected = 0

	dst_select.clear()
	dst_select.add_item("192.168.10.1 (edge-r1 Host A)", 0)
	dst_select.set_item_metadata(0, "192.168.10.1")
	dst_select.add_item("192.168.20.1 (edge-r2 Host B)", 1)
	dst_select.set_item_metadata(1, "192.168.20.1")
	dst_select.selected = 0

	config_router_select.clear()
	var router_list = ["core-r1", "core-r2", "dist-r1", "dist-r2", "edge-r1", "edge-r2"]
	for idx in range(router_list.size()):
		config_router_select.add_item(router_list[idx], idx)
	config_router_select.selected = 0

	# Connect Trace & Control Buttons
	trace_button.pressed.connect(_on_trace_button_pressed)
	reset_cam_btn.pressed.connect(_reset_camera_view)
	config_toggle_btn.pressed.connect(_toggle_config_modal)
	close_config_btn.pressed.connect(_toggle_config_modal)
	save_config_btn.pressed.connect(_on_save_config_pressed)
	config_router_select.item_selected.connect(_on_config_router_selected)

	# Connect Scenario Presets Buttons
	btn_healthy.pressed.connect(func(): _load_scenario("healthy"))
	btn_failover.pressed.connect(func(): _load_scenario("failover"))
	btn_severed.pressed.connect(func(): _load_scenario("severed"))
	btn_acl.pressed.connect(func(): _load_scenario("acl"))

	# Connect Fault Injection Buttons
	btn_cut_dist1_core.pressed.connect(func(): _break_link("core1_dist1"))
	btn_cut_dist1_edge1.pressed.connect(func(): _break_link("dist1_edge1"))
	btn_cut_dist2_edge1.pressed.connect(func(): _break_link("dist2_edge1"))
	btn_restore_all.pressed.connect(func(): _break_link("restore_all"))

	# Connect Device Details Buttons
	close_device_btn.pressed.connect(_deselect_device)
	btn_device_set_src.pressed.connect(_on_device_set_as_src_pressed)
	btn_device_view_cfg.pressed.connect(_on_device_view_config_pressed)

	_connect_websocket()


func _init_materials() -> void:
	mat_active_link = StandardMaterial3D.new()
	mat_active_link.albedo_color = Color(0.18, 0.42, 0.72, 0.85)
	mat_active_link.emission_enabled = true
	mat_active_link.emission = Color(0.2, 0.48, 0.8)
	mat_active_link.emission_energy_multiplier = 0.8

	mat_broken_link = StandardMaterial3D.new()
	mat_broken_link.albedo_color = Color(0.95, 0.2, 0.2, 0.95)
	mat_broken_link.emission_enabled = true
	mat_broken_link.emission = Color(0.95, 0.15, 0.15)
	mat_broken_link.emission_energy_multiplier = 2.5

	mat_trace_link = StandardMaterial3D.new()
	mat_trace_link.albedo_color = Color(0.2, 0.95, 0.45)
	mat_trace_link.emission_enabled = true
	mat_trace_link.emission = Color(0.2, 0.95, 0.45)
	mat_trace_link.emission_energy_multiplier = 2.8

	mat_router_body = StandardMaterial3D.new()
	mat_router_body.albedo_color = Color(0.1, 0.15, 0.25)
	mat_router_body.metallic = 0.8
	mat_router_body.roughness = 0.25

	mat_router_active = StandardMaterial3D.new()
	mat_router_active.albedo_color = Color(0.2, 0.95, 0.45)
	mat_router_active.emission_enabled = true
	mat_router_active.emission = Color(0.2, 0.95, 0.45)
	mat_router_active.emission_energy_multiplier = 2.0

	mat_packet_orb = StandardMaterial3D.new()
	mat_packet_orb.albedo_color = Color.WHITE
	mat_packet_orb.emission_enabled = true
	mat_packet_orb.emission = Color.WHITE
	mat_packet_orb.emission_energy_multiplier = 4.0

	mat_selection_ring = StandardMaterial3D.new()
	mat_selection_ring.albedo_color = Color(1.0, 0.85, 0.25)
	mat_selection_ring.emission_enabled = true
	mat_selection_ring.emission = Color(1.0, 0.85, 0.25)
	mat_selection_ring.emission_energy_multiplier = 3.0


func _init_packet_orb() -> void:
	var sphere = SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.material = mat_packet_orb
	packet_orb.mesh = sphere
	packet_orb.visible = false


func _init_selection_ring() -> void:
	var ring = TorusMesh.new()
	ring.inner_radius = 1.05
	ring.outer_radius = 1.18
	ring.material = mat_selection_ring
	selection_ring.mesh = ring
	selection_ring.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_orbiting = true
				last_mouse_pos = event.position
				mouse_down_pos = event.position
			else:
				is_orbiting = false
				# Detect clean click vs drag orbit
				if event.position.distance_to(mouse_down_pos) < 6.0:
					var clicked_device = _find_clicked_device(event.position)
					if clicked_device != "":
						_select_device(clicked_device)
					else:
						# Only deselect if clicked empty space
						_deselect_device()

		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = clamp(cam_dist - 1.2, 6.0, 36.0)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = clamp(cam_dist + 1.2, 6.0, 36.0)
			_update_camera_transform()

	elif event is InputEventMouseMotion:
		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position

		if is_orbiting:
			cam_yaw -= delta.x * 0.007
			cam_pitch = clamp(cam_pitch - delta.y * 0.007, -1.35, 1.35)
			_update_camera_transform()
		elif is_panning:
			var right = camera.global_transform.basis.x
			var up = camera.global_transform.basis.y
			cam_target += (-right * delta.x + up * delta.y) * 0.015
			_update_camera_transform()


func _find_clicked_device(mouse_screen_pos: Vector2) -> String:
	var ray_origin = camera.project_ray_origin(mouse_screen_pos)
	var ray_dir = camera.project_ray_normal(mouse_screen_pos)
	var closest_device = ""
	var closest_dist = 999999.0

	for node_name in node_positions_3d.keys():
		var center: Vector3 = node_positions_3d[node_name]
		var radius = 1.0 # generous click sphere
		var oc = ray_origin - center
		var b = oc.dot(ray_dir)
		var c = oc.dot(oc) - radius * radius
		var discriminant = b * b - c
		if discriminant >= 0.0:
			var t = -b - sqrt(discriminant)
			if t > 0.0 and t < closest_dist:
				closest_dist = t
				closest_device = node_name

	return closest_device


func _select_device(node_name: String) -> void:
	selected_device_name = node_name
	print("[DEVICE SELECTED] ", node_name)

	# 1. Update 3D Selection Ring
	if node_positions_3d.has(node_name):
		selection_ring.position = node_positions_3d[node_name]
		selection_ring.visible = true

	# 2. Populate Device Details Panel
	var meta = device_metadata.get(node_name, {})
	device_name_label.text = "Router: %s" % node_name
	device_role_label.text = "[ %s ]" % meta.get("role", "Network Device")
	device_loopback_label.text = meta.get("loopback", "10.0.0.x/32")
	device_ospf_label.text = meta.get("ospf", "OSPF Process 1")

	# Check online status
	device_status_label.text = "● ONLINE (Batfish Simulation Active)"
	device_status_label.modulate = Color(0.25, 0.95, 0.45)

	# Populate Interfaces list with real-time Link UP / DOWN state
	for child in device_interfaces_list.get_children():
		child.queue_free()

	var ifaces: Array = meta.get("interfaces", [])
	for iface in ifaces:
		var iface_row = HBoxContainer.new()
		iface_row.add_theme_constant_override("separation", 8)

		var iface_edge = iface.get("edge", [])
		var is_down = false
		if iface_edge.size() >= 2:
			for be in broken_edges:
				var s = be.get("source", "")
				var t = be.get("target", "")
				if (s == iface_edge[0] and t == iface_edge[1]) or (s == iface_edge[1] and t == iface_edge[0]):
					is_down = true
					break

		var status_bullet = Label.new()
		status_bullet.text = "🔴" if is_down else "🟢"
		iface_row.add_child(status_bullet)

		var name_lbl = Label.new()
		name_lbl.text = iface.get("name", "iface")
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4) if is_down else Color(0.9, 0.95, 1.0))
		name_lbl.custom_minimum_size = Vector2(140, 20)
		iface_row.add_child(name_lbl)

		var ip_lbl = Label.new()
		ip_lbl.text = "%s -> %s" % [iface.get("ip", ""), iface.get("peer", "")]
		ip_lbl.add_theme_font_size_override("font_size", 11)
		ip_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.88))
		iface_row.add_child(ip_lbl)

		device_interfaces_list.add_child(iface_row)

	device_details_panel.visible = true


func _deselect_device() -> void:
	selected_device_name = ""
	selection_ring.visible = false
	device_details_panel.visible = false


func _on_device_set_as_src_pressed() -> void:
	if selected_device_name == "":
		return
	# Find index in src_select
	for i in range(src_select.item_count):
		if src_select.get_item_text(i) == selected_device_name:
			src_select.selected = i
			break
	_on_trace_button_pressed()


func _on_device_view_config_pressed() -> void:
	if selected_device_name == "":
		return
	for i in range(config_router_select.item_count):
		if config_router_select.get_item_text(i) == selected_device_name:
			config_router_select.selected = i
			break
	_toggle_config_modal()


func _update_camera_transform() -> void:
	var rot = Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var offset = rot * Vector3(0.0, 0.0, cam_dist)
	camera.position = cam_target + offset
	camera.look_at(cam_target, Vector3.UP)


func _reset_camera_view() -> void:
	cam_yaw = 0.0
	cam_pitch = -0.22
	cam_dist = 17.0
	cam_target = Vector3.ZERO
	_update_camera_transform()


func _connect_websocket() -> void:
	socket.close()
	var err = socket.connect_to_url(WS_URL)
	if err == OK:
		ws_status_label.text = "Connecting to %s..." % WS_URL
		ws_status_label.modulate = Color(0.95, 0.75, 0.25)
	else:
		ws_status_label.text = "Connection error (%d)" % err
		ws_status_label.modulate = Color(0.95, 0.35, 0.35)


func _process(delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			ws_status_label.text = "Connected (Batfish 3D Twin)"
			ws_status_label.modulate = Color(0.25, 0.92, 0.45)

		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var msg_str = packet.get_string_from_utf8()
			_handle_message(msg_str)

	elif state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
		if is_connected:
			is_connected = false
			ws_status_label.text = "Disconnected. Retrying..."
			ws_status_label.modulate = Color(0.95, 0.35, 0.35)

		reconnect_timer += delta
		if reconnect_timer >= 2.0:
			reconnect_timer = 0.0
			_connect_websocket()

	# Process 3D animated packet trace
	if flash_timer > 0.0:
		flash_timer = max(0.0, flash_timer - delta)
		pulse_time += delta
		_animate_trace_packet()
	else:
		packet_orb.visible = false

	# Spin selection ring gently
	if selection_ring.visible:
		selection_ring.rotate_y(delta * 1.5)


func _handle_message(raw_json: String) -> void:
	var parsed = JSON.parse_string(raw_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var msg_type = parsed.get("type", "")
	if msg_type == "init":
		var r_nodes = parsed.get("nodes", [])
		var r_edges = parsed.get("edges", [])
		var r_active = parsed.get("active_edges", [])
		var r_broken = parsed.get("broken_edges", [])
		var scen = parsed.get("scenario", "healthy")
		_build_3d_topology(r_nodes, r_edges, r_active, r_broken, scen)
	elif msg_type == "trace_result":
		var hops = parsed.get("hops", [])
		var status = parsed.get("status", "UNKNOWN")
		_on_trace_result(hops, status)
	elif msg_type == "config_data":
		config_text_edit.text = parsed.get("content", "")


func _build_3d_topology(new_nodes: Array, new_edges: Array, new_active: Array, new_broken: Array, scen: String) -> void:
	nodes = new_nodes
	edges = new_edges
	active_edges = new_active
	broken_edges = new_broken
	active_scenario = scen

	# Update scenario text badge
	var broken_count = broken_edges.size()
	if broken_count > 0:
		scenario_badge.text = "Scenario: %s (%d Link(s) DOWN)" % [active_scenario.capitalize(), broken_count]
		scenario_badge.modulate = Color(1.0, 0.45, 0.3)
	else:
		scenario_badge.text = "Scenario: Healthy Baseline (All Links UP)"
		scenario_badge.modulate = Color(0.3, 0.92, 0.5)

	# 1. Build Nodes in 3D
	for child in nodes_container.get_children():
		child.queue_free()

	for node_name in node_positions_3d.keys():
		var pos: Vector3 = node_positions_3d[node_name]

		var node_root = Node3D.new()
		node_root.name = node_name
		node_root.position = pos

		# Outer Sphere
		var sphere_inst = MeshInstance3D.new()
		var s_mesh = SphereMesh.new()
		s_mesh.radius = 0.65
		s_mesh.height = 1.3
		s_mesh.material = mat_router_body
		sphere_inst.mesh = s_mesh
		node_root.add_child(sphere_inst)

		# Orbit Ring
		var ring_inst = MeshInstance3D.new()
		var ring_mesh = TorusMesh.new()
		ring_mesh.inner_radius = 0.72
		ring_mesh.outer_radius = 0.84
		var r_mat = StandardMaterial3D.new()
		r_mat.albedo_color = Color(0.2, 0.6, 0.95)
		r_mat.emission_enabled = true
		r_mat.emission = Color(0.2, 0.6, 0.95)
		r_mat.emission_energy_multiplier = 1.5
		ring_mesh.material = r_mat
		ring_inst.mesh = ring_mesh
		node_root.add_child(ring_inst)

		# 3D Billboard Label
		var lbl = Label3D.new()
		lbl.position = Vector3(0.0, 1.4, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.text = "%s\n%s" % [node_name, device_metadata.get(node_name, {}).get("loopback", "Router")]
		lbl.font_size = 28
		lbl.outline_size = 6
		lbl.modulate = Color(0.92, 0.96, 1.0)
		node_root.add_child(lbl)

		nodes_container.add_child(node_root)

	# 2. Build 3D Links
	for child in edges_container.get_children():
		child.queue_free()

	# Draw active edges
	for edge in active_edges:
		var s = edge.get("source", "")
		var t = edge.get("target", "")
		if node_positions_3d.has(s) and node_positions_3d.has(t):
			var p1 = node_positions_3d[s]
			var p2 = node_positions_3d[t]
			var link_inst = MeshInstance3D.new()
			_align_cylinder(link_inst, p1, p2, 0.07, mat_active_link)
			edges_container.add_child(link_inst)

	# Draw broken edges (thicker, bright red)
	for edge in broken_edges:
		var s = edge.get("source", "")
		var t = edge.get("target", "")
		if node_positions_3d.has(s) and node_positions_3d.has(t):
			var p1 = node_positions_3d[s]
			var p2 = node_positions_3d[t]
			var broken_inst = MeshInstance3D.new()
			_align_cylinder(broken_inst, p1, p2, 0.12, mat_broken_link)
			edges_container.add_child(broken_inst)

			# Red warning marker in middle
			var mid_pos = (p1 + p2) * 0.5
			var marker_lbl = Label3D.new()
			marker_lbl.position = mid_pos + Vector3(0.0, 0.6, 0.0)
			marker_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker_lbl.text = "✖ LINK SEVERED"
			marker_lbl.font_size = 32
			marker_lbl.outline_size = 8
			marker_lbl.modulate = Color(1.0, 0.2, 0.2)
			edges_container.add_child(marker_lbl)

	# Refresh selected device if open
	if selected_device_name != "":
		_select_device(selected_device_name)

	status_label.text = "Simulation ready. Active 3D Links: %d / %d" % [active_edges.size(), edges.size()]
	status_label.modulate = Color(0.45, 0.85, 1.0)


func _align_cylinder(mesh_inst: MeshInstance3D, from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var dist = from.distance_to(to)
	if dist < 0.01:
		return

	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = dist
	cyl.radial_segments = 16
	cyl.material = mat
	mesh_inst.mesh = cyl

	var y_axis = (to - from).normalized()
	var ref = Vector3.UP
	if abs(y_axis.dot(ref)) > 0.95:
		ref = Vector3.FORWARD

	var x_axis = ref.cross(y_axis).normalized()
	var z_axis = y_axis.cross(x_axis).normalized()

	mesh_inst.transform.basis = Basis(x_axis, y_axis, z_axis)
	mesh_inst.position = (from + to) * 0.5


func _on_trace_button_pressed() -> void:
	print("[BUTTON] Run Trace Simulation pressed")
	if not is_connected:
		status_label.text = "WebSocket not connected. Please check backend..."
		status_label.modulate = Color(0.95, 0.5, 0.3)
		return

	var src = "core-r1"
	if src_select != null and src_select.item_count > 0 and src_select.selected >= 0:
		src = src_select.get_item_text(src_select.selected)

	var dst_ip = "192.168.10.1"
	if dst_select != null and dst_select.item_count > 0 and dst_select.selected >= 0:
		var meta = dst_select.get_item_metadata(dst_select.selected)
		if meta != null and str(meta) != "":
			dst_ip = str(meta)

	var req = {
		"action": "trace",
		"src": src,
		"dst_ip": dst_ip
	}
	socket.send_text(JSON.stringify(req))
	status_label.text = "Simulating: %s -> %s via Batfish forwarding plane..." % [src, dst_ip]
	status_label.modulate = Color(0.4, 0.85, 1.0)


func _load_scenario(scen_name: String) -> void:
	print("[BUTTON] Scenario pressed: ", scen_name)
	status_label.text = "Applying scenario '%s' and re-simulating in Batfish..." % scen_name
	status_label.modulate = Color(1.0, 0.8, 0.3)

	if not is_connected:
		status_label.text = "Cannot apply: WebSocket not connected yet."
		status_label.modulate = Color(1.0, 0.4, 0.4)
		return

	var src = "core-r1"
	if src_select != null and src_select.item_count > 0 and src_select.selected >= 0:
		src = src_select.get_item_text(src_select.selected)

	var dst_ip = "192.168.10.1"
	if dst_select != null and dst_select.item_count > 0 and dst_select.selected >= 0:
		var meta = dst_select.get_item_metadata(dst_select.selected)
		if meta != null and str(meta) != "":
			dst_ip = str(meta)

	var req = {
		"action": "load_scenario",
		"scenario": scen_name,
		"src": src,
		"dst_ip": dst_ip
	}
	socket.send_text(JSON.stringify(req))


func _break_link(link_id: String) -> void:
	print("[BUTTON] Break link pressed: ", link_id)
	if not is_connected:
		return

	var src = "core-r1"
	if src_select != null and src_select.item_count > 0 and src_select.selected >= 0:
		src = src_select.get_item_text(src_select.selected)

	var dst_ip = "192.168.10.1"
	if dst_select != null and dst_select.item_count > 0 and dst_select.selected >= 0:
		var meta = dst_select.get_item_metadata(dst_select.selected)
		if meta != null and str(meta) != "":
			dst_ip = str(meta)

	status_label.text = "Fault injection action '%s' sent to Batfish..." % link_id
	status_label.modulate = Color(1.0, 0.8, 0.3)

	var req = {
		"action": "break_link",
		"link_id": link_id,
		"src": src,
		"dst_ip": dst_ip
	}
	socket.send_text(JSON.stringify(req))


func _on_trace_result(hops: Array, status: String) -> void:
	active_hops = hops
	active_status = status
	flash_timer = 5.0
	pulse_time = 0.0

	var hops_display = " -> ".join(PackedStringArray(hops))
	if hops.is_empty():
		hops_display = "(No path computed)"

	var status_color = Color(0.2, 0.92, 0.42)
	var explanation = ""

	if status == "ACCEPTED":
		explanation = "[ ROUTE OK - Packet Accepted at Destination ]"
	elif "DENIED" in status:
		status_color = Color(0.95, 0.25, 0.25)
		explanation = "[ ACCESS DENIED - Dropped by Security ACL Filter ]"
	elif "NO_ROUTE" in status or "NULL" in status:
		status_color = Color(0.95, 0.45, 0.2)
		explanation = "[ DROPPED - No Route Available (Link Severed) ]"
	else:
		status_color = Color(0.9, 0.8, 0.2)
		explanation = "[ Disposition: " + status + " ]"

	status_label.text = "Trace Result: [ %s ] | %s" % [hops_display, explanation]
	status_label.modulate = status_color

	_render_3d_trace_path()


func _render_3d_trace_path() -> void:
	for child in trace_container.get_children():
		child.queue_free()

	if active_hops.size() <= 1:
		packet_orb.visible = false
		return

	var is_ok = (active_status == "ACCEPTED")
	var trace_color = Color(0.2, 0.95, 0.45) if is_ok else Color(0.95, 0.25, 0.25)
	mat_trace_link.albedo_color = trace_color
	mat_trace_link.emission = trace_color

	for i in range(active_hops.size() - 1):
		var h1 = active_hops[i]
		var h2 = active_hops[i + 1]
		if node_positions_3d.has(h1) and node_positions_3d.has(h2):
			var p1 = node_positions_3d[h1]
			var p2 = node_positions_3d[h2]
			var pipe = MeshInstance3D.new()
			_align_cylinder(pipe, p1, p2, 0.16, mat_trace_link)
			trace_container.add_child(pipe)

	packet_orb.visible = true


func _animate_trace_packet() -> void:
	var total_segs = active_hops.size() - 1
	if total_segs <= 0:
		packet_orb.visible = false
		return

	var t_cycle = fmod(pulse_time * 0.9, 1.0)
	var float_seg = t_cycle * total_segs
	var seg_idx = clamp(int(floor(float_seg)), 0, total_segs - 1)
	var seg_t = float_seg - seg_idx

	var n1 = active_hops[seg_idx]
	var n2 = active_hops[seg_idx + 1]
	if node_positions_3d.has(n1) and node_positions_3d.has(n2):
		packet_orb.visible = true
		packet_orb.position = node_positions_3d[n1].lerp(node_positions_3d[n2], seg_t)


func _toggle_config_modal() -> void:
	config_modal.visible = not config_modal.visible
	if config_modal.visible:
		_on_config_router_selected(config_router_select.selected)


func _on_config_router_selected(index: int) -> void:
	var r_name = config_router_select.get_item_text(index)
	socket.send_text(JSON.stringify({"action": "get_config", "node": r_name}))


func _on_save_config_pressed() -> void:
	var r_name = config_router_select.get_item_text(config_router_select.selected)
	var content = config_text_edit.text
	status_label.text = "Sending config changes for %s to Batfish..." % r_name
	status_label.modulate = Color(0.4, 0.85, 1.0)
	socket.send_text(JSON.stringify({
		"action": "save_config",
		"node": r_name,
		"content": content
	}))
	config_modal.visible = false
