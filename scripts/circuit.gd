class_name Circuit
extends RefCounted
## 賽車場佈置：路緣石（紅白）、碎石緩衝區、輪胎牆與水泥護牆＋防護網、起終點方格線、發車格、
## 起跑燈門架、看台（觀眾）、維修區建築、贊助看板、彎道距離牌。回傳 {lights: [5 組燈], line: 中心線, len}

const RUNOFF := 16.0        # 路面邊緣到護牆的距離（緩衝區）
const KERB_RED := Color(0.85, 0.1, 0.08)
const KERB_WHITE := Color(0.95, 0.95, 0.95)
const SPONSORS := ["眼動鼠", "小柯機器人", "大鵬灣國際賽車場", "台灣加油", "EYE MOUSE RACING", "小柯 AI 自駕", "屏東", "安全第一"]


static func build(w: World) -> Dictionary:
	var kit: MeshKit = w.kit
	var pts: Array = w.map.circuit
	var n := pts.size()
	var hw := 3 * 4.4 * 0.5           # 路面半寬
	# 累計距離
	var cum := [0.0]
	for i in n:
		cum.append(cum[i] + (pts[i] as Vector2).distance_to(pts[(i + 1) % n]))
	var total: float = cum[n]
	# 每點的曲率（左正右負）
	var curv := []
	for i in n:
		var a: Vector2 = pts[(i - 1 + n) % n]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[(i + 1) % n]
		var d1 := (b - a).normalized()
		var d2 := (c - b).normalized()
		var ang := d1.angle_to(d2)
		curv.append(ang / maxf(1.0, (a.distance_to(b) + b.distance_to(c)) * 0.5))
	var sponsor_i := 0
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var dir := (b - a).normalized()
		var r := Vector2(-dir.y, dir.x)
		var mid := (a + b) * 0.5
		var o := Vector3(mid.x, 0, mid.y)
		var M := kit.st("marking", o)
		var S := kit.st("solid", o)
		var k: float = curv[i]
		var corner := absf(k) > 1.0 / 260.0
		# 路面白邊線
		MeshKit.strip(M, a, b, hw - 0.35, hw - 0.15, 0.02, KERB_WHITE)
		MeshKit.strip(M, a, b, -hw + 0.15, -hw + 0.35, 0.02, KERB_WHITE)
		# 草地緩衝帶（綠色）＋外側碎石（彎道外側）
		for sd in [-1.0, 1.0]:
			if corner and signf(k) * sd < 0.0:     # 彎道外側：碎石緩衝區（左彎時右側是外側）
				MeshKit.strip(S, a, b, hw + 1.4 if sd > 0 else -hw - RUNOFF + 0.5, hw + RUNOFF - 0.5 if sd > 0 else -hw - 1.4, 0.01, Color(0.8, 0.72, 0.55))
		# 路緣石：彎道兩側紅白相間（每 2 公尺換色）
		if corner:
			var seg := a.distance_to(b)
			var t := 0.0
			var idx := int(cum[i] / 2.0)
			while t < seg:
				var t2 := minf(t + 2.0, seg)
				var col := KERB_RED if idx % 2 == 0 else KERB_WHITE
				for sd in [-1.0, 1.0]:
					var lo: float = hw if sd > 0 else -hw - 1.4
					var hi: float = hw + 1.4 if sd > 0 else -hw
					MeshKit.strip(M, a + dir * t, a + dir * t2, lo, hi, 0.05, col)
				t = t2
				idx += 1
		# 護牆（水泥＋上方廣告色帶）與防護網柱
		for sd in [-1.0, 1.0]:
			var off: float = sd * (hw + RUNOFF)
			var pa := a + r * off
			var pb := b + r * off
			MeshKit.wall(S, pa, pb, 0.0, 1.1, Color(0.85, 0.85, 0.83), sd < 0)
			MeshKit.wall(S, pa, pb, 0.0, 1.1, Color(0.6, 0.6, 0.6), sd > 0)
			MeshKit.strip(S, pa, pb, -0.15, 0.15, 1.1, Color(0.75, 0.75, 0.73))
			var band := Color.from_hsv(fmod(i * 0.13, 1.0), 0.65, 0.85) if i % 3 != 0 else Color(0.12, 0.3, 0.75)
			MeshKit.wall(kit.st("glow", o), pa - r * sd * 0.16, pb - r * sd * 0.16, 0.55, 1.05, band.darkened(0.25), sd < 0)
			if i % 2 == 0:
				MeshKit.cyl(kit.st("metal", o), MeshKit.xf_at(Vector3(pa.x, 1.1, pa.y)), 0.05, 0.05, 3.2, 6, Color(0.5, 0.52, 0.55), false)
				MeshKit.strip(kit.st("metal", o), pa, pb, -0.02, 0.02, 4.25, Color(0.5, 0.52, 0.55))
			# 彎道外側輪胎牆
			if corner and signf(k) * sd < 0.0 and i % 1 == 0:
				var tt := 0.0
				while tt < a.distance_to(b):
					var q: Vector2 = a + dir * tt + r * sd * (hw + RUNOFF - 0.5)
					for h in 3:
						MeshKit.cyl(kit.st("solid", o), MeshKit.xf_at(Vector3(q.x, h * 0.28, q.y)), 0.42, 0.42, 0.26, 8,
							Color(0.08, 0.08, 0.09) if h != 1 else Color(0.85, 0.85, 0.85))
					tt += 0.9
		# 贊助看板（護牆後面的大看板，每隔一段）
		if i % 9 == 4:
			var sd := -1.0 if i % 18 == 4 else 1.0
			var p: Vector2 = mid + r * sd * (hw + RUNOFF + 3.0)
			var yaw := atan2(-r.x * sd, -r.y * sd)
			var X := MeshKit.xf_at(Vector3(p.x, 0, p.y), yaw)
			MeshKit.box(S, X.translated_local(Vector3(0, 3.2, 0)), Vector3(14, 3.0, 0.3), Color(0.95, 0.95, 0.95))
			MeshKit.box(S, X.translated_local(Vector3(-6, 1.0, 0)), Vector3(0.25, 2.0, 0.25), Color(0.5, 0.5, 0.5))
			MeshKit.box(S, X.translated_local(Vector3(6, 1.0, 0)), Vector3(0.25, 2.0, 0.25), Color(0.5, 0.5, 0.5))
			var txt: String = SPONSORS[sponsor_i % SPONSORS.size()]
			sponsor_i += 1
			var l := Landmarks.label(w, txt, Vector3(p.x, 3.2, p.y) + Vector3(-r.x * sd, 0, -r.y * sd) * 0.2, 0.045, yaw + PI, Color(0.1, 0.25, 0.7) if sponsor_i % 2 else Color(0.8, 0.12, 0.1), false)
			l.outline_size = 0
	# 剎車距離牌：每個大彎前 150 / 100 / 50 公尺
	var corners := _corner_starts(pts, curv, cum)
	for cs in corners:
		for dist in [150.0, 100.0, 50.0]:
			var s_at: float = fposmod(cs - dist, total)
			var info := point_at(pts, cum, s_at)
			var p: Vector2 = info.p
			var dr: Vector2 = info.dir
			var rr := Vector2(-dr.y, dr.x)
			var q := p + rr * (hw + 3.0)
			var X := MeshKit.xf_at(Vector3(q.x, 0, q.y), atan2(dr.x, dr.y))
			MeshKit.box(kit.st("solid", Vector3(q.x, 0, q.y)), X.translated_local(Vector3(0, 0.9, 0)), Vector3(1.2, 1.2, 0.08), Color(0.95, 0.95, 0.95))
			Landmarks.label(w, str(int(dist)), Vector3(q.x, 0.9, q.y) - Vector3(dr.x, 0, dr.y) * 0.06, 0.06, atan2(dr.x, dr.y) + PI, Color(0.05, 0.05, 0.05), false).outline_size = 0
	# 起終點線（s=0）與發車格
	var s0 := point_at(pts, cum, 0.0)
	var p0: Vector2 = s0.p
	var d0: Vector2 = s0.dir
	var r0 := Vector2(-d0.y, d0.x)
	var Mk := kit.st("marking", Vector3(p0.x, 0, p0.y))
	for row in 2:
		for col in 12:
			var x0 := -hw + col * (hw * 2.0 / 12.0)
			var c := KERB_WHITE if (row + col) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var aa := p0 + d0 * (row * 1.1 - 1.1)
			MeshKit.strip(Mk, aa, aa + d0 * 1.1, x0, x0 + hw * 2.0 / 12.0, 0.03, c)
	for g in 8:
		var gi := grid_slot(pts, cum, g)
		var gp: Vector2 = gi.p
		var gd: Vector2 = gi.dir
		var gr := Vector2(-gd.y, gd.x)
		var Mg := kit.st("marking", Vector3(gp.x, 0, gp.y))
		MeshKit.strip(Mg, gp - gd * 2.6, gp - gd * 2.3, -1.4, 1.4, 0.025, KERB_WHITE)
		MeshKit.strip(Mg, gp - gd * 2.6 + gr * 1.4, gp + gd * 2.0 + gr * 1.4, -0.12, 0.12, 0.025, KERB_WHITE)
		MeshKit.strip(Mg, gp - gd * 2.6 - gr * 1.4, gp + gd * 2.0 - gr * 1.4, -0.12, 0.12, 0.025, KERB_WHITE)
	# 起跑燈門架
	var lights := []
	var gx := MeshKit.xf_at(Vector3(p0.x, 0, p0.y), atan2(d0.x, d0.y))
	var Sg := kit.st("metal", Vector3(p0.x, 0, p0.y))
	for sd in [-1.0, 1.0]:
		MeshKit.box(Sg, gx.translated_local(Vector3(sd * (hw + 1.5), 4.0, 0)), Vector3(0.5, 8.0, 0.5), Color(0.25, 0.27, 0.3))
	MeshKit.box(Sg, gx.translated_local(Vector3(0, 7.6, 0)), Vector3(hw * 2 + 3.5, 1.4, 0.6), Color(0.15, 0.16, 0.18))
	Landmarks.label(w, "START　/　FINISH", Vector3(p0.x, 8.8, p0.y), 0.06, atan2(d0.x, d0.y) + PI, Color(1, 1, 1), false)
	for k in 5:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.64
		lamp.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.15, 0.02, 0.02)
		m.emission_enabled = true
		m.emission = Color(1, 0.08, 0.05)
		m.emission_energy_multiplier = 0.0
		lamp.material_override = m
		var lp := Vector3(p0.x, 7.6, p0.y) + Vector3(r0.x, 0, r0.y) * ((k - 2) * 1.2) + Vector3(d0.x, 0, d0.y) * 0.35
		lamp.position = lp
		w.add_child(lamp)
		lights.append(lamp)
	# 看台（主直線右側）與維修區（左側）
	var stand_s := [-260.0, -120.0, 20.0]
	for ss in stand_s:
		var info := point_at(pts, cum, fposmod(ss, total))
		var sp: Vector2 = info.p
		var sdir: Vector2 = info.dir
		var srr := Vector2(-sdir.y, sdir.x)
		var c := sp + srr * (hw + RUNOFF + 14.0)
		var X := MeshKit.xf_at(Vector3(c.x, 0, c.y), atan2(sdir.x, sdir.y))
		var Ss := kit.st("solid", Vector3(c.x, 0, c.y))
		for step in 8:
			MeshKit.box(Ss, X.translated_local(Vector3(-step * 1.4 + 3.0, 0.5 + step * 0.9, 0)), Vector3(1.4, 1.0 + step * 1.8, 110), Color(0.72, 0.72, 0.74))
			# 觀眾（彩色小方塊）
			var rng := RandomNumberGenerator.new()
			rng.seed = int(ss) * 31 + step
			for q in 60:
				if rng.randf() < 0.25:
					continue
				var z := -54.0 + q * 1.8
				MeshKit.box(Ss, X.translated_local(Vector3(-step * 1.4 + 3.0, 1.0 + step * 1.8 + 0.45, z)), Vector3(0.5, 0.9, 0.55),
					Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.9), rng.randf_range(0.5, 1.0)))
		MeshKit.box(Ss, X.translated_local(Vector3(-5.0, 17.5, 0)), Vector3(14, 0.5, 114), Color(0.9, 0.9, 0.92))
		for zz in [-55.0, 0.0, 55.0]:
			MeshKit.box(Ss, X.translated_local(Vector3(-11.0, 8.75, zz)), Vector3(0.6, 17.5, 0.6), Color(0.6, 0.6, 0.62))
		w._add_col({"c": c, "r": 9.0})
		Landmarks.label(w, "大鵬灣國際賽車場", Vector3(c.x, 19.5, c.y), 0.12, atan2(sdir.x, sdir.y) - PI * 0.5, Color(1, 1, 1), false)
	# 維修區建築（左側）
	for ss in [-200.0, -60.0, 80.0]:
		var info := point_at(pts, cum, fposmod(ss, total))
		var sp: Vector2 = info.p
		var sdir: Vector2 = info.dir
		var srr := Vector2(-sdir.y, sdir.x)
		var c := sp - srr * (hw + RUNOFF + 16.0)
		var X := MeshKit.xf_at(Vector3(c.x, 0, c.y), atan2(sdir.x, sdir.y))
		var Sp := kit.st("solid", Vector3(c.x, 0, c.y))
		MeshKit.box(Sp, X.translated_local(Vector3(0, 5, 0)), Vector3(16, 10, 120), Color(0.9, 0.9, 0.9))
		for g in 10:
			MeshKit.box(kit.st("glass", Vector3(c.x, 0, c.y)), X.translated_local(Vector3(8.05, 2.6, -54 + g * 12)), Vector3(0.1, 4.6, 9.5), Color(0.2, 0.25, 0.32))
		MeshKit.box(Sp, X.translated_local(Vector3(0, 10.4, 0)), Vector3(18, 0.8, 122), Color(0.12, 0.3, 0.7))
		w._add_col({"c": c, "r": 10.0})
		Landmarks.label(w, "PIT　維修區", Vector3(c.x, 12.5, c.y), 0.1, atan2(sdir.x, sdir.y) + PI * 0.5, Color(1, 1, 1), false)
	# 控制塔
	var tw := p0 - r0 * (hw + RUNOFF + 30.0) + d0 * 20.0
	var Xt := MeshKit.xf_at(Vector3(tw.x, 0, tw.y), atan2(d0.x, d0.y))
	MeshKit.box(kit.st("solid", Vector3(tw.x, 0, tw.y)), Xt.translated_local(Vector3(0, 12, 0)), Vector3(8, 24, 8), Color(0.92, 0.92, 0.94))
	MeshKit.box(kit.st("glass", Vector3(tw.x, 0, tw.y)), Xt.translated_local(Vector3(0, 26, 0)), Vector3(12, 4, 12), Color(0.15, 0.3, 0.4))
	MeshKit.box(kit.st("solid", Vector3(tw.x, 0, tw.y)), Xt.translated_local(Vector3(0, 28.4, 0)), Vector3(13, 0.8, 13), Color(0.12, 0.3, 0.7))
	w._add_col({"c": tw, "r": 7.0})
	Landmarks.label(w, "小柯機器人", Vector3(tw.x, 31, tw.y), 0.1, 0.0, Color(1, 0.85, 0.3))
	return {"lights": lights, "line": pts, "cum": cum, "len": total, "hw": hw, "corners": corners}


