extends Node

var game
var distant: AudioStreamPlayer
var engine: AudioStreamPlayer
var jetpack: AudioStreamPlayer
var roast: AudioStreamPlayer
var effects: AudioStreamPlayer
var door: AudioStreamPlayer3D
var main_music: AudioStreamPlayer
var attic_music: AudioStreamPlayer
var station_music: AudioStreamPlayer
var active_music := ""
var music_fade: Tween
var death_fade_active := false
var engine_target := -48.0
var jetpack_target := -48.0
var roast_target := -48.0
var ambience_bus := -1
var tone_cache: Dictionary = {}

const MAIN_MUSIC_DB := -17.0
const MUSIC_FADE_OUT_SECONDS := 3.0


func _ready() -> void:
	_ensure_ambience_bus()
	# 保留无声占位节点，兼容旧的场景和测试访问，不再绑定任何音频资源。
	distant = AudioStreamPlayer.new()
	add_child(distant)
	engine = _player(_engine_stream(), -48.0)
	jetpack = _player(_noise_stream(), -48.0)
	roast = _player(_crackle_stream(), -48.0)
	main_music = AudioStreamPlayer.new()
	var main_stream := load("res://assets/audio/borodin_string_quartet_2_allegro_moderato.mp3") as AudioStreamMP3
	if main_stream != null:
		main_stream.loop = true
		main_music.stream = main_stream
	main_music.volume_db = MAIN_MUSIC_DB
	add_child(main_music)
	attic_music = AudioStreamPlayer.new()
	var music_stream := load("res://assets/audio/chopin_waltz_op70_no3.mp3") as AudioStreamMP3
	if music_stream != null:
		music_stream.loop = true
		attic_music.stream = music_stream
	attic_music.volume_db = -17.0
	add_child(attic_music)
	station_music = AudioStreamPlayer.new()
	var station_stream := load("res://assets/audio/chopin_prelude_op28_no6_tolling_bells.mp3") as AudioStreamMP3
	if station_stream != null:
		station_stream.loop = true
		station_music.stream = station_stream
		station_music.volume_db = -17.0
		add_child(station_music)
	effects = AudioStreamPlayer.new()
	effects.volume_db = -7.0
	add_child(effects)
	# 保留无声占位节点，气闸门不再播放任何音效。
	door = AudioStreamPlayer3D.new()
	add_child(door)


func _exit_tree() -> void:
	_stop_audio_players()


func _stop_audio_players() -> void:
	if music_fade != null and music_fade.is_running():
		music_fade.kill()
	for player in [distant, engine, jetpack, roast, effects, door, main_music, attic_music, station_music]:
		if player == null or not is_instance_valid(player):
			continue
		player.stop()
		player.stream = null
	tone_cache.clear()
	active_music = ""
	death_fade_active = false


func _ensure_ambience_bus() -> void:
	ambience_bus = AudioServer.get_bus_index("Ambience")
	if ambience_bus == -1:
		AudioServer.add_bus()
		ambience_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(ambience_bus, "Ambience")
		AudioServer.set_bus_send(ambience_bus, "Master")
	if AudioServer.get_bus_effect_count(ambience_bus) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.92
		reverb.damping = 0.48
		reverb.wet = 0.35
		reverb.dry = 0.82
		reverb.spread = 1.0
		AudioServer.add_bus_effect(ambience_bus, reverb)
	AudioServer.set_bus_volume_db(ambience_bus, -2.0)


