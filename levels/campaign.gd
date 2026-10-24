class_name Campaign
extends Resource
## The stages played in order on one map, and the shouts when one is cleared.

@export var stages: Array[CampaignStage] = []
## Shown, one after the other, when a stage is cleared.
@export var cleared_shouts: PackedStringArray = PackedStringArray(["KLIN CHOL!", "WARAA!"])
@export var cleared_colors: PackedColorArray = PackedColorArray([Color(1.0, 0.56, 0.08), Color(0.98, 0.97, 0.94)])
@export var final_shout := "GRIVET!"
@export var final_subtitle := "ALL STAGES PASSED"
## Seconds from the last enemy falling to the next stage starting.
@export var next_stage_delay := 5.5