## 中心線上距離 s 的點與方向
static func point_at(pts: Array, cum: Array, s: float) -> Dictionary:
	var n := pts.size()
	var total: float = cum[n]
	s = fposmod(s, total)
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var a: Vector2 = pts[lo]
	var b: Vector2 = pts[(lo + 1) % n]
	var seg: float = cum[lo + 1] - cum[lo]
	var t: float = (s - float(cum[lo])) / maxf(seg, 0.001)
	return {"p": a.lerp(b, t), "dir": (b - a).normalized(), "i": lo}


## 發車格：第 g 格（0 = 竿位），交錯左右，在起終點線後方
static func grid_slot(pts: Array, cum: Array, g: int) -> Dictionary:
	var s := -18.0 - g * 9.0
	var info := point_at(pts, cum, s)
	var r := Vector2(-info.dir.y, info.dir.x)
	info.p = info.p + r * (2.6 if g % 2 == 0 else -2.6)
	info.s = fposmod(s, cum[pts.size()])
	return info


static func _corner_starts(pts: Array, curv: Array, cum: Array) -> Array:
	var out := []
	var n := pts.size()
	var in_c := false
	for i in n:
		var c := absf(curv[i]) > 1.0 / 140.0
		if c and not in_c:
			if out.is_empty() or cum[i] - out[out.size() - 1] > 250.0:
				out.append(cum[i])
		in_c = c
	return out
