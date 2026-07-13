extends CharacterBody2D


const JUMP_SOUND := preload("res://assets/audio/player_jump.wav")
const RED_ORB := preload("res://scenes/red_orb.tscn")
const BLUE_ORB := preload("res://scenes/blue_orb.tscn")

const FIREBALL := preload("res://scenes/fireball.tscn")
const FIRE_GRENADE := preload("res://scenes/fire_grenade.tscn")
const FREEZE_TOUCH := preload("res://scenes/freeze_touch.tscn")
const GIANT_ICE_ORB := preload("res://scenes/giant_ice_orb.tscn")

const SLINGSHOT_AUDIO := preload("res://assets/audio/player_slingshot.wav")
const SLOT_CHANGED_AUDIO := preload("res://assets/audio/player_slot_changed.wav")
const POWER_CHANGED_AUDIO := preload("res://assets/audio/power_change.wav")
const POWER_USED_AUDIO := preload("res://assets/audio/power_use.wav")

const ATTACK_2_HOLD := 1.0

## How fast the character will move along the X axis.
@export_range(1, 100, 1, "or_greater", "suffix:px/s") var movement_speed := 128
## How high the character will jump.
@export_range(1, 100, 1, "or_greater", "suffix:px") var jump_height := 384
## How long a jump will be accepted after another one.
@export_range(0.01, 1.0, 0.01, "or_greater", "suffix:s")
var jump_buffering := 0.2
## How long a jump will be accepted after falling a cliff.
@export_range(0.01, 1.0, 0.01, "or_greater", "suffix:s")
var coyote_buffering := 0.1
## How often you can shoot.
@export_range(0.01, 10.0, 0.01, "or_greater", "suffix:s")
var cooldown_fireball := 1.5
## How often you can shoot.
@export_range(0.01, 10.0, 0.01, "or_greater", "suffix:s")
var cooldown_fire_grenade := 0.5
## How often you can shoot.
@export_range(0.01, 10.0, 0.01, "or_greater", "suffix:s")
var cooldown_freeze_touch := 0.5
## How often you can shoot.
@export_range(0.01, 10.0, 0.01, "or_greater", "suffix:s")
var cooldown_giant_ice_orb := 0.5
## How often you can use the strong attack.
@export_range(0.1, 10.0, 0.01, "or_greater", "suffix:s")
var strong_attack_duration := 10.0
## How often you can shoot per second.
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s")
var invincibility := 2.0
@export_category("Nodes")
@export var sprite: Sprite2D
@export var hit_box: Area2D
@export var animator: AnimationPlayer
@export var clamp_component: Node
@export var pivot: Node2D
@export var state_machine: FiniteStateMachine
@export var jump_state: BaseState
@export var hit_state: BaseState
@export var death_state: BaseState
@export var fall_death: Node
@export var cooldown_bar: ProgressBar

## The horizontal direction the player is moving to.
var direction := 0.0
## The number of times the player has jumped.
var jump_count := 0
## The time left to jump.
var jump_buffer := 0.0
## The time left to jump.
var coyote_buffer := 0.0

## The current cooldown.
var cooldown := 0.0
## The current max cooldown.
var max_cooldown := 1.0
## The current strong attack cooldown.
var strong_attack_cooldown := 0.0

## Invincibility time left.
var invincibility_left := 0.0
## The current attack type.
var attack := Globals.Attack.A
## The enemy will be freezed for this long.
var freeze_time := 0.0

## The time left before attack 2 is used.
var attack_2_time_left := 0.0

@onready var gravity = ProjectSettings.get_setting_with_override(&"physics/2d/default_gravity")


