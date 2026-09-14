extends SceneTree
## Native resource + GPU batch and one-metre navigation checks for authored forests.
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func point_rect_distance(point: Vector2, bounds: Rect2) -> float:
	return point.distance_to(point.clamp(bounds.position, bounds.end))

func check_exploration_projection(forest: Node3D) -> void:
	var points: Array[Vector2] = []
	for coordinate: Vector2 in RogueCatalog.BALANCE.coordinates:
		points.append(Vector2((coordinate.x - 3.5) * 9.0, (coordinate.y - 2.0) * 10.0))
	var clear_nodes: bool = true
	var clear_roads: bool = true
	var edges: PackedInt32Array = RogueCatalog.BALANCE.edges
	for tree: Node3D in forest.get_node("Canopy").get_children():
		var model: MeshInstance3D = tree.get_node("SculptedMesh")
		var arrays: Array = model.mesh.surface_get_arrays(0)
		var initialized: bool = false
		var bounds := Rect2()
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var world: Vector3 = model.global_transform * vertex
			var projected := Vector2(world.x, world.z - world.y / sqrt(3.0))
			if not initialized:
				bounds = Rect2(projected, Vector2.ZERO)
				initialized = true
			else:
				bounds = bounds.expand(projected)
		for point: Vector2 in points:
			clear_nodes = clear_nodes and point_rect_distance(point, bounds) >= 2.5
		for index: int in range(0, edges.size(), 2):
			var a: Vector2 = points[edges[index]]
			var b: Vector2 = points[edges[index+1]]
			var count: int = ceili(a.distance_to(b))
			for sample: int in count + 1:
				clear_roads = clear_roads and point_rect_distance(a.lerp(b, float(sample) / count), bounds) >= 1.0
	check(clear_nodes, "exploration crown projection leaves all 34 node rings clear")
	check(clear_roads, "exploration crown projection leaves all 37 adjacent routes clear")

func _run() -> void:
	create_timer(40.0, true, false, true).timeout.connect(func(): quit(3))
	for kind: String in ["exploration", "outpost", "siege"]:
		var forest: Node3D = load("res://scenes/rogue/forest_" + kind + ".tscn").instantiate()
		root.add_child(forest)
		check(forest.find_children("*", "CollisionObject3D", true, false).is_empty(), kind + " preview landscape has no collision or gameplay nodes")
		var ground: Mesh = forest.get_node("Ground").mesh
		var arrays: Array = ground.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_VERTEX].size() == arrays[Mesh.ARRAY_COLOR].size(), kind + " terrain retains real vertex paint")
		check(arrays[Mesh.ARRAY_VERTEX].size() == arrays[Mesh.ARRAY_TEX_UV].size(), kind + " ground texture UVs cover every vertex")
		var material: StandardMaterial3D = ground.surface_get_material(0)
		check(material.vertex_color_use_as_albedo and material.vertex_color_is_srgb, kind + " colour space keeps painted foliage/soil readable")
		check(material.albedo_texture != null and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, kind + " ground detail has mipmapped filtering")
		check(forest.get_node("Canopy").get_child_count() >= 150, kind + " authored mixed forest is present")
		check(forest.get_node("Landmarks").get_child_count() >= 10, kind + " distinct sculpted landmarks are present")
		if kind == "exploration":
			check_exploration_projection(forest)
		for node: MultiMeshInstance3D in forest.get_node("Understory").get_children():
			check(node.multimesh.instance_count > 0, kind + "/" + str(node.name) + " vegetation instances exist")
			if DisplayServer.get_name() != "headless":
				var first: Transform3D = node.multimesh.get_instance_transform(0)
				var last: Transform3D = node.multimesh.get_instance_transform(node.multimesh.instance_count - 1)
				check(first.origin.distance_to(last.origin) > 1.0 and first.basis.determinant() > 0.01, kind + "/" + str(node.name) + " saved GPU transforms are populated and spread out")
		forest.queue_free()
		await process_frame
		if kind == "exploration":
			continue
		var map: Node3D = load("res://scenes/rogue/battle_" + kind + "_map.tscn").instantiate()
		root.add_child(map)
		var region: NavigationRegion3D = map.get_node("NavigationRegion3D")
		var mesh: NavigationMesh = region.navigation_mesh
		var vertices: PackedVector3Array = mesh.get_vertices()
		var metre_grid: bool = true
		for i: int in mesh.get_polygon_count():
			var polygon: PackedInt32Array = mesh.get_polygon(i)
			if polygon.size() != 4:
				metre_grid = false
				break
			var bounds := AABB(vertices[polygon[0]], Vector3.ZERO)
			for index: int in polygon:
				bounds = bounds.expand(vertices[index])
			metre_grid = metre_grid and bounds.size.is_equal_approx(Vector3(1, 0, 1))
		check(metre_grid and mesh.get_polygon_count() > 4000, kind + " navigation source stays on a one-metre grid")
		check(is_equal_approx(mesh.agent_radius, 1.15), kind + " navigation reserves the heavy cannon radius")
		check(map.get_node("Buildings").get_child_count() == (8 if kind == "outpost" else 1), kind + " objective building markers are preserved")
		check(map.get_node("Defenders").get_child_count() == (16 if kind == "outpost" else 0), kind + " authored initial enemy markers are preserved")
		check(map.get_node("Entrances").get_child_count() == 4, kind + " four entry markers remain available")
		var valid_shapes: bool = true
		for body: StaticBody3D in map.get_node("Environment/NaturalObstacles").get_children():
			var shape: CollisionShape3D = body.get_node("Shape")
			valid_shapes = valid_shapes and shape.scale.is_equal_approx(Vector3.ONE) and shape.shape is CylinderShape3D
		check(valid_shapes, kind + " obstacles use real radii without nonuniform cylinder scaling")
		await physics_frame
		await physics_frame
		# Activate this isolated viewport's map, then await native asynchronous publication.
		NavigationServer3D.map_set_active(region.get_navigation_map(), true)
		NavigationServer3D.map_force_update(region.get_navigation_map())
		for _frame: int in 120:
			if NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0:
				break
			await physics_frame
		await create_timer(0.1, true, false, true).timeout
		var start := Vector3(-43, 0, 0) if kind == "outpost" else Vector3(9, 0, 9)
		var targets: Array = [Vector3(48,0,0),Vector3(-12,0,-15),Vector3(-12,0,15),Vector3(22,0,0)] if kind == "outpost" else [Vector3(-33,0,0),Vector3(33,0,0),Vector3(0,0,-33),Vector3(0,0,33)]
		for target: Vector3 in targets:
			var path: PackedVector3Array = NavigationServer3D.map_get_path(region.get_navigation_map(), start, target, true)
			check(path.size() >= 2 and path[-1].distance_to(target) < 0.1, kind + " native navigation reaches " + str(target))
		map.queue_free()
		await process_frame
	print("ROGUE_FOREST_CHECKS ", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
