extends SceneTree
# 허벅지 뼈 선분에서 점까지 거리 분포와, 그 점들이 다리 뼈에 묶인 정도를 잰다.
func _seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a; var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
func _init():
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://../models/frog_rig.glb"), st)
	var n := doc.generate_scene(st); root.add_child(n)
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
	var to_mesh := Transform3D()
	var nd: Node = sk
	while nd != n:
		to_mesh = (nd as Node3D).transform * to_mesh; nd = nd.get_parent()
	var bind := {}
	for b in mi.skin.get_bind_count():
		var nm: String = mi.skin.get_bind_name(b)
		if nm == "": nm = sk.get_bone_name(mi.skin.get_bind_bone(b))
		bind[nm] = b
	print("bind sample ", mi.skin.get_bind_name(0), " / ", mi.skin.get_bind_bone(0))
	var legs := [int(bind["LeftUpLeg"]), int(bind["RightUpLeg"]), int(bind["LeftLeg"]), int(bind["RightLeg"])]
	var ax := []
	for sd in ["Left", "Right"]:
		ax.append([to_mesh * sk.get_bone_global_rest(sk.find_bone(sd + "UpLeg")).origin, to_mesh * sk.get_bone_global_rest(sk.find_bone(sd + "Leg")).origin])
	print("thigh L ", ax[0], " R ", ax[1])
	var a := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]; var bo = a[Mesh.ARRAY_BONES]; var we: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per: int = we.size() / v.size()
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var img: Image = (mi.mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture.get_image()
	if img.is_compressed(): img.decompress()
	var segs := []
	for sd in ["Left", "Right"]:
		var o := []
		for b in [sd + "UpLeg", sd + "Leg", sd + "Foot", sd + "ToeBase"]: o.append(to_mesh * sk.get_bone_global_rest(sk.find_bone(b)).origin)
		print(sd, " ", o)
		segs.append([o[0], o[1]]); segs.append([o[1], o[2]]); segs.append([o[2], o[3]])
	# 0.06~0.14m 높이 점의 색을 거리별로 몇 개 뽑아 본다(신발 목 vs 로브 단 색 구분용).
	var seen := {}
	for k in range(0, v.size(), 7):
		if v[k].y < 0.06 or v[k].y > 0.14: continue
		var d := 1e9
		for sg in segs: d = minf(d, _seg(v[k], sg[0], sg[1]))
		var key := "%d" % int(d * 100.0)
		if seen.get(key, 0) >= 6: continue
		seen[key] = seen.get(key, 0) + 1
		var col := img.get_pixelv(Vector2i(uv[k] * Vector2(img.get_size())).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE))
		print("y%.2f d%scm rgb(%.2f %.2f %.2f) h%.2f s%.2f v%.2f" % [v[k].y, key, col.r, col.g, col.b, col.h, col.s, col.v])
	quit()
