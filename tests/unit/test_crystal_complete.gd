extends GutTest

const SHA1: String = "f2f52230b536214ef7c9924f483392993e226cfb"


func before_each() -> void:
	Gen2ContentOverlay.reset()


func after_each() -> void:
	Gen2ContentOverlay.reset()
	Gen2WorldProgression.reset()
	var runtime := Gen2GameRuntime.instance()
	if runtime != null:
		runtime.take_pending_new_game()


func test_registry_crystal_sha1_matches_the_pc_candidate() -> void:
	assert_eq(RomRegistry.sha1_for(RomRegistry.CRYSTAL), SHA1)
	assert_eq(RomRegistry.lookup(SHA1)["id"], RomRegistry.CRYSTAL)
	assert_true(bool(RomRegistry.lookup(SHA1)["playable"]))


func test_a_missing_edition_stays_vanilla_and_is_not_written() -> void:
	var parsed := Gen2Rules.parse({"mode": "current", "challenge": "hard", "flags": {}})
	assert_false(parsed.is_complete())
	var fresh := Gen2Rules.new()
	assert_false(fresh.to_dict().has("content_edition"))
	fresh.content_edition = Gen2Rules.EDITION_COMPLETE
	var round := Gen2Rules.parse(fresh.to_dict())
	assert_true(round.is_complete())
	assert_true(round.matches(fresh))


func test_complete_is_crystal_only_and_roamers_keep_suicune() -> void:
	var complete := Gen2Rules.new()
	complete.content_edition = Gen2Rules.EDITION_COMPLETE
	var crystal := GameData.new()
	crystal.id = RomRegistry.CRYSTAL
	var gold := GameData.new()
	gold.id = RomRegistry.GOLD
	assert_true(Gen2CrystalComplete.roamer_stays(complete, crystal, 243))
	assert_true(Gen2CrystalComplete.roamer_stays(complete, crystal, 244))
	assert_false(Gen2CrystalComplete.roamer_stays(complete, crystal, 245))
	assert_false(Gen2CrystalComplete.roamer_stays(complete, gold, 243))
	assert_false(Gen2CrystalComplete.roamer_stays(Gen2Rules.new(), crystal, 243))
	var runtime := Gen2GameRuntime.instance()
	runtime.begin_new_game(RomRegistry.CRYSTAL, 1, "Complete", Gen2Rules.CHALLENGE_VANILLA, Gen2Rules.EDITION_COMPLETE)
	assert_eq(runtime.take_pending_new_game()["edition"], Gen2Rules.EDITION_COMPLETE)
	runtime.begin_new_game(RomRegistry.GOLD, 1, "Gold", Gen2Rules.CHALLENGE_VANILLA, Gen2Rules.EDITION_COMPLETE)
	assert_eq(runtime.take_pending_new_game()["edition"], Gen2Rules.EDITION_VANILLA)
	var save := Gen2SaveData.new()
	save.game_id = RomRegistry.GOLD
	runtime.announce_new_save(save, Gen2Rules.CHALLENGE_VANILLA, Gen2Rules.EDITION_COMPLETE)
	assert_false(save.run_rules.is_complete())
	save.game_id = RomRegistry.CRYSTAL
	runtime.announce_new_save(save, Gen2Rules.CHALLENGE_HARD, Gen2Rules.EDITION_COMPLETE)
	assert_true(save.run_rules.is_complete())
	assert_eq(save.run_rules.challenge, Gen2Rules.CHALLENGE_HARD)


