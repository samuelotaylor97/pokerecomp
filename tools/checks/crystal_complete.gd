extends RefCounted


func run(r: RefCounted) -> void:
	var data: GameData = GameData.open(RomRegistry.CRYSTAL)
	if data == null:
		r.fail("Crystal cache is unavailable. Import the Rev 1 dump, then re-run.")
		return
	var rules := Gen2Rules.new()
	rules.content_edition = Gen2Rules.EDITION_COMPLETE
	Gen2CrystalComplete.sync(data, rules)
	var result := Gen2CompleteCoverage.assess(data, rules)
	if bool(result.get("proven", false)):
		return
	var missing: Array = result.get("missing", [])
	r.fail("Crystal Complete left %d species unobtainable." % missing.size())
