class_name Race
extends Node
## 賽車比賽：起跑燈倒數、5 台 AI 對手（沿賽道中心線＋各自的速度曲線）、圈數與圈速、名次、
## 玩家與對手的碰撞、小柯 AI 自駕（賽車線追蹤）。由 drive.gd 在賽車場地圖建立。

signal race_finished(pos: int, total: float, best: float)

const RIVALS := [
	{"name": "阿明", "no": 7, "model": "gt_red", "fallback": "car_red", "skill": 0.93},
	{"name": "美玲", "no": 21, "model": "gt_yellow", "fallback": "car_white", "skill": 0.9},
	{"name": "志豪", "no": 33, "model": "gt_green", "fallback": "car_silver", "skill": 0.96},
	{"name": "雅婷", "no": 11, "model": "gt_orange", "fallback": "sedan", "skill": 0.88},
	{"name": "建宏", "no": 5, "model": "gt_silver", "fallback": "car_red", "skill": 0.94},
]
const PLAYER_SLOT := 3            # 玩家從第 4 格起跑

var drive: Node
var veh: Vehicle
var world: World
var line: Array
var cum: Array
var total := 0.0
var hw := 6.6
var laps := 3
var lap := 0                      # 玩家已完成圈數
var lap_start := 0.0
var lap_times: Array = []
var best_lap := 0.0
var phase := "grid"               # grid / lights / go / finished
var phase_t := 0.0
var lights_out_at := 0.0
var race_t := 0.0
var p_s := 0.0                    # 玩家在中心線上的距離
var p_idx := 0
var p_lat := 0.0
var p_total := 0.0                # 玩家總行駛距離（含圈數）
var _half_ok := false
var cars: Array = []              # AI：{name,no,node,s,lat,lat_t,v,skill,laps,total,done_t,prof}
var prof_player: PackedFloat32Array
var curv: PackedFloat32Array
var difficulty := 1.0
var finish_pos := 0
var _last_beep := -1


func setup(d: Node, n_laps := 3) -> void:
	drive = d
	veh = d.veh
	world = d.world
	laps = n_laps
	var c: Dictionary = world.circuit
	line = c.line
	cum = c.cum
	total = c.len
	hw = c.hw
	difficulty = float(App.settings.get("race_level", 1.0))
	_curvature()
	prof_player = _profile(15.5 * 0.85, 74.0, 8.5, 1.0)
	# 玩家放到發車格
	var slot := Circuit.grid_slot(line, cum, PLAYER_SLOT)
	var dir: Vector2 = slot.dir
	var p: Vector2 = slot.p + dir * 1.2
	veh.position = Vector3(p.x, 0, p.y)
	veh.yaw = atan2(-dir.x, -dir.y)
	veh.rotation.y = veh.yaw
	veh.speed = 0.0
	veh.handbrake = true
	p_s = slot.s
	p_idx = slot.i
	_half_ok = false
	# 對手
	var g := 0
	for i in RIVALS.size():
		if g == PLAYER_SLOT:
			g += 1
		var r: Dictionary = RIVALS[i]
		var sl := Circuit.grid_slot(line, cum, g)
		var skill: float = r.skill * lerpf(0.9, 1.04, clampf(difficulty - 0.5, 0.0, 1.0))
		var car := {"name": r.name, "no": r.no, "s": sl.s, "lat": (2.6 if g % 2 == 0 else -2.6), "lat_t": (2.6 if g % 2 == 0 else -2.6),
			"v": 0.0, "skill": skill, "laps": -1, "total": 0.0, "done_t": 0.0, "slot": g, "react": 0.15 + randf() * 0.35}
		car.prof = _profile(14.5 * skill, 72.0 * skill, 10.5 * skill)
		car.node = _car_node(r)
		world.add_child(car.node)
		cars.append(car)
		g += 1
	for car in cars:
		car.total = _rel(car.s) - total   # 起跑線後方：總距離為負
		car.laps = 0
	p_total = _rel(p_s) - total
	_place_cars(0.0)
	veh.traffic_push = push


