extends Node

const AMBIENT_RATE := 8000
# 远距单发：只登记种类，样本在第一次真的播时再合成（启动阶段不为它们付逐样本合成的钱）。
const DISTANT_KINDS := ["ping", "creak", "radio", "moan"]
const DISTANT_PANS := {"ping": -0.55, "creak": -0.32, "radio": 0.38, "moan": 0.12}

var game
var ambience: AudioStreamPlayer
var room_tone: AudioStreamPlayer
var surface_wind: AudioStreamPlayer
var distant: AudioStreamPlayer
var engine: AudioStreamPlayer
var jetpack: AudioStreamPlayer
var roast: AudioStreamPlayer
var effects: AudioStreamPlayer
var door: AudioStreamPlayer3D
var door_rng := RandomNumberGenerator.new()
var engine_target := -48.0
var jetpack_target := -48.0
var roast_target := -48.0
var ambience_target := -16.0
var room_target := -48.0
var wind_target := -48.0
var distant_timer := 7.0
var distant_rng := RandomNumberGenerator.new()
var ambience_bus := -1
var tone_cache: Dictionary = {}


func _ready() -> void:
	_ensure_ambience_bus()
	ambience = _player(_void_stream(), -16.0)
	room_tone = _player(_room_stream(), -48.0)
	surface_wind = _player(_wind_stream(), -48.0)
	ambience.bus = "Ambience"
	distant_rng.seed = 20261102
	distant = AudioStreamPlayer.new()
	distant.volume_db = -18.0
	distant.bus = "Ambience"
	add_child(distant)
	engine = _player(_engine_stream(), -48.0)
	jetpack = _player(_noise_stream(), -48.0)
	roast = _player(_crackle_stream(), -48.0)
	effects = AudioStreamPlayer.new()
	effects.volume_db = -7.0
	add_child(effects)
	# 放气门是站内唯一的位置音源：走近才响，隔着枢纽会衰减。
	door = AudioStreamPlayer3D.new()
	door.bus = "Ambience"
	door.volume_db = -7.0
	door.unit_size = 9.0
	door.max_distance = 46.0
	door.max_polyphony = 3
	door.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	door.attenuation_filter_cutoff_hz = 9000.0
	add_child(door)
	door_rng.seed = 20261103


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
	_update_environment()
	ambience.volume_db = lerpf(ambience.volume_db, ambience_target, 1.0 - exp(-delta * 0.55))
	room_tone.volume_db = lerpf(room_tone.volume_db, room_target, 1.0 - exp(-delta * 1.4))
	surface_wind.volume_db = lerpf(surface_wind.volume_db, wind_target, 1.0 - exp(-delta * 0.8))
	_update_distant(delta)
	if engine != null:
		engine.volume_db = lerpf(engine.volume_db, engine_target, 1.0 - exp(-delta * 6.0))
	if jetpack != null:
		jetpack.volume_db = lerpf(jetpack.volume_db, jetpack_target, 1.0 - exp(-delta * 8.0))
	if roast != null:
		roast.volume_db = lerpf(roast.volume_db, roast_target, 1.0 - exp(-delta * 5.0))


func _update_environment() -> void:
	if game == null:
		return
	var in_station: bool = game.in_station
	var walking: bool = game.state == "walk" and not in_station
	if in_station:
		ambience_target = -25.0
		room_target = -19.0
		wind_target = -48.0
	elif walking:
		ambience_target = -21.0
		room_target = -48.0
		wind_target = -27.0
	else:
		ambience_target = -16.0
		room_target = -48.0
		wind_target = -48.0


func _update_distant(delta: float) -> void:
	if game == null or game.paused:
		return
	distant_timer -= delta
	if distant_timer > 0.0:
		return
	_play_distant()
	var in_station: bool = game.in_station
	distant_timer = distant_rng.randf_range(18.0, 38.0) if in_station else distant_rng.randf_range(13.0, 31.0)


