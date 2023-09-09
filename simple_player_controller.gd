class_name SimplePlayerController
extends Node3D


@export var speed = 10
@export var jump_velocity = 4.5


var look_sensitivity = 0.01


@onready var camera: Camera3D = $Camera3D


func _process(delta):
	var horizontal_velocity: Vector2 = Input.get_vector("move_left","move_right","move_forward","move_back").normalized() * speed
	var vertical_velocity: float = Input.get_axis("move_down", "move_up") * speed
	var velocity: Vector3 = horizontal_velocity.x * global_transform.basis.x + vertical_velocity * global_transform.basis.y + horizontal_velocity.y * global_transform.basis.z
	global_translate(velocity * delta)
	if Input.is_action_just_pressed("toggle_mouse_capture"): 
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE


func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * look_sensitivity)
		camera.rotate_x(-event.relative.y * look_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