func _ready() -> void:
	Events.player_invincible.connect(_player_invincible)
	
	fall_death.dead.connect(_fall_death)
	
	# Register player
	Globals.player = self
	
	# Start invincibility
	if invincibility > invincibility_left:
		invincibility_left = invincibility
	
	prints("[player] invincible for:", invincibility_left, "s")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"change_orb"):
		if Globals.tutorial < Globals.Tutorial.CHANGE_ORB:
			return
		
		get_viewport().set_input_as_handled()
		Globals.orb = ((Globals.orb + 1) % 2) as Globals.Orb
		Events.orb_changed.emit()
		AudioManager.play(SLOT_CHANGED_AUDIO, 1.0, &"Sounds")
		
		var orb_name: String = Globals.Orb.keys()[Globals.orb]
		prints("[player] orb changed:", orb_name.capitalize())
	elif event.is_action_pressed(&"change_power"):
		if Globals.power == Globals.Power.IMMUNITY:
			if Globals.power_paralyze <= 0:
				return
		elif Globals.power_immunity <= 0:
			return
		
		get_viewport().set_input_as_handled()
		Globals.power = ((Globals.power + 1) % 2) as Globals.Power
		Events.power_changed.emit()
		AudioManager.play(POWER_CHANGED_AUDIO, 1.0, &"Sounds")
		
		var power_name: String = Globals.Power.keys()[Globals.power]
		prints("[player] power changed:", power_name.capitalize())
	elif event.is_action_pressed(&"power"):
		if Globals.power == Globals.Power.IMMUNITY:
			if Globals.power_immunity <= 0 or invincibility_left > 0.0:
				return
		elif Globals.power_paralyze <= 0 or Globals.enemy_paralyze > 0.0:
			return
		
		get_viewport().set_input_as_handled()
		
		# Power effect
		if Globals.power == Globals.Power.IMMUNITY:
			Globals.power_immunity -= 1
			Events.player_invincible.emit(8.0)
		else:
			Globals.power_paralyze -= 1
			Globals.enemy_paralyze = 20.0
		
		Events.power_used.emit()
		AudioManager.play(POWER_USED_AUDIO, 1.0, &"Sounds")
		
		var power_name: String = Globals.Power.keys()[Globals.power]
		prints("[player] power used:", power_name.capitalize())


func _physics_process(delta: float) -> void:
	# Walk while teleporting
	var was_teleporting := not is_equal_approx(Globals.teleport_offset, 0.0)
	
	Globals.teleport_offset = move_toward(Globals.teleport_offset,
				0.0, movement_speed * delta)
	
	if not is_equal_approx(Globals.teleport_offset, 0.0):
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		clamp_component.process_mode = Node.PROCESS_MODE_DISABLED
		
		# Animation
		direction = signf(Globals.teleport_offset)
		sprite.modulate = Color.WHITE
		animator.play(&"RUN")
		
		# Gravity logic
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y += gravity * delta
		
		# Movement
		velocity.x = direction * movement_speed
		move_and_slide()
		return
	
	if was_teleporting:
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT
		clamp_component.process_mode = Node.PROCESS_MODE_INHERIT
		state_machine.change_state("Idle")
	
	# Flip sprite logic
	if freeze_time <= 0.0:
		if direction < 0.0:
			sprite.scale.x = -1
		elif direction > 0.0:
			sprite.scale.x = 1
	
	# Jump buffer
	if jump_buffer > 0.0:
		jump_buffer -= delta
	else:
		jump_buffer = 0.0
	
	# Coyote buffer
	if coyote_buffer > 0.0:
		coyote_buffer -= delta
	else:
		coyote_buffer = 0.0
	
	if attack_2_time_left > 0.0:
		# Attack 2 hold
		cooldown_bar.update(ATTACK_2_HOLD - attack_2_time_left, ATTACK_2_HOLD)
	else:
		# Cooldown
		cooldown = move_toward(cooldown, 0.0, delta)
		update_cooldown_bar()
	
	if strong_attack_cooldown > 0.0:
		strong_attack_cooldown -= delta
		
		if strong_attack_cooldown <= 0.0:
			strong_attack_cooldown = 0.0
			Events.strong_attack_ready.emit()
	
	var cooldown_left := strong_attack_duration - strong_attack_cooldown
	Events.strong_attack_cooldown.emit(cooldown_left, strong_attack_duration)
	
	# Invincibility frames
	if invincibility_left > 0.0:
		invincibility_left -= delta
		sprite.modulate.a = fposmod(invincibility_left, 0.25) * 4.0
		
		if invincibility_left <= 0.0:
			prints("[player] invincibility ran out")
			sprite.modulate.a = 1.0
	
	# Process character movement
	velocity.x = direction * movement_speed
	
	# Freeze time
	if freeze_time > 0.0:
		freeze_time -= delta
		_freeze()
	else:
		_unfreeze()
	
	# Gravity logic
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += gravity * delta
	
	# Perform the actual movement
	move_and_slide()


