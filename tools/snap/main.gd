extends Node3D
func _matte(n: Node):
	if n is MeshInstance3D:
		for s in n.mesh.get_surface_count():
			var m: BaseMaterial3D = n.mesh.surface_get_material(s).duplicate()
			m.metallic = 0.0; m.metallic_texture = null; m.roughness = 1.0; m.roughness_texture = null; m.normal_enabled = false
			n.set_surface_override_material(s, m)
	for c in n.get_children(): _matte(c)
func _ready():
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.96,0.96,0.97)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color.WHITE; env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-35, 25, 0); add_child(l)
	var m: Node3D = (load("res://m.glb") as PackedScene).instantiate(); add_child(m); _matte(m)
	var ab := AABB(); var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.get_aabb() if mi.skin else mi.global_transform * mi.get_aabb()  # 스킨 메시는 뼈가 위치를 정해서 노드 변환을 안 씀
		ab = b if first else ab.merge(b); first = false
	print("AABB ", ab)
	var c := ab.get_center()
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = maxf(ab.size.y, maxf(ab.size.x, ab.size.z)) * 1.15; add_child(cam); cam.current = true
	var dirs := {"pz": Vector3(0,0,1), "px": Vector3(1,0,0), "nz": Vector3(0,0,-1), "nx": Vector3(-1,0,0)}
	for k in dirs:
		cam.position = c + dirs[k] * 5.0; cam.look_at(c, Vector3.UP)
		l.global_transform = cam.global_transform; l.rotate_object_local(Vector3.RIGHT, deg_to_rad(-20))
		for i in 3: await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://" + k + ".png")
	get_tree().quit()
