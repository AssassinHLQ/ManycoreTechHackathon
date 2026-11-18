extends SceneTree

var failures := 0
var checks := 0

const SAVE_FILES := ["user://starward_audio_test.json", "user://starward_audio_progress_test.json"]


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _cleanup_saves() -> void:
	for path in SAVE_FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	_cleanup_saves()
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = SAVE_FILES[0]
	game.progress_path = SAVE_FILES[1]
	root.add_child(game)
	await game.await_world_ready()
	var deadline_ms: int = Time.get_ticks_msec() + 180000
	while (game.planets.size() < 20 or game.world_build_remaining) \
			and Time.get_ticks_msec() < deadline_ms:
		await process_frame
	_check(game.planets.size() == 20 and not game.world_build_remaining,
		"all background world construction finishes before audio teardown")
	await process_frame
	var audio = game.audio
	_check(audio != null and audio.main_music != null and audio.attic_music != null and audio.station_music != null,
		"all scene music players are created")
	if audio == null:
		game.queue_free()
		await process_frame
		_cleanup_saves()
		quit(1)
		return
	_check(audio.main_music.stream is AudioStreamMP3 and audio.main_music.stream.loop,
		"universe music is a looping MP3")
	_check(audio.attic_music.stream is AudioStreamMP3 and audio.attic_music.stream.loop,
		"home music is a looping MP3")
	_check(audio.station_music.stream is AudioStreamMP3 and audio.station_music.stream.loop,
		"station music is a looping MP3")
	game.player._set_jetpack_audio(false)
	game.audio = null
	game.player._set_jetpack_audio(false)
	game.audio = audio
	_check(true, "player accepts the audio service being staged")
	game.start_game()
	audio._sync_scene_music()
	_check(audio.active_music == "main" and audio.main_music.playing and not audio.attic_music.playing,
		"universe context selects universe music")
	game.in_station = true
	audio._sync_scene_music()
	_check(audio.active_music == "station" and audio.station_music.playing and not audio.main_music.playing and not audio.attic_music.playing,
		"station context selects station music")
	game.in_station = false
	game.in_attic = true
	audio._sync_scene_music()
	_check(audio.active_music == "attic" and audio.attic_music.playing and not audio.station_music.playing,
		"attic context selects attic music")
	game.in_attic = false
	audio._sync_scene_music()
	_check(audio.active_music == "main" and audio.main_music.playing,
		"returning to the universe restores universe music")
	_check(audio.ambience_bus >= 0 and AudioServer.get_bus_effect_count(audio.ambience_bus) > 0,
		"ambience bus and reverb remain available for effects")
	_check(audio.distant != null and audio.distant.stream == null and not audio.distant.playing,
		"distant random ambience is removed")
	audio.play_door(Vector3(3.0, 1.0, -2.0), false)
	_check(audio.door != null and audio.door.stream == null and not audio.door.playing,
		"airlock door sound is removed")
	audio.play_ui(470.0)
	_check(audio.effects.playing, "UI sound starts on its dedicated player")
	audio._stop_audio_players()
	var all_stopped := true
	for player in [audio.distant, audio.engine, audio.jetpack, audio.roast, audio.effects,
			audio.door, audio.main_music, audio.attic_music, audio.station_music]:
		all_stopped = all_stopped and not player.playing and player.stream == null
	_check(all_stopped and audio.tone_cache.is_empty(),
		"audio shutdown stops playback and releases cached generated streams")
	game.queue_free()
	await process_frame
	await process_frame
	_cleanup_saves()
	print("AUDIO TEST COMPLETE: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