func _car_node(r: Dictionary) -> Node3D:
	var root := Node3D.new()
	var m: Node3D = null
	if Models.has(r.model):
		m = Models.make(r.model, 4.65)
	elif Models.has(r.fallback):
		m = Models.make(r.fallback, 4.6)
	if m:
		root.add_child(m)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.95, 1.1, 4.6)
		mi.mesh = bm
		mi.position.y = 0.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(randf(), 0.8, 0.9)
		mi.material_override = mat
		root.add_child(mi)
	var l := Landmarks.label(root, "%s #%d" % [r.name, r.no], Vector3(0, 1.9, 0), 0.0045, 0.0, Color(1, 1, 1))
	l.no_depth_test = false
	l.set_meta("tag", true)
	return root


## 0 ≤ s < total 轉成「相對起跑線」：起跑線前方為正
func _rel(s: float) -> float:
	return s if s < total * 0.5 else s - total + total   # 保持 0..total，呼叫端自行處理


# ---------------------------------------------------------------- 速度曲線
func _curvature() -> void:
	var n := line.size()
	curv = PackedFloat32Array()
	curv.resize(n)
	for i in n:
		var a: Vector2 = line[(i - 3 + n) % n]
		var b: Vector2 = line[i]
		var c: Vector2 = line[(i + 3) % n]
		var d1 := (b - a)
		var d2 := (c - b)
		var ang := d1.normalized().angle_to(d2.normalized())
		curv[i] = ang / maxf(1.0, (d1.length() + d2.length()) * 0.5)


func _profile(alat: float, vtop: float, brk: float, cut := 1.25) -> PackedFloat32Array:
	var n := line.size()
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		var k := absf(curv[i])
		# 賽車線會切彎（實際半徑比中心線大），所以半徑放大 1.6 倍
		v[i] = minf(vtop, sqrt(alat * cut / maxf(k, 1e-4)))
	for _pass in 2:
		for j in n:
			var i := n - 1 - j
			var nx := (i + 1) % n
			var ds: float = (line[i] as Vector2).distance_to(line[nx])
			v[i] = minf(v[i], sqrt(v[nx] * v[nx] + 2.0 * brk * ds))
	return v


func _prof_at(prof: PackedFloat32Array, s: float) -> float:
	var info := Circuit.point_at(line, cum, s)
	return prof[info.i]


# ---------------------------------------------------------------- 每格
func step(dt: float) -> void:
	phase_t += dt
	match phase:
		"grid":
			veh.handbrake = true
			if phase_t > 2.5:
				phase = "lights"
				phase_t = 0.0
				lights_out_at = 5.0 + randf_range(0.4, 1.4)
				Snd.say("race_lights", true)
		"lights":
			veh.handbrake = true
			var on := mini(5, int(phase_t))
			_set_lights(on)
			if on != _last_beep and on > 0 and on <= 5:
				_last_beep = on
				Snd.play("click", 0.9, 0.8)
			if phase_t >= lights_out_at:
				_set_lights(0)
				phase = "go"
				phase_t = 0.0
				race_t = 0.0
				lap_start = 0.0
				veh.handbrake = false
				veh.gear = "D"
				Snd.play("success", 0.6, 1.4)
				Snd.say("race_go", true)
		"go", "finished":
			race_t += dt
	_track_player()
	if phase in ["go", "finished"]:
		_step_ai(dt)
	_place_cars(dt)


func _set_lights(n: int) -> void:
	var ls: Array = world.circuit.get("lights", [])
	for k in ls.size():
		var m: StandardMaterial3D = (ls[k] as MeshInstance3D).material_override
		m.emission_energy_multiplier = 6.0 if k < n else 0.0
		m.albedo_color = Color(1, 0.1, 0.05) if k < n else Color(0.15, 0.02, 0.02)


