extends SceneTree
const OffWin = preload("res://scripts/offscreen_window.gd")
func _initialize():
 DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
 call_deferred("_run")
func _run():
 await OffWin.apply(self)
 if not OffWin.is_safe()[0]:
  quit(2)
  return
 var worlds=load("res://scripts/attic_worlds.gd").new()
 root.add_child(worlds)
	await worlds.build()
 var environment=Environment.new()
 var sky=Sky.new()
 var material=ShaderMaterial.new()
 material.shader=load("res://shaders/space_sky.gdshader")
 material.set_shader_parameter("sky_detail",1)
 sky.sky_material=material
 environment.background_mode=Environment.BG_SKY
 environment.sky=sky
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color=Color(0.28,0.36,0.54)
 environment.ambient_light_energy=0.5
 var world_env=WorldEnvironment.new()
 world_env.environment=environment
 root.add_child(world_env)
 var camera=Camera3D.new()
 camera.far=350
 camera.fov=74
 root.add_child(camera)
 camera.current=true
 var controller=load("res://scripts/main.gd").new()
 controller.sky_material=material
 controller.attic_worlds=worlds
 DirAccess.make_dir_recursive_absolute("res://captures")
 for key in ["cloud","firefly","alley","snow"]:
  controller.apply_sky(key)
  var content=worlds.worlds[key].content
  camera.global_position=content.to_global(Vector3(0,4,10))
  camera.look_at(content.to_global(Vector3(0,2,-8)),Vector3.UP)
  for i in range(6):
   await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/pocketfix_%s.png" % key)
  print("CAPTURED ",key)
 print("OFFSCREEN ",OffWin.is_safe())
 controller.free()
 quit()
