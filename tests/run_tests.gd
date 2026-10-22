extends SceneTree
## Headless tests for the dungeon generator. From the repository root:
##   godot --headless --path godot/02-dungeon-generator -s res://tests/run_tests.gd
## Prints PASS or FAIL per test and exits with 0 only if every test passed.

const Layout := preload("res://steps/step_07_debug_map/layout.gd")

const CELL_SIZE := 10.0
const RAY_HEIGHT := 1.2 ## Metres above the floor: through the middle of a doorway.
const WALL_THICKNESS := 0.2 ## KB graybox standard: interior wall 0.1-0.25 x 3.0 m.
const WALL_HEIGHT := 3.0
const SLAB_THICKNESS := 0.2 ## Floor and ceiling.
const PLAYER_HEIGHT := 1.8
const ALL_LAYERS := 0xFFFFF ## Camera3D.cull_mask of a camera that renders every layer.
const LAYER_2 := 2 ## The VisualInstance3D.layers value of the second layer: ceiling and fixture.
const MATERIAL_DIR := "res://materials/"
const WALL_NAMES: Array[String] = ["WallNorth", "WallEast", "WallSouth", "WallWest"]
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const ROOM_COUNTS: Array[int] = [1, 2, 12, 40]
const SEED_COUNT := 200

const STEPS: Array[String] = [
	"step_01_one_room",
	"step_02_room_grid",
	"step_03_seeded_layout",
	"step_04_doors",
	"step_05_walking_player",
	"step_06_mouse_look",
	"step_07_debug_map",
]
const STEPS_WITH_DOORS: Array[String] = [
	"step_04_doors", "step_05_walking_player", "step_06_mouse_look", "step_07_debug_map",
]
const STEPS_WITH_PLAYER: Array[String] = ["step_05_walking_player", "step_06_mouse_look", "step_07_debug_map"]
const STEPS_WITH_MOUSE_LOOK: Array[String] = ["step_06_mouse_look", "step_07_debug_map"]
const LAYOUT_STEPS: Array[String] = [
	"step_03_seeded_layout", "step_04_doors", "step_05_walking_player", "step_06_mouse_look", "step_07_debug_map",
]

## Counts the script errors the engine logs. A test that hits one stops at that line and the engine hands back an
## empty array, which reads as a pass: `_report` charges the count to the test that ran.
class ScriptErrorCounter extends Logger:
	var count := 0
	var _lock := Mutex.new() ## The engine calls a logger from any thread.

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		_lock.unlock()

var _passed := 0
var _failed := 0
var _skipped := 0
var _script_errors := ScriptErrorCounter.new() ## Registered with the engine's logger for the whole run.
var _script_errors_reported := 0 ## How many script errors the tests reported so far have been charged with.

func _initialize() -> void:
	OS.add_logger(_script_errors)
	_report("layout: same seed gives the same layout, another seed another one", test_determinism())
	_report("layout: room count and unique cells, seeds 1-%d" % SEED_COUNT, test_count_and_uniqueness())
	_report("layout: doors form a connected tree of neighbours", test_connectivity())
	_report("layout: layout.gd gives the same cells in steps 3 to 7", test_layout_copies_agree())
	_report("materials: shared grid, world-space triplanar, midtone albedo, floor lighter than walls", test_materials())
	for step in STEPS:
		_report("%s: rooms follow the graybox standard (sizes, ceiling, fixture, light)" % step, await test_room_standard(step))
		_report("%s: wall is 0.2 m thick, the ceiling blocks a ray, the fixture does not (raycasts)" % step, await test_room_physics(step))
		_report("%s: cutaway, overview cameras skip layer 2 and player cameras see it" % step, await test_cameras(step))
		_report("%s: ambient fill, sun and sky" % step, await test_lighting(step))
	for step: String in ["step_01_one_room", "step_02_room_grid", "step_03_seeded_layout"]:
		_report("%s: every doorway is cut" % step, await test_all_doorways_cut(step))
	for step in STEPS_WITH_DOORS:
		_report("%s: doors are open on both sides, walls block (raycasts)" % step, await test_doors(step))
	_report("step_07_debug_map: doorway is 1.6 x 2.4 m", await test_doorway_size())
	for step in STEPS_WITH_PLAYER:
		_report("%s: player walks forward through a doorway" % step, await test_walk_through_doorway(step))
		_report("%s: player is stopped by a wall" % step, await test_walk_into_wall(step))
		_report("%s: player jumps and lands" % step, await test_jump(step))
	for step in STEPS_WITH_MOUSE_LOOK:
		_report("%s: right stick turns the body and tilts the head, clamped at 89 deg" % step, await test_stick_look(step))
		if DisplayServer.get_name() == "headless":
			_skip("%s: mouse look, Esc and click" % step, "the headless display server never reports a captured mouse; tools/capture.gd checks it in a window")
			continue
		_report("%s: mouse look turns the body and clamps the head" % step, await test_mouse_look(step))
		_report("%s: Esc releases and a click recaptures the mouse" % step, await test_mouse_capture(step))
	_report("step_07_debug_map: Tab toggles the map", await test_toggle_map())
	_report("step_07_debug_map: R rebuilds with seed + 1", await test_regenerate())
	for step in STEPS:
		_report("%s: main scene runs 30 frames" % step, await test_scene_runs(step))

	OS.remove_logger(_script_errors)
	print("\n%d passed, %d failed, %d skipped" % [_passed, _failed, _skipped])
	quit(1 if _failed > 0 else 0)

