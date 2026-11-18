extends SceneTree

class MusicContext:
	extends RefCounted
	var state := "menu"
	var in_station := false
	var in_attic := false
	var paused := false

var checks := 0
var failures := 0
var audio
var context := MusicContext.new()


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)


func _run() -> void:
	audio = load("res://scripts/audio.gd").new()
	audio.game = context
	root.add_child(audio)
	await process_frame
	_check(audio.active_music == "main" and audio.main_music.playing, "menu starts the main score")
	_check(audio.main_music.stream is AudioStreamMP3 and audio.main_music.stream.loop, "main score is an imported looping MP3")

	context.state = "walk"
	await process_frame
	_check(audio.active_music == "main", "planetary walking keeps the main score")
	context.state = "ship"
	await process_frame
	_check(audio.active_music == "main", "spaceflight keeps the main score")

	context.in_station = true
	await process_frame
	_check(audio.active_music == "attic" and audio.attic_music.playing, "station switches to the Chopin score")
	context.in_station = false
	context.in_attic = true
	await process_frame
	_check(audio.active_music == "attic", "attic shares the station score")

	context.state = "dying"
	audio.fade_music_for_death()
	await create_timer(audio.MUSIC_FADE_OUT_SECONDS + 0.25).timeout
	_check(not audio.attic_music.playing, "death fades and stops the current score")

	context.in_attic = false
	context.state = "walk"
	audio.restart_music_for_new_life()
	_check(audio.active_music == "main" and audio.main_music.playing, "rebirth restarts the main score")
	_check(audio.main_music.get_playback_position() < 0.5, "rebirth starts from the beginning")

	print("AUDIO MUSIC: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
