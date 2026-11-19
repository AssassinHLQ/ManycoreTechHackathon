extends SceneTree
func _initialize():
 call_deferred("_run")
func _run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.save_path="user://probe_pocket_issues_knowledge.json"
 game.progress_path="user://probe_pocket_issues_progress.json"
 var t=Time.get_ticks_msec()
 root.add_child(game)
 await game.await_world_ready()
 print("READY_MS ",Time.get_ticks_msec()-t)
 game.start_game()
 game.player.set_physics_process(false)
 await physics_frame
 var a=game.anomalies[0]
 var arch=game.home.get_node("Architecture_Qinglan")
 print("ANOMALY_ARCH_LOCAL ",arch.to_local(a.global_position), " ORB ",arch.to_local(a.orb.global_position))
 var up:Vector3=a.global_basis.y.normalized()
 var q=PhysicsRayQueryParameters3D.create(a.global_position+up*100,a.global_position-up*150,1)
 var hit=game.get_world_3d().direct_space_state.intersect_ray(q)
 print("TOP_HIT ",hit)
 var camera=game.player.camera
 print("START_PLAYER ",arch.to_local(game.player.global_position), " CAMERA ",arch.to_local(camera.global_position)," DIST ",camera.global_position.distance_to(a.orb.global_position))
 for xyz in [Vector3(0,1.75,10),Vector3(0,1.75,15),Vector3(10,1.75,8),Vector3(-10,1.75,8)]:
  game.player.global_position=arch.to_global(xyz)
  camera.look_at(a.orb.global_position,up)
  print("SCAN_FROM ",xyz," TARGET ",game._find_scan_target()==a," DIST ",camera.global_position.distance_to(a.orb.global_position)," LOS_ORB ",game._has_line_of_sight(camera.global_position,a.orb.global_position))
 game._enter_attic_space()
 for key in ["cloud","firefly","alley","snow"]:
  t=Time.get_ticks_usec()
  game.enter_pocket(key)
  print("ENTER_US ",key," ",Time.get_ticks_usec()-t," FAR ",camera.far)
  await process_frame
  game.leave_pocket()
 game.free()
 quit()