#region Layout (pure data, no scene)

func test_determinism() -> Array[String]:
	var failures: Array[String] = []
	var first: RefCounted = Layout.generate(42, 12)
	var second: RefCounted = Layout.generate(42, 12)
	var other: RefCounted = Layout.generate(43, 12)
	_expect(failures, first.cells == second.cells, "seed 42 twice: cells differ")
	_expect(failures, first.doors == second.doors, "seed 42 twice: doors differ")
	_expect(failures, first.cells != other.cells, "seed 43 gives the same cells as seed 42")
	return failures

func test_count_and_uniqueness() -> Array[String]:
	var failures: Array[String] = []
	for layout_seed in range(1, SEED_COUNT + 1):
		for count in ROOM_COUNTS:
			var layout: RefCounted = Layout.generate(layout_seed, count)
			var cells: Array[Vector2i] = layout.cells
			var unique := {}
			for cell in cells:
				unique[cell] = true
			var label := "seed %d, %d rooms" % [layout_seed, count]
			_expect(failures, cells.size() == count, "%s: got %d cells" % [label, cells.size()])
			_expect(failures, unique.size() == cells.size(), "%s: duplicate cells" % label)
			_expect(failures, cells[0] == Vector2i.ZERO, "%s: first cell is not (0, 0)" % label)
	return failures

func test_connectivity() -> Array[String]:
	var failures: Array[String] = []
	for layout_seed in range(1, SEED_COUNT + 1):
		for count in ROOM_COUNTS:
			var layout: RefCounted = Layout.generate(layout_seed, count)
			var cells: Array[Vector2i] = layout.cells
			var doors: Array[Array] = layout.doors
			var label := "seed %d, %d rooms" % [layout_seed, count]
			_expect(failures, doors.size() == cells.size() - 1, "%s: %d doors for %d cells" % [label, doors.size(), cells.size()])
			for door in doors:
				var from: Vector2i = door[0]
				var to: Vector2i = door[1]
				var gap := to - from
				_expect(failures, absi(gap.x) + absi(gap.y) == 1, "%s: door %s -> %s is not between neighbours" % [label, from, to])
			_expect(failures, _reachable_from_start(cells, doors) == cells.size(), "%s: not every room is reachable" % label)
	return failures

func test_layout_copies_agree() -> Array[String]:
	var failures: Array[String] = []
	var reference: RefCounted = Layout.generate(42, 12)
	for step in LAYOUT_STEPS:
		var script: GDScript = load("res://steps/%s/layout.gd" % step)
		var layout: RefCounted = script.generate(42, 12)
		_expect(failures, layout.cells == reference.cells, "%s: cells differ from step 7" % step)
	return failures

## Breadth-first search over the doors, starting in (0, 0). Returns how many cells it reached.
func _reachable_from_start(cells: Array[Vector2i], doors: Array[Array]) -> int:
	var neighbours := {}
	for cell in cells:
		neighbours[cell] = []
	for door in doors:
		neighbours[door[0]].append(door[1])
		neighbours[door[1]].append(door[0])
	var seen := {Vector2i.ZERO: true}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for next: Vector2i in neighbours[cell]:
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size()

#endregion

#region Rooms to the graybox standard (scene + materials)