func _track_player() -> void:
	var p := veh.pos2()
	var n := line.size()
	var best := p_idx
	var bd := INF
	for o in range(-6, 14):
		var i := (p_idx + o + n) % n
		var d := p.distance_squared_to(line[i])
		if d < bd:
			bd = d
			best = i
	if bd > 60.0 * 60.0:   # 跑太遠（例如重設位置）→ 全部搜尋
		for i in n:
			var d := p.distance_squared_to(line[i])
			if d < bd:
				bd = d
				best = i
	p_idx = best
	# 在線段上精確投影
	var a: Vector2 = line[best]
	var b: Vector2 = line[(best + 1) % n]
	var dir := (b - a).normalized()
	var along := clampf((p - a).dot(dir), -30.0, a.distance_to(b) + 30.0)
	var new_s := fposmod(float(cum[best]) + along, total)
	p_lat = (p - a).dot(Vector2(-dir.y, dir.x))
	var ds := new_s - p_s
	if ds < -total * 0.5:
		ds += total
	elif ds > total * 0.5:
		ds -= total
	p_s = new_s
	p_total += ds
	if p_s > total * 0.4 and p_s < total * 0.6:
		_half_ok = true
	# 過起終點線（往前）
	if phase in ["go", "finished"] and ds > 0 and p_total >= (lap + 1) * total and _half_ok:
		_half_ok = false
		var lt := race_t - lap_start
		lap_start = race_t
		lap_times.append(lt)
		if best_lap <= 0.0 or lt < best_lap:
			best_lap = lt
		lap += 1
		if phase == "go":
			if lap >= laps:
				_finish()
			else:
				drive.say_msg("第 %d 圈完成：%s%s" % [lap, fmt_time(lt), "（最快圈！）" if lt == best_lap and lap > 1 else ""], "ok")
				Snd.say("race_final" if lap == laps - 1 else "race_lap", false)


func _finish() -> void:
	phase = "finished"
	finish_pos = player_pos()
	race_finished.emit(finish_pos, race_t, best_lap)


func player_pos() -> int:
	if phase == "finished" and finish_pos > 0:
		return finish_pos
	var pos := 1
	for car in cars:
		if car.total > p_total:
			pos += 1
	return pos


func standings() -> Array:
	var arr := [{"name": "你", "no": 1, "total": p_total if phase != "finished" else 1e9 - finish_pos, "player": true}]
	for car in cars:
		arr.append({"name": car.name, "no": car.no, "total": car.total if car.done_t <= 0.0 else 1e9 - car.get("fpos", 9), "player": false})
	arr.sort_custom(func(a, b): return a.total > b.total)
	return arr


func lap_time() -> float:
	if phase == "grid" or phase == "lights":
		return 0.0
	return race_t - lap_start


static func fmt_time(t: float) -> String:
	if t <= 0.0:
		return "-:--.---"
	return "%d:%02d.%03d" % [int(t / 60.0), int(fmod(t, 60.0)), int(fmod(t, 1.0) * 1000.0)]


# ---------------------------------------------------------------- AI 對手
func _step_ai(dt: float) -> void:
	var finished_n := 1 if phase == "finished" else 0
	for car in cars:
		if car.done_t > 0.0:
			finished_n += 1
	for car in cars:
		if race_t < car.react:
			continue
		var vt := _prof_at(car.prof, car.s + 8.0 + car.v * 0.3)
		if car.done_t > 0.0:
			vt = minf(vt, 30.0)
		# 前方的車（包含玩家）：同一條線上靠太近就減速或換線超車
		var ahead_gap := INF
		var ahead_v := 0.0
		var ahead_lat := 0.0
		var others := [{"total": p_total, "lat": p_lat, "v": absf(veh.speed)}]
		for o in cars:
			if o != car:
				others.append({"total": o.total, "lat": o.lat, "v": o.v})
		for o in others:
			var gap: float = o.total - car.total
			if gap > 0.0 and gap < 28.0 and absf(o.lat - car.lat) < 2.6:
				if gap < ahead_gap:
					ahead_gap = gap
					ahead_v = o.v
					ahead_lat = o.lat
		if ahead_gap < 28.0:
			if car.v > ahead_v:
				# 往空的一側換線
				var side := -1.0 if ahead_lat > 0.0 else 1.0
				car.lat_t = clampf(ahead_lat + side * 3.4, -hw + 1.4, hw - 1.4)
			if ahead_gap < 9.0:
				vt = minf(vt, ahead_v - 1.0)
		else:
			# 沒有車：慢慢回到賽車線（入彎靠內側）
			var k := curv[Circuit.point_at(line, cum, car.s + 40.0).i]
			car.lat_t = clampf(signf(k) * minf(absf(k) * 900.0, 3.5) if absf(k) > 1.0 / 400.0 else car.lat_t * 0.98, -hw + 1.4, hw - 1.4)
		var acc: float = 6.5 * car.skill * clampf(1.0 - car.v / 80.0, 0.15, 1.0)
		if car.v < vt:
			car.v = minf(vt, car.v + acc * dt)
		else:
			car.v = maxf(vt, car.v - 12.0 * dt)
		car.v = maxf(car.v, 0.0)
		car.lat = move_toward(car.lat, car.lat_t, dt * 2.2)
		var ds: float = car.v * dt
		car.s = fposmod(car.s + ds, total)
		car.total += ds
		if car.done_t <= 0.0 and car.total >= laps * total:
			car.done_t = race_t
			car.fpos = finished_n + 1
			finished_n += 1