func _distant_stream(kind: String) -> AudioStreamWAV:
	var key := "distant_" + kind
	if not tone_cache.has(key):
		match kind:
			"ping":
				tone_cache[key] = _ping_stream(DISTANT_PANS["ping"], 700.0)
			"creak":
				tone_cache[key] = _creak_stream(DISTANT_PANS["creak"])
			"radio":
				tone_cache[key] = _radio_stream(DISTANT_PANS["radio"])
			_:
				tone_cache[key] = _moan_stream(DISTANT_PANS["moan"])
	return tone_cache[key]


func _play_distant() -> void:
	var in_station: bool = game.in_station
	var walking: bool = game.state == "walk" and not in_station
	var allowed: Array = []
	for kind in DISTANT_KINDS:
		if (in_station or walking) and kind == "ping":
			continue
		allowed.append(kind)
	if allowed.is_empty():
		allowed = DISTANT_KINDS.duplicate()
	var kind: String = allowed[distant_rng.randi_range(0, allowed.size() - 1)]
	distant.stream = _distant_stream(kind)
	distant.volume_db = -23.0 if (in_station or walking) else -18.0
	distant.pitch_scale = distant_rng.randf_range(0.93, 1.07)
	distant.play()


func set_engine(active: bool, level: float) -> void:
	engine_target = (-20.0 + level * 5.0) if active else -48.0
	engine.pitch_scale = 0.82 + level * 0.6


func set_jetpack(active: bool) -> void:
	jetpack_target = -20.0 if active else -48.0


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
	if door == null:
		return
	var key := "door_open" if opening else "door_close"
	if not tone_cache.has(key):
		tone_cache[key] = _door_stream(opening)
	door.stream = tone_cache[key]
	door.global_position = world_position
	door.pitch_scale = door_rng.randf_range(0.95, 1.06)
	door.volume_db = -7.0 + door_rng.randf_range(-2.0, 1.0)
	door.play()


func _door_stream(opening: bool) -> AudioStreamWAV:
	# 放气门：泄压嘶声 + 门扇滑行的电机低鸣与伺服扫频 + 到位顿挫。
	var rate := 22050
	var duration := 1.05
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6151 if opening else 6152
	var air := 0.0
	var rumble := 0.0
	var phase := 0.0
	var slide_start := 0.06
	var slide_span := 0.58
	var stop_time := slide_start + slide_span
	for i in range(frames):
		var t := float(i) / rate
		air = lerpf(air, rng.randf_range(-1.0, 1.0), 0.5)
		var seal := minf(t * 60.0, 1.0) * exp(-maxf(t - 0.012, 0.0) * 20.0)
		var sample := air * 0.20 * seal
		var slide := 0.0
		var progress := 0.0
		if t > slide_start and t < stop_time:
			progress = (t - slide_start) / slide_span
			slide = minf((t - slide_start) * 14.0, 1.0) * minf((stop_time - t) * 14.0, 1.0)
		rumble = lerpf(rumble, rng.randf_range(-1.0, 1.0), 0.045)
		var sweep: float = progress if opening else 1.0 - progress
		var frequency := lerpf(212.0, 388.0, sweep)
		phase += TAU * frequency * (1.0 + 0.02 * sin(TAU * 8.5 * t)) / rate
		var motor := 0.8 + 0.2 * sin(TAU * 27.0 * t)
		sample += rumble * 0.16 * slide * motor
		sample += sin(phase) * 0.11 * slide * motor
		sample += sin(phase * 2.0 + 0.6) * 0.035 * slide
		if t > stop_time:
			var u := t - stop_time
			var thud := 0.34 if opening else 0.40
			sample += sin(TAU * 74.0 * u) * thud * exp(-u * 24.0)
			sample += sin(TAU * 1180.0 * u + 0.4) * 0.05 * exp(-u * 34.0)
			sample += rng.randf_range(-1.0, 1.0) * 0.04 * exp(-u * 30.0)
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := _wav(data, rate, frames)
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _void_stream() -> AudioStreamWAV:
	var rate := AMBIENT_RATE
	var duration := 12.0
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / rate
		var swell := 0.62 + 0.2 * sin(TAU * t / duration) + 0.08 * sin(TAU * 3.0 * t / duration + 1.1)
		var shimmer := 0.5 + 0.5 * sin(TAU * 2.0 * t / duration + 0.7)
		var sample := sin(TAU * 36.0 * t) * 0.16
		sample += sin(TAU * 36.5 * t + 0.4) * 0.12
		sample += sin(TAU * 54.0 * t + 1.1) * 0.07
		sample += sin(TAU * 55.0 * t) * 0.06
		sample += sin(TAU * 39.0 * t + 2.2) * 0.05
		sample += sin(TAU * 81.0 * t) * 0.028
		sample += sin(TAU * 82.5 * t + 0.8) * 0.04
		sample += sin(TAU * 108.0 * t + 0.3) * 0.012
		sample += sin(TAU * 110.0 * t + 1.7) * 0.03
		sample += sin(TAU * 165.0 * t) * 0.015
		sample += sin(TAU * 220.0 * t) * 0.008 * shimmer
		sample += sin(TAU * 233.0 * t + 0.9) * 0.006 * shimmer
		sample += sin(TAU * 440.0 * t) * 0.012 * shimmer
		sample += sin(TAU * 660.0 * t + 0.7) * 0.006 * shimmer
		sample += sin(TAU * 880.0 * t + 1.4) * 0.004 * shimmer
		sample *= swell
		data.encode_s16(i * 2, int(clampf(sample * 0.9, -1.0, 1.0) * 32767.0))
	return _wav(data, rate, frames)