## Makes the character jump upwards.
func jump() -> void:
	# Reset jump count (for double jump)
	if is_on_floor():
		jump_count = 0
	
	# Jump logic (with jump buffering)
	if Input.is_action_just_pressed(&"jump") and freeze_time <= 0.0:
		jump_buffer = jump_buffering
		
		if coyote_buffer > 0.0:
			jump_now()
			move_and_slide()
		elif jump_count < 2:
			# Double jump
			print("[player] double jump")
			jump_now()
			move_and_slide()
	# Variable jump height logic
	elif Input.is_action_just_released(&"jump") and velocity.y < 0.0:
		fall()
	
	# Jump
	if is_on_floor() and jump_buffer > 0.0:
		jump_buffer = 0.0
		
		# Fix: prevent full jump after release
		if not Input.is_action_pressed(&"jump"):
			return
		
		jump_now()
		move_and_slide()


func jump_now() -> void:
	jump_count += 1
	AudioManager.play(JUMP_SOUND, 1.0, &"Sounds")
	velocity.y = -jump_height
	state_machine.current_state = jump_state


## Makes the character start falling (usually after a jump).
func fall() -> void:
	velocity.y = 0.0


func hit(_damage: int, _knockback_direction: float) -> void:
	# Invincibility
	if invincibility_left > 0.0:
		return
	
	invincibility_left = invincibility
	prints("[player] invincible for:", invincibility_left, "s")
	
	# Die straight
	if Globals.tutorial < Globals.Tutorial.SHOOT:
		die(false)
		return
	
	# Orb drop and die logic
	if Globals.orb == Globals.Orb.RED:
		# Drop red orb
		if Globals.max_red_orbs > Globals.default_red_orbs:
			Globals.max_red_orbs -= 1
			prints("[player] max red orbs:", Globals.max_red_orbs)
			
			spawn_orb(RED_ORB)
			prints("[player] red orb dropped")
			
			# Hit state
			state_machine.current_state = hit_state
		elif Globals.red_orbs > 0:
			Globals.red_orbs -= 1
			spawn_orb(RED_ORB)
			prints("[player] red orb dropped")
			prints("[player] red orbs:", Globals.red_orbs)
			
			# Hit state
			state_machine.current_state = hit_state
		else:
			die(false)
	# Drop blue orb
	elif Globals.max_blue_orbs > Globals.default_blue_orbs:
		Globals.max_blue_orbs -= 1
		prints("[player] max blue orbs:", Globals.max_blue_orbs)
		
		spawn_orb(BLUE_ORB)
		prints("[player] blue orb dropped")
		
		# Hit state
		state_machine.current_state = hit_state
	elif Globals.blue_orbs > 0:
		Globals.blue_orbs -= 1
		spawn_orb(BLUE_ORB)
		prints("[player] blue orb dropped")
		prints("[player] blue orbs:", Globals.red_orbs)
		
		# Hit state
		state_machine.current_state = hit_state
	else:
		die(false)


func _fall_death() -> void:
	die(true)
	prints("[player] fell")
	
	# Reset player directions
	direction = 0.0
	sprite.scale.x = 1


func die(fallen: bool) -> void:
	Globals.player_health -= 1
	
	if Globals.player_health >= 0:
		Events.player_health_changed.emit()
	
	# Invincibility
	invincibility_left = invincibility
	
	# Freeze
	freeze_time = 0.0
	
	# Death
	if Globals.player_health <= 0:
		if fallen:
			Events.game_over.emit()
		else:
			state_machine.current_state = death_state


func spawn_orb(scene: PackedScene) -> void:
	var orb := scene.instantiate()
	orb.global_position = global_position
	Events.orb_dropped.emit(orb)


func handle_attack(delta: float) -> bool:
	if Input.is_action_just_pressed("attack_1"):
		try_shoot(Globals.Attack.A)
		return true
	
	# Hold
	if Input.is_action_just_pressed("attack_2_hold") and can_shoot_attack_b():
		attack_2_time_left = ATTACK_2_HOLD
		return false
	
	if Input.is_action_pressed("attack_2_hold") and can_shoot_attack_b():
		if attack_2_time_left > 0.0:
			attack_2_time_left -= delta
			
			if attack_2_time_left <= 0.0:
				if try_shoot(Globals.Attack.B):
					print("[player] attack B held")
					return true
		
		return false
	
	if Input.is_action_just_released("attack_2_hold"):
		attack_2_time_left = 0.0
		return true
	
	# Press
	if Input.is_action_just_pressed("attack_2_press"):
		if try_shoot(Globals.Attack.B):
			print("[player] attack B pressed")
		
		return true
	
	return false


func try_shoot(attack_type: Globals.Attack) -> bool:
	if cooldown > 0.0:
		return false
	
	attack = attack_type
	
	if can_shoot():
		if attack == Globals.Attack.B:
			if Globals.orb == Globals.Orb.RED:
				remove_red_orbs(Globals.FIRE_GRENADE_COST)
			else:
				remove_blue_orbs(Globals.GIANT_ICE_ORB_COST)
			
			Events.orb_consumed.emit()
		
		state_machine.change_state("Attack")
		return true
	
	return false


