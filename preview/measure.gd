extends SceneTree
# 의상 보라 vs 물약 병 색: 보라 계열 점의 색 분포를 자리별로.
func _init():
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://../models/frog_rig.glb"), st)
	var n := doc.generate_scene(st); root.add_child(n)
	var mi: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
	var a := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var img: Image = (mi.mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture.get_image()
	if img.is_compressed(): img.decompress()
	# 유리병: 왼쪽 허리(-x) 밝은 점(명도 0.55 이상, 초록·갈색 아님)의 범위와 그 안 색 분포
	var mn := Vector3(1e9, 1e9, 1e9); var mx := -mn
	for k in v.size():
		var col := img.get_pixelv(Vector2i(uv[k] * Vector2(img.get_size())).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE))
		var p := v[k]
		if p.x < -0.10 and p.y > 0.2 and p.y < 0.45 and col.v > 0.55 and not (col.h > 0.04 and col.h < 0.3):
			mn = mn.min(p); mx = mx.max(p)
	print("potion box ", mn, " ", mx)
	var hs := {}
	for k in v.size():
		var p := v[k]
		if p.x > mx.x + 0.01 or p.x < mn.x - 0.01 or p.y < mn.y - 0.01 or p.y > mx.y + 0.01 or p.z < mn.z - 0.01 or p.z > mx.z + 0.01: continue
		var col := img.get_pixelv(Vector2i(uv[k] * Vector2(img.get_size())).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE))
		var bright := col.v > 0.5
		print("PX %.3f %d %.2f %.2f" % [p.x, 1 if bright else 0, col.h, col.v])
		var key := "h%.2f s%.1f v%.1f" % [snappedf(col.h, 0.04), snappedf(col.s, 0.2), snappedf(col.v, 0.2)]
		hs[key] = hs.get(key, 0) + 1
	var ks := hs.keys(); ks.sort_custom(func(x, y): return hs[x] > hs[y])
	for kk in ks.slice(0, 24): print(kk, " ", hs[kk])
	quit()