func _place_cars(_dt: float) -> void:
	for car in cars:
		var info := Circuit.point_at(line, cum, car.s)
		var dir: Vector2 = info.dir
		var r := Vector2(-dir.y, dir.x)
		var p: Vector2 = info.p + r * car.lat
		var nd: Node3D = car.node
		nd.position = Vector3(p.x, 0, p.y)
		nd.rotation.y = atan2(-dir.x, -dir.y)


## 玩家碰撞：對手各用三個圓（前、中、後）
func push(c: Vector2, rad: float) -> Vector2:
	var out := Vector2.ZERO
	for car in cars:
		var nd: Node3D = car.node
		var cp := Vector2(nd.position.x, nd.position.z)
		if cp.distance_squared_to(c) > 64.0:
			continue
		var f := Vector2(-sin(nd.rotation.y), -cos(nd.rotation.y))
		for z in [-1.6, 0.0, 1.6]:
			var q: Vector2 = cp + f * z
			var d := c.distance_to(q)
			var need := rad + 0.95
			if d < need and d > 0.001:
				out += (c - q) / d * (need - d)
				car.v *= 0.97
	return out


## 小柯 AI 賽車自駕：純追蹤沿中心線（偏賽車線），依速度曲線油門／煞車
func ap_drive(_dt: float) -> Dictionary:
	if phase in ["grid", "lights"]:
		return {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "blinker": 0}
	var v := absf(veh.speed)
	var ld := clampf(9.0 + v * 0.55, 10.0, 48.0)
	var info := Circuit.point_at(line, cum, p_s + ld)
	var dir: Vector2 = info.dir
	var k := curv[info.i]
	var lat_t := clampf(signf(k) * minf(absf(k) * 700.0, 3.0), -hw + 1.6, hw - 1.6) if absf(k) > 1.0 / 400.0 else 0.0
	var target: Vector2 = info.p + Vector2(-dir.y, dir.x) * lat_t
	var to := target - veh.pos2()
	var alpha := veh.fwd2().angle_to(to)
	var wb: float = veh.spec.wb
	var max_st: float = float(veh.spec.steer) * clampf(1.0 - v / 38.0 * 0.65, 0.3, 1.0)
	var st := atan(2.0 * wb * sin(alpha) / maxf(to.length(), 1.0))
	var steer := clampf(st / max_st, -1.0, 1.0)
	# 前方有車：換到另一側超車，太近就跟車
	for car in cars:
		var gap: float = car.total - p_total
		if gap > 0.0 and gap < 30.0 and absf(car.lat - lat_t) < 2.8:
			lat_t = clampf(car.lat + (-3.6 if car.lat > 0.0 else 3.6), -hw + 1.6, hw - 1.6)
			target = info.p + Vector2(-dir.y, dir.x) * lat_t
			to = target - veh.pos2()
			alpha = veh.fwd2().angle_to(to)
			st = atan(2.0 * wb * sin(alpha) / maxf(to.length(), 1.0))
			steer = clampf(st / max_st, -1.0, 1.0)
	var vt := _prof_at(prof_player, p_s + 4.0 + v * 0.5)
	for car in cars:
		var gap2: float = car.total - p_total
		if gap2 > 0.0 and gap2 < 10.0 and absf(car.lat - p_lat) < 2.2:
			vt = minf(vt, car.v - 1.5)
	var thr := clampf((vt - v) * 0.4, 0.0, 1.0)
	var brk := clampf((v - vt) * 0.18, 0.0, 1.0)
	if phase == "finished":
		thr = minf(thr, 0.3)
	return {"steer": steer, "throttle": thr, "brake": brk, "blinker": 0}
