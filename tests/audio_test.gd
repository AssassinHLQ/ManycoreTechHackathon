extends SceneTree

var failures := 0


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		push_error("FAIL  " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_path = "user://starward_audio_test.json"
	root.add_child(game)
	await game.await_world_ready()
	await process_frame
	game.start_game()
	for i in range(6):
		await physics_frame
	var audio = game.audio
	for kind in audio.DISTANT_KINDS:
		var stream: AudioStreamWAV = audio._distant_stream(kind)
		print("  ", kind, " len=", stream.get_length(), " stereo=", stream.stereo, " bytes=", stream.data.size())
	print("AMBIENCE_LEN=", audio.ambience.stream.get_length(), " ROOM_LEN=", audio.room_tone.stream.get_length(), " WIND_LEN=", audio.surface_wind.stream.get_length())
	print("BUS=", audio.ambience_bus, " effects=", AudioServer.get_bus_effect_count(audio.ambience_bus), " name=", AudioServer.get_bus_name(audio.ambience_bus))
	_check(audio.ambience != null and audio.ambience.stream.get_length() > 10.0, "deep-space bed is a long loop")
	_check(audio.room_tone != null and audio.room_tone.stream.get_length() > 5.0, "station room tone exists")
	_check(audio.surface_wind != null and audio.surface_wind.stream.get_length() > 5.0, "surface wind exists")
	_check(audio.DISTANT_KINDS.size() >= 4, "distant one-shot variants exist")
	_check(audio.ambience_bus >= 0 and AudioServer.get_bus_effect_count(audio.ambience_bus) > 0, "ambience reverb bus exists")
	game.in_station = true
	audio._update_environment()
	_check(audio.room_target > -30.0 and audio.wind_target < -40.0, "station selects room tone")
	game.in_station = false
	game.state = "walk"
	audio._update_environment()
	_check(audio.wind_target > -40.0, "planet walk selects wind")
	game.state = "ship"
	audio._update_environment()
	_check(audio.ambience_target > -20.0, "ship selects deep-space bed")
	audio.distant_timer = 0.0
	await process_frame
	await process_frame
	_check(audio.distant.stream != null, "distant event stream assigned")
	_check(audio.door != null and audio.door is AudioStreamPlayer3D, "hub door has a positional effect player")
	audio.play_door(Vector3(3.0, 1.0, -2.0), false)
	var close_stream: AudioStreamWAV = audio.door.stream
	_check(close_stream != null and close_stream.get_length() > 0.5, "closing door builds a servo one-shot")
	_check(close_stream.data.size() > 20000, "door one-shot carries real samples")
	_check(close_stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "door one-shot does not loop")
	audio.play_door(Vector3(3.0, 1.0, -2.0), true)
	_check(audio.door.stream != close_stream, "opening and closing use separate door variants")
	_check(audio.door.global_position.is_equal_approx(Vector3(3.0, 1.0, -2.0)), "door sound is placed at the door frame")
	_check(audio.door.max_distance > 20.0 and audio.door.unit_size > 0.0, "door sound attenuates with distance")
	game.queue_free()
	await process_frame
	if FileAccess.file_exists("user://starward_audio_test.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://starward_audio_test.json"))
	print("AUDIO TEST COMPLETE: ", failures, " failure(s)")
	quit(0 if failures == 0 else 1)