func test_complete_patches_one_cache_and_leaves_the_others_vanilla() -> void:
	var directory := _write_cache()
	var vanilla := GameData.open_directory(directory)
	var complete_data := GameData.open_directory(directory)
	var manifest: Dictionary = RomCache.read_manifest(directory)
	manifest["game_id"] = "gold"
	RomCache.write_json(RomCache.manifest_path(directory), manifest)
	var gold := GameData.open_directory(directory)
	var rules := Gen2Rules.new()
	rules.content_edition = Gen2Rules.EDITION_COMPLETE
	Gen2CrystalComplete.sync(complete_data, rules)
	assert_true(complete_data.edition_attached)
	assert_ne(complete_data.content_overlay(), Gen2ContentOverlay.shared())
	assert_eq(vanilla.content_overlay(), Gen2ContentOverlay.shared())
	assert_eq(_method(complete_data, 1), Gen2Layout.EVOLVE_LEVEL)
	assert_eq(_held(complete_data, 1), 0)
	assert_eq(_method(vanilla, 1), Gen2Layout.EVOLVE_TRADE)
	assert_eq(_method(gold, 1), Gen2Layout.EVOLVE_TRADE)
	assert_false(gold.edition_attached)
	Gen2CrystalComplete.sync(gold, rules)
	assert_eq(_method(gold, 1), Gen2Layout.EVOLVE_TRADE)
	var slow := _row(complete_data, 3, 0x52)
	assert_eq(int(slow["method"]), Gen2Layout.EVOLVE_LEVEL)
	assert_eq(int(slow["parameter"]), 36)
	assert_eq(int(slow["target"]), 1)
	var bro := _row(complete_data, 3, 0)
	assert_eq(int(bro["method"]), Gen2Layout.EVOLVE_LEVEL)
	assert_eq(int(bro["parameter"]), 37)
	assert_eq(int(bro["target"]), 2)
	var held := Gen2BattleMon.create(complete_data, 3, 36, [])
	held.item = 0x52
	var evolved := Gen2Evolution.level_evolution(held.data, held, 0)
	assert_eq(int(evolved.get("target", 0)), 1)
	assert_eq(int(evolved.get("consumes_held_item", 0)), 0x52)
	var plain := Gen2BattleMon.create(complete_data, 3, 37, [])
	var slowbro := Gen2Evolution.level_evolution(plain.data, plain, 0)
	assert_eq(int(slowbro.get("target", 0)), 2)
	assert_false(slowbro.has("consumes_held_item"))
	assert_true(complete_data.world_mart(0).get("items", []).has(0x8F))
	assert_false(vanilla.world_mart(0).get("items", []).has(0x8F))
	assert_false(gold.world_mart(0).get("items", []).has(0x8F))
	var later := GameData.open_directory(directory)
	manifest["game_id"] = "crystal"
	RomCache.write_json(RomCache.manifest_path(directory), manifest)
	later = GameData.open_directory(directory)
	assert_eq(_method(later, 1), Gen2Layout.EVOLVE_TRADE)
	assert_eq(_method(complete_data, 1), Gen2Layout.EVOLVE_LEVEL)
	Gen2CrystalComplete.sync(complete_data, Gen2Rules.new())
	assert_false(complete_data.edition_attached)
	assert_eq(_method(complete_data, 1), Gen2Layout.EVOLVE_TRADE)
	assert_eq(_method(vanilla, 1), Gen2Layout.EVOLVE_TRADE)
	RomCache.clear(directory)


func test_unknown_maps_fail_and_landed_species_come_from_the_cache() -> void:
	var directory := _write_cache()
	var data := GameData.open_directory(directory)
	var rules := Gen2Rules.new()
	rules.content_edition = Gen2Rules.EDITION_COMPLETE
	Gen2CrystalComplete.sync(data, rules)
	var errors := "\n".join(data.edition_landing_errors)
	assert_string_contains(errors, "ROUTE_26")
	assert_false(errors.contains("SILVER_CAVE_OUTSIDE is not in this cache"))
	assert_false(errors.contains("ILEX_FOREST is not in this cache"))
	var grass: Dictionary = data.world_encounter(&"grass", 2, 5)
	var found: Dictionary = {}
	_note(grass.get("slots", []), found)
	assert_true(found.has(152))
	assert_false(found.has(7))
	var mew := _static(data, "mew")
	var celebi := _static(data, "celebi")
	assert_eq(int(mew["species"]), 151)
	assert_eq(int(celebi["species"]), 251)
	assert_eq(String(mew["map"]), "SILVER_CAVE_OUTSIDE")
	assert_eq(String(celebi["map"]), "ILEX_FOREST")
	assert_gt(int((mew["cell"] as Vector2i).x), -1)
	var covered := Gen2CompleteCoverage.assess(data, rules)
	assert_false(bool(covered["proven"]))
	var methods: Dictionary = covered["methods"]
	assert_string_contains(String(methods.get(152, "")), "grass")
	assert_string_contains(String(methods.get(151, "")), "static")
	assert_string_contains(String(methods.get(251, "")), "static")
	assert_false(methods.has(7))
	assert_true((covered["missing"] as Array).has(3))
	RomCache.clear(directory)


