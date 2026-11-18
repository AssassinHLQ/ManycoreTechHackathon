extends RefCounted
## Rebuild visual LOD indices offline. Full-resolution vertices and collision stay unchanged.
static func generate(directory := "res://assets/runtime_bakes/streamed/") -> Error:
	for filename in DirAccess.get_files_at(directory):
		if not filename.begins_with("terrain_") or not filename.ends_with(".res"):
			continue
		var path: String = directory + filename
		var original := load(path) as ArrayMesh
		if original == null:
			return ERR_INVALID_DATA
		var importer := ImporterMesh.from_mesh(original)
		importer.generate_lods(60.0, 0.0, [])
		var mesh := importer.get_mesh()
		var levels := 0
		for surface in range(original.get_surface_count()):
			var before := original.surface_get_arrays(surface)
			# Validate the original attributes before GPU normal packing. get_mesh()
			# quantizes normals again, with a small expected codec round-trip error.
			var after := importer.get_surface_arrays(surface)
			for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
				if before[channel] != after[channel]:
					return ERR_INVALID_DATA
			levels += importer.get_surface_lod_count(surface)
		mesh.set_meta("runtime_lod_levels", levels)
		var error := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			return error
		print("BAKED LODS ", filename, " levels=", levels)
	return OK