func remove_red_orbs(count: int) -> void:
	for i in count:
		if Globals.max_red_orbs > Globals.default_red_orbs:
			Globals.max_red_orbs -= 1
		else:
			Globals.red_orbs -= 1


func remove_blue_orbs(count: int) -> void:
	for i in count:
		if Globals.max_blue_orbs > Globals.default_blue_orbs:
			Globals.max_blue_orbs -= 1
		else:
			Globals.blue_orbs -= 1


func can_shoot() -> bool:
	if Globals.tutorial < Globals.Tutorial.SHOOT:
		return false
	
	if attack == Globals.Attack.A:
		if Globals.orb == Globals.Orb.RED:
			return Globals.red_orbs > 0
		return Globals.blue_orbs > 0
	
	return can_shoot_attack_b()


func can_shoot_attack_b() -> bool:
	if strong_attack_cooldown <= 0.0:
		if Globals.orb == Globals.Orb.RED:
			if Globals.red_orbs >= Globals.FIRE_GRENADE_COST:
				return true
		
		if Globals.blue_orbs >= Globals.GIANT_ICE_ORB_COST:
			return true
	
	return false


func shoot() -> void:
	# Audio
	AudioManager.play(SLINGSHOT_AUDIO, 1.0, &"Sounds")
	
	# Shoot
	var bullet: Node2D
	
	if Globals.orb == Globals.Orb.RED:
		if attack == Globals.Attack.A:
			bullet = FIREBALL.instantiate()
			Events.skill_one_used.emit()
			
			# Cooldown
			max_cooldown = cooldown_fireball
			cooldown += max_cooldown
		else:
			bullet = FIRE_GRENADE.instantiate()
			strong_attack_cooldown += strong_attack_duration
			Events.strong_attack_used.emit()
			
			# Cooldown
			max_cooldown = cooldown_fire_grenade
			cooldown += max_cooldown
	elif attack == Globals.Attack.A:
		bullet = FREEZE_TOUCH.instantiate()
		
		# Cooldown
		max_cooldown = cooldown_freeze_touch
		cooldown += max_cooldown
	else:
		bullet = GIANT_ICE_ORB.instantiate()
		strong_attack_cooldown += strong_attack_duration
		Events.strong_attack_used.emit()
		
		# Cooldown
		max_cooldown = cooldown_giant_ice_orb
		cooldown += max_cooldown
	
	bullet.global_position = pivot.global_position
	bullet.direction.x = sprite.scale.x
	Events.bullet.emit(bullet)


## Freezes the player for the given amount of time.
func freeze(time: float) -> void:
	if invincibility_left > 0.0:
		print("[freeze] player is invincible")
		return
	
	freeze_time = time
	prints("[freeze] player frozen for:", freeze_time, "s")


func _freeze() -> void:
	velocity.x = 0.0
	animator.process_mode = Node.PROCESS_MODE_DISABLED
	sprite.self_modulate = Color.AQUAMARINE
	hit_box.process_mode = Node.PROCESS_MODE_DISABLED


func _unfreeze() -> void:
	animator.speed_scale = 1.0
	animator.process_mode = Node.PROCESS_MODE_INHERIT
	sprite.self_modulate = Color.WHITE
	hit_box.process_mode = Node.PROCESS_MODE_INHERIT


func update_cooldown_bar() -> void:
	cooldown_bar.update(max_cooldown - cooldown, max_cooldown)


func heal() -> bool:
	if Globals.tutorial < Globals.Tutorial.HEAL:
		return false
	
	if Globals.orb == Globals.Orb.RED:
		if Globals.red_orbs >= Globals.LIFE_COST:
			# Take orbs
			Globals.red_orbs -= Globals.LIFE_COST
			Events.orb_consumed.emit()
			
			# Heal
			Globals.player_health += 1
			Globals.max_player_health += 1
			Events.player_health_changed.emit()
			return true
	elif Globals.blue_orbs >= Globals.LIFE_COST:
		# Take orbs
		Globals.blue_orbs -= Globals.LIFE_COST
		Events.orb_consumed.emit()
		
		# Heal
		Globals.player_health += 1
		Globals.max_player_health += 1
		Events.player_health_changed.emit()
		return true
	
	return false


func _player_invincible(time: float) -> void:
	invincibility_left = time