func test_materials() -> Array[String]:
	var failures: Array[String] = []
	var grid := load(MATERIAL_DIR + "grid.png") as Texture2D
	_expect(failures, grid != null, "grid.png is missing")
	if grid == null:
		return failures
	var image := grid.get_image()
	_expect(failures, image.get_size() == Vector2i(256, 256), "grid.png is %s, expected 256 x 256 (one tile is 1 m)" % image.get_size())
	_expect(failures, image.has_mipmaps(), "grid.png has no mipmaps: the lines would shimmer in the distance")
	var fill := image.get_pixel(32, 32)
	var half_line := image.get_pixel(127, 32)
	var metre_line := image.get_pixel(0, 32)
	_expect(failures, metre_line.v < half_line.v and half_line.v < fill.v, "line values: metre %.2f, half metre %.2f, fill %.2f" % [metre_line.v, half_line.v, fill.v])
	_expect(failures, image.get_pixel(255, 32) == metre_line, "the tile does not wrap: left and right border differ")

	var effective := {}
	for material_name: String in ["floor", "wall", "ceiling", "doorway"]:
		var material := load(MATERIAL_DIR + material_name + ".tres") as StandardMaterial3D
		_expect(failures, material != null, "%s.tres is missing" % material_name)
		if material == null:
			continue
		_expect(failures, material.albedo_texture == grid, "%s: albedo texture is not the shared grid" % material_name)
		_expect(failures, material.uv1_triplanar and material.uv1_world_triplanar, "%s: not triplanar in world space" % material_name)
		_expect(failures, material.uv1_scale.is_equal_approx(Vector3.ONE), "%s: uv1_scale %s, one tile per metre needs (1, 1, 1)" % [material_name, material.uv1_scale])
		_expect(failures, material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "%s: unshaded" % material_name)
		var albedo := (material.albedo_color.srgb_to_linear() * fill.srgb_to_linear()).linear_to_srgb()
		_expect(failures, albedo.v >= 0.5 and albedo.v <= 1.0, "%s: effective albedo %.2f is outside the 50-100 percent midtone range" % [material_name, albedo.v])
		effective[material_name] = albedo
	if effective.size() == 4:
		var floor_albedo: Color = effective["floor"]
		var wall_albedo: Color = effective["wall"]
		var ceiling_albedo: Color = effective["ceiling"]
		var doorway_albedo: Color = effective["doorway"]
		_expect(failures, absf(floor_albedo.v - 0.70) < 0.02, "floor albedo %.2f, expected about 0.70" % floor_albedo.v)
		_expect(failures, absf(wall_albedo.v - 0.55) < 0.02, "wall albedo %.2f, expected about 0.55" % wall_albedo.v)
		_expect(failures, absf(ceiling_albedo.v - 0.60) < 0.02, "ceiling albedo %.2f, expected about 0.60" % ceiling_albedo.v)
		_expect(failures, floor_albedo.v > ceiling_albedo.v and ceiling_albedo.v > wall_albedo.v, "floor must be lighter than ceiling, ceiling lighter than walls")
		_expect(failures, doorway_albedo.r > doorway_albedo.g and doorway_albedo.g > doorway_albedo.b, "the doorway accent is not warm: %s" % doorway_albedo)

	var fixture := load(MATERIAL_DIR + "fixture.tres") as StandardMaterial3D
	_expect(failures, fixture != null and fixture.emission_enabled and fixture.emission_energy_multiplier > 1.0, "fixture.tres is not emissive")
	return failures