func _player(stream: AudioStreamWAV, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	player.play()
	return player


func _process(delta: float) -> void:
	_sync_scene_music()
	if engine != null:
		engine.volume_db = lerpf(engine.volume_db, engine_target, 1.0 - exp(-delta * 6.0))
	if jetpack != null:
		jetpack.volume_db = lerpf(jetpack.volume_db, jetpack_target, 1.0 - exp(-delta * 8.0))
	if roast != null:
		roast.volume_db = lerpf(roast.volume_db, roast_target, 1.0 - exp(-delta * 5.0))


func _context_music() -> String:
	if game != null and game.in_station:
		return "station"
	if game != null and game.in_attic:
		return "attic"
	return "main"


func _music_player(track: String) -> AudioStreamPlayer:
	if track == "station":
		return station_music
	return attic_music if track == "attic" else main_music


func _sync_scene_music() -> void:
	if game == null or game.state in ["dying", "supernova", "end"]:
		return
	var desired := _context_music()
	if desired == active_music and _music_player(desired).playing:
		return
	_start_music(desired, false)


func _start_music(track: String, restart: bool) -> void:
	if music_fade != null and music_fade.is_running():
		music_fade.kill()
	death_fade_active = false
	var player := _music_player(track)
	if active_music != track:
		main_music.stop()
		attic_music.stop()
		station_music.stop()
		active_music = track
	if restart or not player.playing:
		player.volume_db = MAIN_MUSIC_DB
		player.play(0.0)
	else:
		player.volume_db = MAIN_MUSIC_DB


func fade_music_for_death() -> void:
	var player := _music_player(active_music) if active_music != "" else null
	if player == null or not player.playing or death_fade_active:
		return
	death_fade_active = true
	if music_fade != null and music_fade.is_running():
		music_fade.kill()
	music_fade = create_tween()
	music_fade.tween_property(player, "volume_db", -60.0, MUSIC_FADE_OUT_SECONDS)
	music_fade.finished.connect(func():
		if game != null and game.state in ["dying", "supernova"]:
			player.stop()
			active_music = ""
		death_fade_active = false
	)


func restart_music_for_new_life() -> void:
	_start_music(_context_music(), true)


func set_engine(active: bool, level: float) -> void:
	engine_target = (-20.0 + level * 5.0) if active else -48.0
	engine.pitch_scale = 0.82 + level * 0.6


func set_jetpack(active: bool) -> void:
	if jetpack == null:
		return
	jetpack_target = -20.0 if active else -48.0
	if active:
		if not jetpack.playing:
			jetpack.play()
	else:
		jetpack.stop()


func set_roast(active: bool, intensity := 0.0) -> void:
	roast_target = (-27.0 + clampf(intensity, 0.0, 1.0) * 8.0) if active else -48.0
	if roast != null:
		roast.pitch_scale = 0.9 + clampf(intensity, 0.0, 1.0) * 0.35


func play_ui(frequency := 440.0) -> void:
	var key := "ui_%d" % int(frequency)
	if not tone_cache.has(key):
		tone_cache[key] = _tone_stream(frequency, 0.18, false)
	effects.stream = tone_cache[key]
	effects.volume_db = -12.0
	effects.play()


func play_chime() -> void:
	if not tone_cache.has("chime"):
		tone_cache["chime"] = _tone_stream(440.0, 1.8, true)
	effects.stream = tone_cache["chime"]
	effects.volume_db = -6.0
	effects.play()


func play_attic_music() -> void:
	_start_music("attic", false)


func stop_attic_music() -> void:
	if attic_music != null:
		attic_music.stop()
		if active_music == "attic":
			active_music = ""


func play_impact() -> void:
	if not tone_cache.has("impact"):
		tone_cache["impact"] = _tone_stream(65.0, 0.5, false)
	effects.stream = tone_cache["impact"]
	effects.volume_db = -2.0
	effects.play()


func play_supernova() -> void:
	if not tone_cache.has("supernova"):
		tone_cache["supernova"] = _tone_stream(48.0, 3.2, true)
	effects.stream = tone_cache["supernova"]
	effects.volume_db = 0.0
	effects.play()


func play_door(world_position: Vector3, opening: bool) -> void:
	# 气闸门保留接口，实际不再播放声音。
	return


func _engine_stream() -> AudioStreamWAV:
	var rate := 22050
	var frames := rate
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var filtered := 0.0
	for i in range(frames):
		var t := float(i) / rate
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.08)
		var sample := sin(TAU * 60.0 * t) * 0.28 + sin(TAU * 120.0 * t) * 0.12 + filtered * 0.25
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav(data, rate, frames)


func _crackle_stream() -> AudioStreamWAV:
	var rate := 22050
	var frames := int(1.6 * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var filtered := 0.0
	var pop := 0.0
	for i in range(frames):
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.22)
		if rng.randf() < 0.0028:
			pop = rng.randf_range(0.35, 0.9)
		pop *= 0.94
		var sample := filtered * 0.10 + pop * rng.randf_range(-1.0, 1.0) * 0.5
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav(data, rate, frames)


func _noise_stream() -> AudioStreamWAV:
	var rate := 22050
	var frames := rate
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 771
	var filtered := 0.0
	for i in range(frames):
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.18)
		data.encode_s16(i * 2, int(filtered * 0.55 * 32767.0))
	return _wav(data, rate, frames)


func _tone_stream(frequency: float, duration: float, chord: bool) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / rate
		var envelope := exp(-t * 4.0 / maxf(duration, 0.1)) * minf(t * 35.0, 1.0)
		var sample := sin(TAU * frequency * t) * 0.36
		if chord:
			sample += sin(TAU * frequency * 1.25 * t) * 0.19
			sample += sin(TAU * frequency * 1.5 * t) * 0.14
		data.encode_s16(i * 2, int(clampf(sample * envelope, -1.0, 1.0) * 32767.0))
	var stream := _wav(data, rate, frames)
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _wav(data: PackedByteArray, rate: int, frames: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream
