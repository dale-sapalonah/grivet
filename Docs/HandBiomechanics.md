# Hand biomechanics for the first-person hands

What SkinnedViewArms (weapons/skinned_view_arms.gd) uses when closing the
player's fingers on a gun, and where the numbers come from. Tuning lives in
data/weapons/view_model_tuning.tres (`arms_*`).

## Joints and pivots

Each finger has three hinge joints at the bones' own pivots (the Mixamo rig's
HandIndex1/2/3 etc.): the knuckle (MCP), the middle joint (PIP) and the tip
joint (DIP). They turn about one axis, the hand's curl axis, from the straight
rest pose. `res://tests/probes/hands_look.tscn` draws the skeleton over the
hands (yellow bones, red joints) to check where they bend.

## Ranges (from straight)

| Joint | Used | Measured |
|---|---|---|
| MCP (knuckle) | 85° (`arms_mcp_max_degrees`) | about 84–87° active flexion; reference tables 80–90° |
| PIP (middle) | 100° (`arms_pip_max_degrees`) | about 92–104° |
| DIP (tip) | 75° (`arms_dip_max_degrees`) | about 68–85° |

## Coupling

The tip joint is not driven on its own: it follows the middle joint at 0.7°
per degree (`arms_dip_pip_coupling`). A cadaver study measured a slope of
0.69 for DIP against PIP. Tips bending independently gave the claw look.

Fingers are wrapped the way the reference grips show (the user's handgun
photos): the pads of the middle, ring and little fingers rest on the far side
of the grip, level with their own knuckles, so the fingers enclose it; the
index pad sits on the trigger; the thumb lies along the far side. The solver
(`_wrap_finger`) searches knuckle and middle-joint angles (tip coupled) for
the pose that lands the pad on that target without touching the gun.

## Solid contact

Each phalanx is tested as a tube as thick as its own flesh, measured from the
mesh (90th percentile of its skin vertices' distance from the bone line; a
ring of eight lines round the bone line) against the gun's triangles; a joint stops before
any part would enter the gun. The first `arms_knuckle_skip` of the first
phalanx sits inside the palm and is not tested. The palm is seated
`arms_palm_skin` off the grip so the fingers start clear of it.

## The no-crossing rule

On top of the tube test, the hand's real mesh is checked: each finger's
skinned triangles, posed, in the gun's frame. A pose is rejected if any edge
of the finger's mesh passes through a gun triangle, or any edge of the gun's
mesh passes through a finger triangle. Touching is allowed; crossing never.
Before the fingers close, the whole hand backs off its grip along the palm's
normal until the open fingers cross nothing.

## Proportions

Measured on the model (right hand): middle + distal phalanx = 1.07 (index),
1.14 (middle), 1.06 (ring), 1.20 (little) times the proximal phalanx. Studies
put this near 1.0, with the little finger the most variable, so the model's
fingers were left as they are. The thumbs are shortened to
`arms_thumb_length` (the user's call: they read too long).

## Sources

- Kamper et al., finger joint coupling under tendon loading (cadaver): https://link.springer.com/doi/10.1186/1749-799X-3-27
- Normative active finger range of motion: https://pmc.ncbi.nlm.nih.gov/articles/PMC11436331
- Pooled finger ROM table: https://pmc.ncbi.nlm.nih.gov/articles/PMC2483967
- Phalanx lengths and the Fibonacci / Littler question: https://doaj.org/article/95331bf144cd41be9b36472cfdb3530b and https://pmc.ncbi.nlm.nih.gov/articles/PMC6760092
