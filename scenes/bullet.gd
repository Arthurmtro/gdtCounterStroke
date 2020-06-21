extends RigidBody2D


# Called when the node enters the scene tree for the first time.
func _ready():
	print("he")



func _on_Bullet_body_entered(body):
	self.queue_free()
	
	print("aie")