func test_room_standard(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var rooms := _rooms_of(main)
	_expect(failures, not rooms.is_empty(), "no rooms found")
	for room in rooms:
		var label := "room at %s" % room.position
		var floor_box := _box(room, "Shell/Floor", failures)
		if floor_box == null:
			continue
		_expect(failures, is_equal_approx(floor_box.size.y, SLAB_THICKNESS), "%s: floor is %.2f m thick" % [label, floor_box.size.y])
		_expect(failures, is_equal_approx(floor_box.position.y + floor_box.size.y / 2.0, 0.0), "%s: floor top is at y = %.2f" % [label, floor_box.position.y + floor_box.size.y / 2.0])
		_expect(failures, _uses(floor_box, "floor.tres"), "%s: floor does not use floor.tres" % label)

		for wall_name in WALL_NAMES:
			var wall := _box(room, "Shell/" + wall_name, failures)
			var doorway := _box(room, "Shell/%s/Doorway" % wall_name, failures)
			if wall == null or doorway == null:
				continue
			var along_x := wall_name in ["WallNorth", "WallSouth"]
			var thickness := wall.size.z if along_x else wall.size.x
			var length := wall.size.x if along_x else wall.size.z
			var cut_depth := doorway.size.z if along_x else doorway.size.x
			var cut_width := doorway.size.x if along_x else doorway.size.z
			_expect(failures, is_equal_approx(thickness, WALL_THICKNESS), "%s: %s is %.2f m thick" % [label, wall_name, thickness])
			_expect(failures, is_equal_approx(length, CELL_SIZE + WALL_THICKNESS), "%s: %s is %.2f m long, expected 10.2 (fills the corners)" % [label, wall_name, length])
			_expect(failures, is_equal_approx(wall.size.y, WALL_HEIGHT), "%s: %s is %.2f m high" % [label, wall_name, wall.size.y])
			_expect(failures, is_equal_approx(wall.position.y - wall.size.y / 2.0, 0.0), "%s: %s starts at y = %.2f" % [label, wall_name, wall.position.y - wall.size.y / 2.0])
			_expect(failures, _uses(wall, "wall.tres"), "%s: %s does not use wall.tres" % [label, wall_name])
			_expect(failures, cut_depth > WALL_THICKNESS, "%s: %s doorway cutter is %.2f m deep, the wall is %.2f m" % [label, wall_name, cut_depth, WALL_THICKNESS])
			_expect(failures, is_equal_approx(cut_width, 1.6) and is_equal_approx(doorway.size.y, 2.4), "%s: %s doorway is %.2f x %.2f m" % [label, wall_name, cut_width, doorway.size.y])
			_expect(failures, _uses(doorway, "doorway.tres"), "%s: %s doorway does not use doorway.tres" % [label, wall_name])

		# The faces a Subtraction cuts take the cutter's material: the warm accent on the reveal.
		var open_doorways := 0
		for wall_name in WALL_NAMES:
			if (room.get_node("Shell/%s/Doorway" % wall_name) as CSGBox3D).visible:
				open_doorways += 1
		var cut_vertices := _vertices_with_material(room.get_node("Shell") as CSGCombiner3D, "doorway.tres")
		_expect(failures, (cut_vertices > 0) == (open_doorways > 0), "%s: %d open doorways but %d vertices use doorway.tres" % [label, open_doorways, cut_vertices])

		# The ceiling is its own root shape next to the Shell, not a child of the combiner.
		var ceiling := _box(room, "Ceiling", failures)
		if ceiling == null:
			continue
		_expect(failures, ceiling.get_parent() == room and ceiling.is_root_shape(), "%s: the ceiling is not a root shape of its own" % label)
		_expect(failures, ceiling.use_collision, "%s: the ceiling has no collision" % label)
		_expect(failures, ceiling.layers == LAYER_2, "%s: ceiling layers are %d, expected only layer 2 (%d)" % [label, ceiling.layers, LAYER_2])
		_expect(failures, is_equal_approx(ceiling.size.y, SLAB_THICKNESS), "%s: ceiling is %.2f m thick" % [label, ceiling.size.y])
		_expect(failures, ceiling.size.x == CELL_SIZE and ceiling.size.z == CELL_SIZE, "%s: ceiling is %.1f x %.1f m" % [label, ceiling.size.x, ceiling.size.z])
		_expect(failures, is_equal_approx(ceiling.position.y - ceiling.size.y / 2.0, WALL_HEIGHT), "%s: ceiling underside is at y = %.2f" % [label, ceiling.position.y - ceiling.size.y / 2.0])
		_expect(failures, _uses(ceiling, "ceiling.tres"), "%s: ceiling does not use ceiling.tres" % label)

		var fixture := _box(room, "Fixture", failures)
		if fixture == null:
			continue
		_expect(failures, fixture.size.is_equal_approx(Vector3(0.6, 0.08, 0.6)), "%s: fixture is %s" % [label, fixture.size])
		_expect(failures, fixture.layers == LAYER_2, "%s: fixture layers are %d, expected only layer 2 (%d)" % [label, fixture.layers, LAYER_2])
		_expect(failures, not fixture.use_collision, "%s: the fixture has collision" % label)
		_expect(failures, is_equal_approx(fixture.position.y + fixture.size.y / 2.0, WALL_HEIGHT), "%s: fixture top is at y = %.2f, it should touch the ceiling" % [label, fixture.position.y + fixture.size.y / 2.0])
		_expect(failures, _uses(fixture, "fixture.tres"), "%s: fixture does not use fixture.tres" % label)

		var light := room.get_node_or_null("RoomLight") as OmniLight3D
		if light == null:
			failures.append("%s: no RoomLight" % label)
			continue
		var farthest_corner := Vector3(CELL_SIZE / 2.0, 0.0, CELL_SIZE / 2.0)
		_expect(failures, not light.shadow_enabled, "%s: RoomLight casts shadows" % label)
		_expect(failures, light.omni_range > light.position.distance_to(farthest_corner), "%s: range %.1f m does not reach the far floor corner (%.1f m)" % [label, light.omni_range, light.position.distance_to(farthest_corner)])
		_expect(failures, is_zero_approx(light.position.x) and is_zero_approx(light.position.z), "%s: RoomLight is not over the room centre" % label)
		_expect(failures, light.position.y > PLAYER_HEIGHT and light.position.y < fixture.position.y - fixture.size.y / 2.0, "%s: RoomLight at y = %.2f is not between the head and the fixture" % [label, light.position.y])

	var lights := main.find_children("RoomLight", "OmniLight3D", true, false)
	var fixtures := main.find_children("Fixture", "CSGBox3D", true, false)
	_expect(failures, lights.size() == rooms.size(), "%d RoomLights for %d rooms" % [lights.size(), rooms.size()])
	_expect(failures, fixtures.size() == rooms.size(), "%d fixtures for %d rooms" % [fixtures.size(), rooms.size()])
	await _unload(main)
	return failures

func test_room_physics(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	for room in _rooms_of(main):
		var label := "room at %s" % room.position
		var centre := room.global_position
		# From the floor straight up: the first thing hit is the underside of the ceiling,
		# so the fixture (no collision) does not stop the ray and the ceiling does.
		var up := _ray(centre + Vector3(0.0, 0.5, 0.0), centre + Vector3(0.0, 4.0, 0.0), main)
		_expect(failures, not up.is_empty(), "%s: a ray straight up hits nothing" % label)
		if not up.is_empty():
			var hit: Vector3 = up["position"]
			_expect(failures, absf(hit.y - WALL_HEIGHT) < 0.01, "%s: the ray up stops at y = %.3f, expected 3.0" % [label, hit.y])
		# From the sky straight down: the ceiling is solid, the top is at 3.2 m.
		var down := _ray(centre + Vector3(0.0, 6.0, 0.0), centre + Vector3(0.0, 0.5, 0.0), main)
		_expect(failures, not down.is_empty() and absf((down["position"] as Vector3).y - (WALL_HEIGHT + SLAB_THICKNESS)) < 0.01, "%s: the ray down does not stop on top of the ceiling at y = 3.2" % label)

	# Wall thickness, measured on the start room's east wall, away from the doorway (z = 2.5).
	var inside := _ray(Vector3(3.0, RAY_HEIGHT, 2.5), Vector3(7.0, RAY_HEIGHT, 2.5), main)
	var outside := _ray(Vector3(7.0, RAY_HEIGHT, 2.5), Vector3(3.0, RAY_HEIGHT, 2.5), main)
	if inside.is_empty() or outside.is_empty():
		failures.append("the rays through the east wall hit nothing")
	else:
		var thickness: float = (outside["position"] as Vector3).x - (inside["position"] as Vector3).x
		_expect(failures, absf(thickness - WALL_THICKNESS) < 0.01, "the wall is %.3f m thick, expected 0.2" % thickness)
	await _unload(main)
	return failures

func test_cameras(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	var cameras := main.find_children("*", "Camera3D", true, false)
	_expect(failures, cameras.size() == 1, "%d cameras in the scene, expected 1" % cameras.size())
	if cameras.is_empty():
		await _unload(main)
		return failures
	var camera := cameras[0] as Camera3D
	if step in STEPS_WITH_PLAYER:
		_expect(failures, camera.get_parent().name == "Head", "the camera is not the player's")
		_expect(failures, (camera.cull_mask & LAYER_2) != 0, "the player camera does not render layer 2: the ceiling would be invisible")
		_expect(failures, camera.cull_mask == ALL_LAYERS, "the player camera cull mask is %d, expected all layers (%d)" % [camera.cull_mask, ALL_LAYERS])
	else:
		_expect(failures, camera.name == "OverviewCamera", "the camera is %s" % camera.name)
		_expect(failures, (camera.cull_mask & LAYER_2) == 0, "the overview camera renders layer 2: the ceiling hides the layout")
		_expect(failures, camera.cull_mask == (ALL_LAYERS & ~LAYER_2), "the overview cull mask is %d, expected all layers except layer 2 (%d)" % [camera.cull_mask, ALL_LAYERS & ~LAYER_2])
	await _unload(main)
	return failures

func test_lighting(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	var world_environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		failures.append("no WorldEnvironment with an environment")
		await _unload(main)
		return failures
	var environment := world_environment.environment
	_expect(failures, environment.background_mode == Environment.BG_SKY and environment.sky.sky_material is ProceduralSkyMaterial, "the procedural sky is gone")
	_expect(failures, environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "ambient light source is %d, expected a colour" % environment.ambient_light_source)
	var ambient := environment.ambient_light_color.srgb_to_linear().get_luminance() * environment.ambient_light_energy
	_expect(failures, ambient >= 0.3, "ambient fill %.2f is too low: corners of closed rooms go black" % ambient)
	_expect(failures, main.get_node_or_null("DirectionalLight3D") is DirectionalLight3D, "the sun is gone")
	await _unload(main)
	return failures

#endregion

#region Doors and walls (scene + physics)

func test_all_doorways_cut(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var cells := _cells_of(main)
	_expect(failures, not cells.is_empty(), "no rooms found")
	for cell in cells:
		for dir in DIRECTIONS:
			if _ray_hits_wall(cell, dir, 0.0, RAY_HEIGHT, main):
				failures.append("room %s: wall %s is closed" % [cell, dir])
	await _unload(main)
	return failures

func test_doors(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var layout: RefCounted = level.layout
	var cells: Array[Vector2i] = layout.cells
	var blocked := {}
	for cell in cells:
		for dir in DIRECTIONS:
			var hit := _ray_hits_wall(cell, dir, 0.0, RAY_HEIGHT, main)
			blocked[[cell, dir]] = hit
			var connected := _is_connected(layout, cell, cell + dir)
			if hit == connected:
				failures.append("room %s side %s: %s but data says %s" % [
					cell, dir, "closed" if hit else "open", "connected" if connected else "not connected"])
	# Both sides of a wall must agree, otherwise a door is a one-way trap.
	for cell in cells:
		for dir in DIRECTIONS:
			var key := [cell + dir, -dir]
			if blocked.has(key) and blocked[key] != blocked[[cell, dir]]:
				failures.append("rooms %s and %s disagree about the wall between them" % [cell, cell + dir])
	await _unload(main)
	return failures

func test_doorway_size() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step("step_07_debug_map")
	var level: Node3D = main.get_node("Level")
	var layout: RefCounted = level.layout
	var door: Array = layout.doors[0]
	var cell: Vector2i = door[0]
	var dir: Vector2i = door[1] - door[0]
	# [sideways offset from the doorway centre, height, expect a hit]
	var probes: Array[Array] = [
		[0.7, 2.3, false], [-0.7, 0.05, false],
		[0.9, RAY_HEIGHT, true], [-0.9, RAY_HEIGHT, true], [0.0, 2.5, true],
	]
	for probe in probes:
		var hit := _ray_hits_wall(cell, dir, probe[0], probe[1], main)
		_expect(failures, hit == probe[2], "ray at offset %.2f, height %.2f: hit is %s" % [probe[0], probe[1], hit])
	await _unload(main)
	return failures

#endregion

#region Player

func test_walk_through_doorway(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var dir := _start_direction(level.layout, true)
	var forward := Vector3(dir.x, 0.0, dir.y)
	player.rotation.y = atan2(-forward.x, -forward.z)
	var start := player.global_position
	_expect(failures, player.is_on_floor(), "player is not on the floor at the start")

	Input.action_press("move_forward")
	await _wait_physics(60)
	Input.action_release("move_forward")

	var moved := player.global_position - start
	_expect(failures, moved.dot(-player.global_basis.z) > 4.0, "moved only %.2f m along -basis.z" % moved.dot(-player.global_basis.z))
	_expect(failures, moved.dot(forward) > 4.0, "moved only %.2f m towards the open doorway" % moved.dot(forward))
	_expect(failures, absf(moved.dot(forward.cross(Vector3.UP))) < 0.1, "drifted %.2f m sideways" % moved.dot(forward.cross(Vector3.UP)))
	_expect(failures, absf(player.global_position.y) < 0.05, "left the floor (y = %.3f)" % player.global_position.y)
	await _unload(main)
	return failures

func test_walk_into_wall(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var dir := _start_direction(level.layout, false)
	var forward := Vector3(dir.x, 0.0, dir.y)
	player.rotation.y = atan2(-forward.x, -forward.z)

	Input.action_press("move_forward")
	await _wait_physics(90)
	Input.action_release("move_forward")

	# The wall's inner face is 4.9 m out and the capsule radius is 0.4 m.
	var reached := player.global_position.dot(forward)
	_expect(failures, reached > 4.3 and reached < 4.6, "stopped %.2f m from the centre" % reached)
	await _unload(main)
	return failures

func test_jump(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player

	Input.action_press("jump")
	await _wait_physics(2)
	Input.action_release("jump")
	var highest := 0.0
	for i in 30:
		await physics_frame
		highest = maxf(highest, player.global_position.y)
	_expect(failures, highest > 0.8 and highest < 1.2, "highest point %.2f m, expected about 1.03" % highest)
	_expect(failures, highest + PLAYER_HEIGHT < WALL_HEIGHT, "the jump apex (%.2f m) plus the body (%.1f m) reaches the ceiling at %.1f m" % [highest, PLAYER_HEIGHT, WALL_HEIGHT])

	await _wait_physics(60)
	_expect(failures, player.is_on_floor(), "player did not land")
	_expect(failures, absf(player.global_position.y) < 0.05, "landed at y = %.3f" % player.global_position.y)
	await _unload(main)
	return failures

func test_stick_look(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var head: Node3D = player.get_node("Head")

	# 3 rad/s for one second turns the body by about 3 rad (right is negative yaw).
	Input.action_press("look_right")
	await _wait_physics(60)
	Input.action_release("look_right")
	var turned := wrapf(-player.rotation.y, -PI, PI)
	_expect(failures, absf(turned - 3.0) < 0.15, "stick turned the body by %.2f rad in 1 s" % turned)
	_expect(failures, is_zero_approx(head.rotation.x), "yaw moved the head pitch")

	Input.action_press("look_down")
	await _wait_physics(60)
	Input.action_release("look_down")
	_expect(failures, is_equal_approx(head.rotation.x, -deg_to_rad(89.0)), "looking down: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	Input.action_press("look_up")
	await _wait_physics(120)
	Input.action_release("look_up")
	_expect(failures, is_equal_approx(head.rotation.x, deg_to_rad(89.0)), "looking up: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	_expect(failures, is_zero_approx(player.rotation.x) and is_zero_approx(player.rotation.z), "pitch tilted the body")
	await _unload(main)
	return failures

func test_mouse_look(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var head: Node3D = player.get_node("Head")
	_expect(failures, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse is not captured at start")

	await _mouse_move(Vector2(100.0, 0.0))
	_expect(failures, is_equal_approx(player.rotation.y, -0.2), "100 px right turned the body by %.3f rad, expected -0.2" % player.rotation.y)
	_expect(failures, is_zero_approx(head.rotation.x), "yaw moved the head pitch")

	await _mouse_move(Vector2(0.0, 100000.0))
	_expect(failures, is_equal_approx(head.rotation.x, -deg_to_rad(89.0)), "looking down: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	await _mouse_move(Vector2(0.0, -200000.0))
	_expect(failures, is_equal_approx(head.rotation.x, deg_to_rad(89.0)), "looking up: pitch %.1f deg" % rad_to_deg(head.rotation.x))
	_expect(failures, is_zero_approx(player.rotation.x), "pitch tilted the body")

	await _unload(main)
	return failures

func test_mouse_capture(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step)
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player

	await _key(KEY_ESCAPE)
	_expect(failures, Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Esc did not release the mouse")
	var yaw := player.rotation.y
	await _mouse_move(Vector2(100.0, 0.0))
	_expect(failures, player.rotation.y == yaw, "the view turned while the mouse was released")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	await process_frame
	_expect(failures, Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "a click did not capture the mouse")
	await _mouse_move(Vector2(100.0, 0.0))
	_expect(failures, player.rotation.y != yaw, "the view did not turn after recapturing")
	await _unload(main)
	return failures

func _start_direction(layout: RefCounted, want_open: bool) -> Vector2i:
	for dir in DIRECTIONS:
		if _is_connected(layout, Vector2i.ZERO, dir) == want_open:
			return dir
	push_error("start room has no %s side" % ("open" if want_open else "closed"))
	return Vector2i.UP

#endregion

#region Debug map and regenerate

func test_toggle_map() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step("step_07_debug_map")
	var map: Control = main.get_node("HUD/DebugMap")
	_expect(failures, map.visible, "the map does not start visible")
	_expect(failures, map.size.is_equal_approx(Vector2(280.0, 280.0)), "map size is %s" % map.size)
	await _action("toggle_debug")
	_expect(failures, not map.visible, "Tab did not hide the map")
	await _action("toggle_debug")
	_expect(failures, map.visible, "Tab did not show the map again")
	await _unload(main)
	return failures

func test_regenerate() -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step("step_07_debug_map")
	var level: Node3D = main.get_node("Level")
	var player: CharacterBody3D = level.player
	var old_cells: Array[Vector2i] = (level.layout.cells as Array[Vector2i]).duplicate()
	player.global_position = Vector3(23.0, 0.0, -17.0)

	await _action("regenerate")
	await _wait_physics(5)
	_expect(failures, level.layout_seed == 43, "seed is %d, expected 43" % level.layout_seed)
	_expect(failures, level.layout.cells == Layout.generate(43, 12).cells, "the new layout is not seed 43")
	_expect(failures, level.layout.cells != old_cells, "the layout did not change")
	_expect(failures, _room_count(level) == 12, "%d rooms in the tree after regenerating" % _room_count(level))
	_expect(failures, player.global_position.is_equal_approx(Vector3.ZERO) or player.global_position.length() < 0.1, "player is at %s, not back in the start room" % player.global_position)
	_expect(failures, player.is_on_floor(), "player is not on the floor after regenerating")

	await _action("regenerate")
	await _wait_physics(5)
	_expect(failures, level.layout_seed == 44, "second R: seed is %d, expected 44" % level.layout_seed)
	_expect(failures, _room_count(level) == 12, "%d rooms after the second regenerate" % _room_count(level))
	await _unload(main)
	return failures

func _room_count(level: Node3D) -> int:
	var count := 0
	for child in level.get_children():
		if child.has_method("open_door"):
			count += 1
	return count

#endregion

func test_scene_runs(step: String) -> Array[String]:
	var failures: Array[String] = []
	var main := await _load_step(step, false)
	for i in 30:
		await process_frame
	_expect(failures, is_instance_valid(main) and main.is_inside_tree(), "scene left the tree")
	await _unload(main)
	return failures

#region Helpers

func _report(test_name: String, failures: Array[String]) -> void:
	var script_errors := _script_errors.count - _script_errors_reported
	_script_errors_reported = _script_errors.count
	if script_errors > 0: # the test stopped at the failing line and the engine returned an empty array, which would read as a pass
		failures.insert(0, "the test stopped with a script error: see the log")
	if failures.is_empty():
		_passed += 1
		print("PASS  ", test_name)
		return
	_failed += 1
	print("FAIL  ", test_name)
	for message: String in failures.slice(0, 8):
		print("        ", message)
	if failures.size() > 8:
		print("        ... and %d more" % (failures.size() - 8))

func _skip(test_name: String, reason: String) -> void:
	_skipped += 1
	print("SKIP  ", test_name)
	print("        ", reason)

func _expect(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

## Instances a step's main scene. By default it waits until the CSG shapes have built their collision.
func _load_step(step: String, settle := true) -> Node:
	var scene: PackedScene = load("res://steps/%s/main.tscn" % step)
	var main := scene.instantiate()
	root.add_child(main)
	if settle:
		await _wait_physics(10)
	return main

func _unload(main: Node) -> void:
	Input.action_release("move_forward")
	root.remove_child(main)
	main.free()
	await process_frame

func _wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

func _is_connected(layout: RefCounted, a: Vector2i, b: Vector2i) -> bool:
	var doors: Array[Array] = layout.doors
	for door in doors:
		if (door[0] == a and door[1] == b) or (door[0] == b and door[1] == a):
			return true
	return false

## Casts a ray from a room's centre through the wall in direction dir, 0.5 m past the wall.
## sideways moves the ray along the wall, away from the doorway centre.
func _ray_hits_wall(cell: Vector2i, dir: Vector2i, sideways: float, height: float, main: Node) -> bool:
	var heading := Vector3(dir.x, 0.0, dir.y)
	var from := Vector3(cell.x * CELL_SIZE, height, cell.y * CELL_SIZE) + heading.cross(Vector3.UP) * sideways
	return not _ray(from, from + heading * (CELL_SIZE / 2.0 + 0.5), main).is_empty()

## A physics ray from one point to another that ignores the player. Empty if it hits nothing.
func _ray(from: Vector3, to: Vector3, main: Node) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var player: Node = main.get_node("Level").get("player") if main.has_node("Level") else null
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	return root.get_world_3d().direct_space_state.intersect_ray(query)

## Every room in a step's main scene: the Node3D that has a Shell.
func _rooms_of(main: Node) -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for room: Node in main.find_children("*", "Node3D", true, false):
		if room.has_node("Shell"):
			rooms.append(room as Node3D)
	return rooms

## The grid cells of every room in a step's main scene.
func _cells_of(main: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for room in _rooms_of(main):
		cells.append(Vector2i(roundi(room.global_position.x / CELL_SIZE), roundi(room.global_position.z / CELL_SIZE)))
	return cells

## How many vertices of a CSG combiner's built mesh use a material from res://materials/.
func _vertices_with_material(shell: CSGCombiner3D, file: String) -> int:
	var meshes := shell.get_meshes()
	if meshes.size() < 2 or not meshes[1] is ArrayMesh:
		return 0
	var mesh := meshes[1] as ArrayMesh
	var count := 0
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material != null and material.resource_path == MATERIAL_DIR + file:
			count += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return count

## A CSGBox3D below a room, or null plus a failure message if it is missing.
func _box(room: Node3D, path: String, failures: Array[String]) -> CSGBox3D:
	var box := room.get_node_or_null(path) as CSGBox3D
	if box == null:
		failures.append("room at %s: no CSGBox3D at %s" % [room.position, path])
	return box

## True if the shape's material is the shared one in res://materials/.
func _uses(shape: CSGBox3D, file: String) -> bool:
	return shape.material != null and shape.material.resource_path == MATERIAL_DIR + file

func _mouse_move(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = relative
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame

func _key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame

func _action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame

#endregion
