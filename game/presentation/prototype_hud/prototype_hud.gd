extends CanvasLayer
@export var player_path:NodePath
@onready var hp:ProgressBar=$Left/Frame/V/Health/Bar
@onready var hpv:Label=$Left/Frame/V/Health/Value
@onready var mut:ProgressBar=$Left/Frame/V/Mutation/Wrap/Bar
@onready var mutv:Label=$Left/Frame/V/Mutation/Value
@onready var marker:ColorRect=$Left/Frame/V/Mutation/Wrap/Marker
@onready var armor:HBoxContainer=$Left/Frame/V/Armor
@onready var anti:Label=$Left/Antidote/Count
@onready var wname:Label=$Right/Frame/Name
@onready var mag:Label=$Right/Frame/Ammo/Mag
@onready var reserve:Label=$Right/Frame/Ammo/Reserve
@onready var reload:Label=$Right/Frame/Reload
@onready var slots:Array[PanelContainer]=[$Right/Frame/Slots/S1,$Right/Frame/Slots/S2,$Right/Frame/Slots/S3]
var p:Node
var inf:Node
func _ready()->void:p=get_node(player_path);inf=p.get_node("InfectionRuntime");hp.max_value=p.max_health;mut.max_value=100
func _process(_d:float)->void:
	hp.value=p.health;hpv.text="%d / %d"%[roundi(p.health),roundi(p.max_health)]
	var m:float=inf.call("get_mutation");var crit:float=inf.call("get_critical_threshold");mut.value=m;mutv.text="%d / 100"%roundi(m);marker.position.x=mut.size.x*crit/100.0
	var filled:=ceili(p.armor/maxf(p.max_armor,1)*armor.get_child_count())
	for i in armor.get_child_count():(armor.get_child(i) as ColorRect).color=Color(0.1,0.85,1,1) if i<filled else Color(0.03,0.12,0.18,1)
	anti.text=str(p.antidotes)
	var w:Node=p.get_current_weapon();wname.text=w.call("get_weapon_name");mag.text=str(w.call("get_magazine_ammo"));reserve.text="/ %d"%w.call("get_reserve_ammo");reload.text="RELOADING" if w.call("is_reloading") else ""
	for i in slots.size():slots[i].modulate=Color(0.1,1,1,1) if i==p.get_current_weapon_index() else Color(0.5,0.65,0.75,0.75)