func _room_stream() -> AudioStreamWAV:
	var rate := AMBIENT_RATE
	var duration := 6.0
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / rate
		var air := 0.5 + 0.5 * sin(TAU * 4.0 * t / duration)
		var sample := sin(TAU * 50.0 * t) * 0.12
		sample += sin(TAU * 100.0 * t + 0.4) * 0.045
		sample += sin(TAU * 150.0 * t) * 0.02
		sample += sin(TAU * 180.0 * t + 1.2) * 0.006 * air
		sample += sin(TAU * 300.0 * t + 0.6) * 0.004 * air
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav(data, rate, frames)


func _wind_stream() -> AudioStreamWAV:
	var rate := AMBIENT_RATE
	var duration := 6.0
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501
	var filtered := 0.0
	for i in range(frames):
		var t := float(i) / rate
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.035)
		var gust := 0.35 + 0.3 * (0.5 - 0.5 * cos(TAU * t / duration)) + 0.12 * sin(TAU * 3.0 * t / duration)
		var sample := filtered * 0.18 * gust
		sample += sin(TAU * 420.0 * t) * 0.004 * gust
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	return _wav(data, rate, frames)


func _pan_gains(pan: float) -> Vector2:
	var p := clampf(pan, -1.0, 1.0)
	return Vector2(sqrt(0.5 * (1.0 - p)), sqrt(0.5 * (1.0 + p)))


func _stereo_wav(data: PackedByteArray, rate: int, frames: int) -> AudioStreamWAV:
	var stream := _wav(data, rate, frames)
	stream.stereo = true
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _ping_stream(pan: float, base := 700.0) -> AudioStreamWAV:
	var rate := AMBIENT_RATE
	var duration := 3.6
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 4)
	var gains := _pan_gains(pan)
	for i in range(frames):
		var t := float(i) / rate
		var sample := 0.0
		for echo_index in range(3):
			var start := float(echo_index) * 0.55
			if t >= start:
				var u := t - start
				var envelope := exp(-u * 1.25) * minf(u * 28.0, 1.0)
				var frequency := base * (1.0 - 0.05 * float(echo_index))
				sample += sin(TAU * frequency * u) * 0.2 * envelope
				sample += sin(TAU * frequency * 1.5 * u + 0.5) * 0.06 * envelope
		sample += sin(TAU * 48.0 * t) * 0.03 * exp(-t * 0.7)
		sample = clampf(sample, -1.0, 1.0)
		data.encode_s16(i * 4, int(sample * gains.x * 32767.0))
		data.encode_s16(i * 4 + 2, int(sample * gains.y * 32767.0))
	return _stereo_wav(data, rate, frames)