func _write_cache() -> String:
	var directory := RomCache.directory_for(&"crystalcomplete", SHA1)
	RomCache.clear(directory)
	RomCache.prepare(directory)
	var species: Array = []
	for number: int in range(1, 4):
		species.append(_species(number))
	RomCache.write_json(RomCache.species_path(directory), species)
	RomCache.write_json(RomCache.world_marts_path(directory), {
		"marts": [{"index": 0, "items": [1]}], "default": {"items": []}, "special": {},
	})
	var slot := {"species": 1, "level": 10}
	var day: Array = []
	for _index: int in 7:
		day.append(slot.duplicate())
	RomCache.write_json(RomCache.world_encounters_path(directory), {
		"grass": {"2:5": {"map": "2:5", "rate": 10, "rates": [10, 10, 10], "slots": [day, day, day]}},
	})
	var collision := [0, 0, 0, 0]
	RomCache.write_json(RomCache.world_maps_path(directory), [
		_map(2, 5, collision), _map(3, 52, collision), _map(19, 2, collision),
	])
	RomCache.write_json(RomCache.manifest_path(directory), {
		"format_version": RomCache.FORMAT_VERSION,
		"complete": true,
		"game_id": "crystal",
		"sha1": SHA1,
		"generation": RomRegistry.GEN2,
	})
	return directory


func _species(number: int) -> Dictionary:
	var evolutions: Array = []
	if number == 1:
		evolutions.append({
			"method": Gen2Layout.EVOLVE_TRADE, "parameter": 0xFF, "condition": 0, "target": 2,
		})
	elif number == 3:
		evolutions.append({
			"method": Gen2Layout.EVOLVE_LEVEL, "parameter": 37, "condition": 0, "target": 2,
		})
		evolutions.append({
			"method": Gen2Layout.EVOLVE_TRADE, "parameter": 0x52, "condition": 0, "target": 1,
		})
	return {"number": number, "name": "MON%d" % number, "evolutions": evolutions}


func _map(group: int, number: int, collision: Array) -> Dictionary:
	return {
		"group": group, "number": number, "tileset": 0,
		"width_blocks": 1, "height_blocks": 1,
		"collision_width": 2, "collision_height": 2, "collision": collision,
		"blocks": [0],
	}


func _method(data: GameData, species: int) -> int:
	return int(data.evolutions(species)[0]["method"])


func _held(data: GameData, species: int) -> int:
	return int(data.evolutions(species)[0]["held_item"])


func _row(data: GameData, species: int, held: int) -> Dictionary:
	for row: Dictionary in data.evolutions(species):
		if int(row.get("held_item", 0)) == held and int(row.get("parameter", 0)) == (36 if held != 0 else 37):
			return row
	return {}


func _static(data: GameData, static_id: String) -> Dictionary:
	for row: Dictionary in data.edition_statics:
		if String(row.get("id", "")) == static_id:
			return row
	return {}


func _note(value: Variant, found: Dictionary) -> void:
	if value is Dictionary and (value as Dictionary).has("species"):
		found[int((value as Dictionary)["species"])] = true
	elif value is Array:
		for entry: Variant in value as Array:
			_note(entry, found)
