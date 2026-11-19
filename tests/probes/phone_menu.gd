extends Node
## Phone menu probe (windowed): boots the title menu, picks PHONE, and checks
## that the game starts the PhonePad server itself, shows a QR code per
## network, and reports PHONE CONNECTED once a phone (the sim) connects.
## Exit 0 = pass. Needs Node 18+ and the installed packages in tools/phonepad.
##
##   $GODOT --path . res://tests/probes/phone_menu.tscn [-- shot=<abs path>.png]
## Another PhonePad on 8080/8443? Set PHONEPAD_GAME_PORT / PHONEPAD_HTTPS_PORT first.

const MENU := "res://ui/main_menu.tscn"

var failures := 0
var shot := ""
var sim: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shot = arg.get_slice("=", 1)
	get_tree().create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		printerr("FAIL watchdog")
		_stop_sim()
		get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var stand_in := Node.new()
	tree.root.add_child(stand_in)
	tree.current_scene = stand_in
	tree.change_scene_to_file(MENU)
	await tree.create_timer(3.0).timeout
	var menus := tree.root.find_children("*", "GameMenu", true, false)
	if menus.is_empty():
		print("FAIL no GameMenu")
		tree.quit(1)
		return
	var menu: GameMenu = menus[0]
	_check("the server isn't running before PHONE is picked", not PhonePad.is_connected_to_server(), "already connected")
	menu._show("phone")
	var panel: PhoneConnectPanel = menu._phone_panel
	var waited := 0.0
	while not panel._have_links and waited < 30.0:
		await tree.create_timer(0.25).timeout
		waited += 0.25
	print("links after %.1f s: %s" % [waited, panel._have_links])
	var views := panel.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n is PhoneConnectPanel.QrView)
	_check("the page shows QR codes", not views.is_empty() and (views[0] as PhoneConnectPanel.QrView).modules.size() >= 21,
			"%d views, status %s" % [views.size(), panel._status.text])
	await tree.create_timer(2.5).timeout  # PhonePad's own socket connects
	_check("Grivet connects to the server it started", PhonePad.is_connected_to_server(), "not connected")
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		print("screenshot %s" % shot)
	sim = OS.execute_with_pipe("node", [ProjectSettings.globalize_path("res://tools/phonepad/sim/phone_sim.js")], false)
	waited = 0.0
	while PhonePad.controllers == 0 and waited < 10.0:
		await tree.create_timer(0.25).timeout
		waited += 0.25
	await tree.create_timer(0.3).timeout
	_check("the page says the phone is connected", panel._status.text.begins_with("PHONE CONNECTED"), panel._status.text)
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot.get_basename() + "_connected.png")
	print("\n%s: %d check(s) failed" % ["FAIL" if failures else "PASS", failures])
	_stop_sim()
	tree.quit(1 if failures else 0)


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", what, "" if ok else " (%s)" % detail])
	if not ok:
		failures += 1


func _stop_sim() -> void:
	if sim.has("pid") and OS.is_process_running(sim.pid):
		OS.kill(sim.pid)