func _creak_stream(pan: float) -> AudioStreamWAV:
	var rate := AMBIENT_RATE
	var duration := 2.8
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 4)
	var gains := _pan_gains(pan)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123
	var filtered := 0.0
	var phase := 0.0
	for i in range(frames):
		var t := float(i) / rate
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.05)
		var envelope := minf(t * 2.5, 1.0) * exp(-maxf(t - 0.25, 0.0) * 1.1)
		var frequency := 135.0 - 42.0 * minf(t / duration, 1.0) + 4.0 * sin(TAU * 7.0 * t)
		phase += TAU * frequency / rate
		var sample := sin(phase) * 0.16 * envelope
		sample += sin(phase * 2.7 + 0.4) * 0.05 * envelope
		sample += filtered * 0.04 * envelope
		if t > 1.1:
			var u := t - 1.1
			sample += sin(TAU * 310.0 * u) * 0.05 * exp(-u * 5.0)
		sample = clampf(sample, -1.0, 1.0)
		data.encode_s16(i * 4, int(sample * gains.x * 32767.0))
		data.encode_s16(i * 4 + 2, int(sample * gains.y * 32767.0))
	return _stereo_wav(data, rate, frames)


func _radio_stream(pan: float) -> AudioStreamWAV:
	var rate := AMBIENT_RATE
	var duration := 1.7
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 4)
	var gains := _pan_gains(pan)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3141
	var filtered := 0.0
	for i in range(frames):
		var t := float(i) / rate
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.25)
		var gate := 0.0
		for start: float in [0.15, 0.55, 0.95]:
			if t >= start:
				gate += exp(-(t - start) * 18.0)
		var sample := filtered * 0.05 * gate
		sample += sin(TAU * 880.0 * t) * 0.025 * gate
		sample += sin(TAU * 1320.0 * t + 0.3) * 0.015 * gate
		sample = clampf(sample, -1.0, 1.0)
		data.encode_s16(i * 4, int(sample * gains.x * 32767.0))
		data.encode_s16(i * 4 + 2, int(sample * gains.y * 32767.0))
	return _stereo_wav(data, rate, frames)


func _moan_stream(pan: float) -> AudioStreamWAV:
	var rate := AMBIENT_RATE
	var duration := 4.2
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 4)
	var gains := _pan_gains(pan)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	var filtered := 0.0
	var phase_a := 0.0
	var phase_b := 0.0
	for i in range(frames):
		var t := float(i) / rate
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.03)
		var envelope := minf(t * 1.5, 1.0) * exp(-maxf(t - 0.4, 0.0) * 0.6) * minf((duration - t) * 1.5, 1.0)
		var frequency := 46.0 + 3.0 * sin(TAU * t / duration) - 4.0 * t / duration
		phase_a += TAU * frequency / rate
		phase_b += TAU * frequency * 0.5 / rate
		var sample := sin(phase_a) * 0.12 * envelope
		sample += sin(phase_b + 0.5) * 0.08 * envelope
		sample += sin(phase_a * 3.02) * 0.03 * envelope
		sample += filtered * 0.02 * envelope
		sample = clampf(sample, -1.0, 1.0)
		data.encode_s16(i * 4, int(sample * gains.x * 32767.0))
		data.encode_s16(i * 4 + 2, int(sample * gains.y * 32767.0))
	return _stereo_wav(data, rate, frames)


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
