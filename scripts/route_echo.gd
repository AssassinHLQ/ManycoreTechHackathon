extends Node3D

## A decoded attic record projects a second, independently scannable signal.
var anomaly_id := ""
var title := ""
var body := ""
var accent_color := Color("9ae7df")
var scan_time := 2.4
var scan_range := 55.0


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = accent_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = accent_color
	material.emission_energy_multiplier = 1.5
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.65
	sphere.height = 1.3
	orb.mesh = sphere
	orb.material_override = material
	orb.position.y = 3.0
	add_child(orb)
	for height in [0.15, 2.2, 3.8]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.1
		torus.outer_radius = 1.25
		ring.mesh = torus
		ring.material_override = material
		ring.position.y = height
		add_child(ring)
	var label := Label3D.new()
	label.text = title + "\n按住 F 扫描回声"
	label.font = load("res://assets/ui_font.ttf")
	label.font_size = 48
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 5.5
	label.modulate = accent_color
	add_child(label)
