"""Generates levels/gordons/gordons_market.tscn: Gordons Market, Port Moresby,
after hours (the market closed for the night, stalls under tarps, no vendors).

Usage: python tools/gen_gordons.py levels/gordons/gordons_market.tscn

Layout from the real site (OpenStreetMap: the market hall beside Geauta
Drive, car park and wholesale sheds to the west, the PMV interchange to the
south), compressed a little so fights stay close:
  * the two-storey market hall (56 x 52 m): concrete columns and deck below,
    an open upper floor under a steel roof, two internal stairs, an outside
    ramp up the south face, and a footbridge west to a stair tower;
  * the south plaza with planters, a monument stone and a mural wall;
  * the PMV interchange beyond it;
  * the car park (north-west) and open-sided wholesale sheds (south-west);
  * Geauta Drive along the east side, a median of jersey barriers;
  * shops along the service road to the north.
x is east, -z is north. Every collider is here (CSG boxes, or static bodies
for stall rows, sacks, sandbags and barriers, whose look is built by
levels/gordons/gordons_market.gd).
"""
import math
import pathlib
import sys

out = pathlib.Path(sys.argv[1])

DECK = 4.8  # upper floor level (top of the deck slab)
SLAB = 0.4
HX0, HX1, HZ0, HZ1 = -18.0, 38.0, -30.0, 22.0  # the market hall
ROOF_EAVES = 10.4

boxes = []   # (name, center, size, material, surface, params, rows)
bodies = []  # (name, center, size, group, surface)


def box(name, x, y_bottom, z, sx, sy, sz, material, surface, rows=None, **params):
    boxes.append((name, (x, y_bottom + sy / 2.0, z), (sx, sy, sz), material, surface, params, rows))


def span(name, x0, x1, y0, y1, z0, z1, material, surface, **params):
    """A box from corner to corner."""
    box(name, (x0 + x1) / 2, y0, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, material, surface, **params)


def body(name, x, y_bottom, z, sx, sy, sz, group, surface):
    bodies.append((name, (x, y_bottom + sy / 2.0, z), (sx, sy, sz), group, surface))


def ramp(name, x0, z0, y0, x1, z1, y1, width, material, surface, thickness=0.3):
    """A sloped slab whose top runs from (x0, y0, z0) to (x1, y1, z1)."""
    if y1 < y0:  # always work low end -> high end
        x0, z0, y0, x1, z1, y1 = x1, z1, y1, x0, z0, y0
    dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    run = math.hypot(dx, dz)
    length = math.hypot(run, dy)
    angle = math.atan2(dy, run)
    c, s = math.cos(angle), math.sin(angle)
    if abs(dz) >= abs(dx):
        # Runs along Z: tilt about X. Rising towards -z needs the local +z end down.
        a = angle if dz < 0 else -angle
        ca, sa = math.cos(a), math.sin(a)
        rows = (1, 0, 0, 0, ca, -sa, 0, sa, ca)
        size = (width, thickness, length)
        normal = (0.0, ca, sa)  # local +y in world
    else:
        a = angle if dx > 0 else -angle
        ca, sa = math.cos(a), math.sin(a)
        rows = (ca, -sa, 0, sa, ca, 0, 0, 0, 1)
        size = (length, thickness, width)
        normal = (-sa, ca, 0.0)
    mid = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    center = tuple(mid[i] - normal[i] * thickness / 2 for i in range(3))
    boxes.append((name, center, size, material, surface, {}, rows))


def railing(name, x0, z0, x1, z1, y, material="Railing", height=1.1):
    """Waist-high railing (a thin wall: cover and a fall guard)."""
    if abs(x1 - x0) >= abs(z1 - z0):
        span(name, min(x0, x1), max(x0, x1), y, y + height, z0 - 0.05, z0 + 0.05, material, "steel")
    else:
        span(name, x0 - 0.05, x0 + 0.05, y, y + height, min(z0, z1), max(z0, z1), material, "steel")


# --- Ground -----------------------------------------------------------------------
span("Ground", -72, 72, -1, 0, -62, 64, "Asphalt", "concrete")
span("Plaza", -20, 44, -0.99, 0.01, 22, 44, "Pavers", "concrete")
span("HallFloor", HX0, HX1, -0.99, 0.02, HZ0, HZ1, "HallFloor", "concrete")
span("Road", 46, 62, -0.98, 0.0, -62, 64, "Road", "concrete")
span("VergeE", 62, 72, -0.98, 0.0, -62, 64, "Grass", "dirt")
span("ShedYard", -66, -28, -0.985, 0.0, 2, 44, "Dirt", "dirt")

# --- The market hall ----------------------------------------------------------------
# Ground-floor columns (concrete) on an 8 x ~8.7 m grid; upper columns (steel) carry the roof.
xs = [HX0 + 8 * i for i in range(8)]
zs = [HZ0 + (HZ1 - HZ0) / 6 * i for i in range(7)]
for i, x in enumerate(xs):
    for j, z in enumerate(zs):
        box(f"Col{i}_{j}", x, 0, z, 0.6, DECK - SLAB, 0.6, "Concrete", "concrete")
        if i % 2 == 0 or i == len(xs) - 1 or j in (0, len(zs) - 1):
            box(f"Post{i}_{j}", x, DECK, z, 0.3, ROOF_EAVES - DECK, 0.3, "SteelPaint", "steel")

# Deck slab with two stair wells: west (x -16..-12, z -3..11), east (x 32..36, z -27..-13).
# 2.5 m walkways between each well and the hall edge (1.5 m pinched soldiers against the posts).
wells = [(-15.5, -10.5, -3.0, 11.0), (30.5, 35.5, -27.0, -13.0)]
cuts = sorted({HX0, HX1, *[w[0] for w in wells], *[w[1] for w in wells]})
n = 0
for a, b in zip(cuts, cuts[1:]):
    zcuts = [HZ0, HZ1]
    for w in wells:
        if w[0] <= a and b <= w[1]:
            zcuts += [w[2], w[3]]
    zcuts = sorted(zcuts)
    for k, (z0, z1) in enumerate(zip(zcuts, zcuts[1:])):
        if any(w[0] <= a and b <= w[1] and w[2] <= z0 and z1 <= w[3] for w in wells):
            continue  # the hole
        span(f"Deck{n}", a, b, DECK - SLAB, DECK, z0, z1, "Deck", "concrete")
        n += 1
# Stairs (steep ramps, stepped look added by the dressing) up through the wells.
ramp("StairW", -13, 13, 0.0, -13, -3, DECK, 3.0, "Stair", "concrete")
# Its foot faces the open floor (against the north fence there was no way round onto it).
ramp("StairE", 33, -10.5, 0.0, 33, -27, DECK, 3.0, "Stair", "concrete")
railing("WellWRailW", -15.5, -3, -15.5, 11, DECK)
railing("WellWRailE", -10.5, -3, -10.5, 11, DECK)
railing("WellWRailS", -15.5, 11, -10.5, 11, DECK)
railing("WellERailW", 30.5, -27, 30.5, -13, DECK)
railing("WellERailE", 35.5, -27, 35.5, -13, DECK)
railing("WellERailS", 30.5, -13, 35.5, -13, DECK)

# Upper-floor edge railings, open where the ramp landing and the footbridge join.
railing("UpRailN", HX0, HZ0, HX1, HZ0, DECK)
railing("UpRailE", HX1, HZ0, HX1, HZ1, DECK)
railing("UpRailS1", HX0, HZ1, 2, HZ1, DECK)
railing("UpRailS2", 8, HZ1, HX1, HZ1, DECK)
railing("UpRailW1", HX0, HZ0, HX0, -6.5, DECK)
railing("UpRailW2", HX0, -3.5, HX0, HZ1, DECK)
# Ground-floor perimeter: galvanised fence with entrances.
for name, x0, z0, x1, z1 in [
    ("FenceN1", HX0, HZ0, -4, HZ0), ("FenceN2", 2, HZ0, 22, HZ0), ("FenceN3", 28, HZ0, HX1, HZ0),
    ("FenceE1", HX1, HZ0, HX1, -14), ("FenceE2", HX1, -9, HX1, 6), ("FenceE3", HX1, 11, HX1, HZ1),
    ("FenceS1", HX0, HZ1, -6, HZ1), ("FenceS2", 0, HZ1, 14, HZ1), ("FenceS3", 20, HZ1, HX1, HZ1),
    ("FenceW1", HX0, HZ0, HX0, -20), ("FenceW2", HX0, -14, HX0, 2), ("FenceW3", HX0, 8, HX0, HZ1),
]:
    railing(name, x0, z0, x1, z1, 0.0, "Fence", 1.2)
# Admin and toilet block, ground floor north-west: rooms with doorways (gaps).
for name, x0, x1, z0, z1 in [
    ("AdminN", -17.7, -6, -29.7, -29.4), ("AdminE1", -6.3, -6, -29.4, -26), ("AdminE2", -6.3, -6, -24, -21.8),
    ("AdminS1", -17.7, -13, -21.8, -21.5), ("AdminS2", -11, -6.3, -21.8, -21.5), ("AdminMid", -12.15, -11.85, -29.4, -24),
]:
    span(name, x0, x1, 0, DECK - SLAB, z0, z1, "Admin", "concrete")

# Outside ramp up the south face (rising east to west), landing onto the deck.
ramp("RampSouth", 36, 25.5, 0.0, 9, 25.5, DECK, 3.0, "Deck", "concrete")
span("RampLanding", 2, 9, DECK - SLAB, DECK, HZ1, 27, "Deck", "concrete")
railing("RampRailOut", 9, 27.05, 36, 27.05, 0.0, "Railing", 1.1)  # low along the ground; the dressing slopes it
railing("LandingRailS", 2, 27, 9, 27, DECK)
railing("LandingRailW", 2, HZ1, 2, 27, DECK)

# Footbridge west from the upper floor to a stair tower over the car park lane.
span("Bridge", -40, HX0, DECK - SLAB, DECK, -6.5, -3.5, "Deck", "concrete")
railing("BridgeRailN", -37, -6.5, HX0, -6.5, DECK)
railing("BridgeRailS", -37, -3.5, HX0, -3.5, DECK)
span("TowerLanding", -43, -37, DECK - SLAB, DECK, -8, -3.5, "Deck", "concrete")
ramp("TowerStair", -41, -8, DECK, -41, -21, 0.0, 3.0, "Stair", "concrete")
for name, x, z in [("TowerPostA", -43, -8), ("TowerPostB", -37, -8), ("TowerPostC", -43, -3.5), ("TowerPostD", -37, -3.5),
                   ("BridgePier", -29, -5)]:
    box(name, x, 0, z, 0.5, DECK - SLAB, 0.5, "Concrete", "concrete")
railing("TowerRailW", -43, -8, -43, -3.5, DECK)
railing("TowerRailS", -43, -3.5, -37, -3.5, DECK)

# Stall rows: tables in runs of three (bodies; tables, produce and tarps dressed in).
def stall_rows(prefix, y, x0, x1, z0, z1, skip, sacks_every=0):
    """Runs of three tables. Every `sacks_every`-th run is a 1.8 m pile of sacks
    instead: full cover (tables are open underneath, so they are none)."""
    k = 0
    z = z0
    while z < z1:
        x = x0
        while x + 7.2 <= x1:
            cx, cz = x + 3.6, z
            if not any(s[0] <= cx <= s[1] and s[2] <= cz <= s[3] for s in skip):
                if sacks_every and k % sacks_every == 1:
                    body(f"{prefix}Sacks{k}", cx, y, cz, 6.0, 1.8, 1.2, "sacks", "sandbag")
                else:
                    body(f"{prefix}{k}", cx, y, cz, 7.2, 0.85, 1.1, "stall_row", "wood")
                k += 1
            x += 9.2  # 2 m aisle between runs
        z += 4.2  # 3.1 m aisle between rows
    return k


keep_clear = [(-16, -9.5, -4, 14), (29.5, 37, -30, -7), (-18, -5, -30, -21), (-4, 2, -31, -24), (-19, -14, -21, -13)]
stall_rows("StallG", 0.0, HX0 + 1.5, HX1 - 1.5, HZ0 + 3.0, HZ1 - 2.0, keep_clear, sacks_every=5)
# Lock-up storerooms on the upper floor (solid rooms to fight round), where stall runs would be.
kiosks = [("KioskA", 5.5, -14.4), ("KioskB", 23.9, 6.6)]
for name, x, z in kiosks:
    box(name, x, DECK, z, 3.6, 2.6, 3.0, "Admin", "concrete")
stall_rows("StallU", DECK, HX0 + 1.5, HX1 - 1.5, HZ0 + 3.0, HZ1 - 2.0,
           [(-16.5, -9.5, -5, 13), (29.5, 37, -30, -11)] + [(x - 1, x + 1, z - 1, z + 1) for _, x, z in kiosks], sacks_every=4)

# --- The plaza ----------------------------------------------------------------------
for name, x0, x1, z0, z1 in [("PlanterA", -16, -4, 30, 33), ("PlanterB", 4, 16, 30, 33), ("PlanterC", 22, 32, 34, 37),
                             ("PlanterD", -16, -8, 39, 42), ("PlanterE", 10, 20, 39, 42)]:
    span(name, x0, x1, 0, 0.55, z0, z1, "Planter", "concrete")
box("Monument", 0, 0, 36, 1.6, 0.6, 1.6, "Concrete", "concrete")  # plinth; the stone is dressed on
box("MonumentStone", 0, 0.6, 36, 1.2, 1.0, 1.0, "Stone", "concrete")
span("MuralWall", 30, 42, 0, 3.6, 41.6, 42.0, "Mural", "concrete")

# --- PMV interchange (south) ----------------------------------------------------------
span("Interchange", -44, 40, -0.985, 0.0, 46, 62, "Road", "concrete")
# Planted islands between the bays: a real obstacle (0.5 m), not a kerb soldiers snag on.
for name, x, z, sx, sz in [("IslandA", -20, 52, 24, 1.2), ("IslandB", 14, 52, 24, 1.2)]:
    box(name, x, 0, z, sx, 0.5, sz, "Planter", "concrete")

# --- Car park (north-west) and the wholesale sheds (south-west) ------------------------------
span("CarPark", -68, -22, -0.985, 0.0, -56, -10, "Asphalt", "concrete")
for name, x0, x1 in [("ShedA", -64, -52), ("ShedB", -46, -34)]:
    for i in range(6):
        z = 6 + i * 6.4
        for xx in (x0, x1):
            box(f"{name}Post{i}{'W' if xx == x0 else 'E'}", xx, 0, z, 0.3, 4.2, 0.3, "SteelPaint", "steel")
    # Sacks of buai, rice and copra stacked down the middle, gaps to run through.
    for i, (z0, z1) in enumerate([(8, 14), (17, 23), (26, 32), (35, 39)]):
        body(f"{name}Sacks{i}", (x0 + x1) / 2, 0, (z0 + z1) / 2, 2.4, 1.8, z1 - z0, "sacks", "sandbag")  # full cover: a standing head stays below the top
    body(f"{name}SacksW", x0 + 1.6, 0, 22, 1.4, 1.1, 4.0, "sacks", "sandbag")  # half cover
    body(f"{name}SacksE", x1 - 1.6, 0, 30, 1.4, 1.1, 3.0, "sacks", "sandbag")

# --- Shops along the service road (north), facing south ------------------------------------
stores = [("KaiBar", -50, -55, 12, 8, "KAI BAR", "Color(0.85, 0.62, 0.16, 1)"),
          ("HadwiaStoa", -32, -55, 14, 8, "HADWIA STOA", "Color(0.2, 0.36, 0.62, 1)"),
          ("MarasinStoa", -12, -55, 10, 8, "MARASIN STOA", "Color(0.82, 0.83, 0.78, 1)"),
          ("TradeStoa", 8, -55, 14, 8, "TRADE STOA", "Color(0.66, 0.16, 0.12, 1)"),
          ("Wholsel", 28, -55, 14, 8, "WHOLSEL KAI", "Color(0.15, 0.5, 0.3, 1)")]
# Plaza and interchange: security booths at the entrances and two closed kiosks
# (dressed as shopfronts), real cover where the planters and islands are too low.
# (name, x, z, sx, sz, sign, colour, facing, height)
plaza_stores = [("BoothW", -18, 26, 2.4, 2.4, "SEKURITI", "Color(0.2, 0.3, 0.55, 1)", "Vector3(1, 0, 0)", 2.9),
                ("BoothE", 42, 26, 2.4, 2.4, "SEKURITI", "Color(0.2, 0.3, 0.55, 1)", "Vector3(-1, 0, 0)", 2.9),
                ("KioskFon", -8, 37, 3.2, 2.4, "FON KAD", "Color(0.85, 0.15, 0.12, 1)", "Vector3(1, 0, 0)", 3.0),
                ("KioskBuai", 34, 32.5, 3.2, 2.4, "BUAI STOA", "Color(0.15, 0.5, 0.3, 1)", "Vector3(-1, 0, 0)", 3.0)]
for name, x, z, sx, sz, sign, color in stores:
    box(name, x, 0, z, sx, 3.4, sz, "Store" + name, "concrete")
for name, x, z, sx, sz, sign, color, facing, height in plaza_stores:
    box(name, x, 0, z, sx, height, sz, "Store" + name, "concrete")
stores = [st + ("Vector3(0, 0, 1)",) for st in stores] + [st[:8] for st in plaza_stores]
# Produce crates stacked for the morning trucks: full cover (1.8 m), crate look.
for name, x, z, seed in [("CratesPlazaA", 6, 28.6, 31), ("CratesPlazaB", -2, 45.2, 32), ("CratesPlazaC", 24, 45.2, 33)]:
    box(name, x, 0, z, 2.4, 1.8, 1.2, "Crate", "wood", box_size=(2.4, 1.8, 1.2), seed=seed)
# The west PMV shelter gets a solid back wall (the east one has the bus in its bay).
span("ShelterWallW", -26, -14, 0, 2.2, 55.4, 55.6, "Concrete", "concrete")

# --- Boundary: concrete fence walls (west, south) and the road's far verge fence (east) ---------
span("WallWest", -72, -70, 0, 3.0, -62, 64, "Boundary", "concrete")
span("WallSouth", -70, 72, 0, 3.0, 62, 64, "Boundary", "concrete")
span("WallNorth", -70, 72, 0, 3.0, -62, -59, "Boundary", "concrete")
span("FenceEast", 70, 72, 0, 3.0, -59, 62, "Boundary", "concrete")

# --- Cover dotted round the outside ---------------------------------------------------------
for name, x, z, sx, sz in [("SandNorth1", -4, -40, 4, 0.4), ("SandNorth2", 20, -38, 4, 0.4), ("SandRoad", 42, -12, 0.4, 4),
                           ("SandShed", -26, 24, 0.4, 4), ("SandCarPark", -30, -30, 4, 0.4), ("SandPlaza", 38, 30, 0.4, 3)]:
    body(name, x, 0, z, sx, 1.0, sz, "sandbag_wall", "sandbag")
for i, z in enumerate(range(-56, 60, 4)):
    if -6 < z < 2:
        continue  # a gap to cross the median
    body(f"Median{i}", 54, 0, z + 2, 0.6, 1.1, 2.0, "jersey_barrier", "concrete")
for name, x, z in [("BarrierN1", 10, -44), ("BarrierW1", -26, -2), ("BarrierS1", 30, 46), ("BarrierS2", -32, 46)]:
    body(name, x, 0, z, 2.0, 1.1, 0.6, "jersey_barrier", "concrete")

# Light poles: (name, x, z, arm direction or None for "towards the middle").
poles = [("PoleCarParkA", -50, -40, None), ("PoleCarParkB", -30, -18, None), ("PolePlazaW", -18, 40, None),
         ("PolePlazaE", 40, 40, None), ("PoleInterA", -30, 56, None), ("PoleInterB", 0, 56, None),
         ("PoleInterC", 28, 56, None), ("PoleShedYard", -48, 42, None), ("PoleNorth", 4, -42, None),
         ("StreetA", 63.4, -40, "Vector3(-1, 0, 0)"), ("StreetB", 63.4, 0, "Vector3(-1, 0, 0)"),
         ("StreetC", 63.4, 40, "Vector3(-1, 0, 0)"), ("StreetD", 44.6, -20, "Vector3(1, 0, 0)"),
         ("StreetE", 44.6, 20, "Vector3(1, 0, 0)")]

# Vehicles: Kamfot taxis, PMVs and two trucks (name, x, z, yaw rows, ...).
EAST = "0, 0, 1, 0, 1, 0, -1, 0, 0"
NORTH = "1, 0, 0, 0, 1, 0, 0, 0, 1"
WEST = "0, 0, -1, 0, 1, 0, 1, 0, 0"
taxis = [("Taxi1", -60, -46, NORTH, "T 1146"), ("Taxi2", -56, -46, NORTH, "T 2207"), ("Taxi3", -44, -46, NORTH, "T 3381"),
         ("Taxi4", -36, -30, EAST, "T 4419"), ("Taxi5", 30, 58, EAST, "T 5520"), ("Taxi6", 50, -30, NORTH, "T 6634")]
buses = [("PmvRoute11", -28, 49, EAST, "Color(0.16, 0.6, 0.6, 1)", "11", "P 1188", True),
         ("PmvRoute9", -6, 49, EAST, "Color(0.82, 0.45, 0.12, 1)", "9", "P 9071", False),
         ("PmvRoute4", 18, 55, WEST, "Color(0.52, 0.52, 0.82, 1)", "4", "P 3908", True),
         ("PmvRoute7", 58, 22, NORTH, "Color(0.7, 0.18, 0.15, 1)", "7", "P 7742", True)]
trucks = [("TruckA", -58, 0, NORTH, "Color(0.82, 0.8, 0.74, 1)"), ("TruckB", -40, 44, EAST, "Color(0.2, 0.32, 0.55, 1)")]

# Enemy spawns: (name, x, y, z, kind, level).
spawns = [
    # 1 - PMV interchange and plaza
    ("L1Rifle1", -10, 0, 50, "rifleman", 1), ("L1Rifle2", 10, 0, 48, "rifleman", 1), ("L1Rifle3", 20, 0, 32, "rifleman", 1),
    ("L1Rusher1", 0, 0, 30, "rusher", 1), ("L1Rusher2", -25, 0, 53, "rusher", 1), ("L1Machete1", 30, 0, 40, "machete", 1),
    # 2 - the wholesale sheds
    ("L2Rifle1", -56, 0, 12, "rifleman", 2), ("L2Rifle2", -36, 0, 30, "rifleman", 2), ("L2Rifle3", -58, 0, 34, "rifleman", 2),
    ("L2Rifle4", -44, 0, 8, "rifleman", 2), ("L2Machete1", -52, 0, 22, "machete", 2), ("L2Machete2", -38, 0, 18, "machete", 2),
    ("L2Machete3", -60, 0, 28, "machete", 2), ("L2Rusher1", -30, 0, 2, "rusher", 2),
    # 3 - the market floor
    ("L3Rifle1", -6, 0, -20, "rifleman", 3), ("L3Rifle2", 10, 0, -6, "rifleman", 3), ("L3Rifle3", 26, 0, -24, "rifleman", 3),
    ("L3Rifle4", 30, 0, 10, "rifleman", 3), ("L3Rifle5", 0, 0, 14, "rifleman", 3), ("L3Rusher1", 16, 0, -12.3, "rusher", 3),
    ("L3Rusher2", -10, 0, 4, "rusher", 3), ("L3Machete1", 20, 0, 4, "machete", 3), ("L3Machete2", 6, 0, 18, "machete", 3),
    # 4 - top floor and the footbridge
    ("L4Rifle1", 0, DECK, -20, "rifleman", 4), ("L4Rifle2", 19, DECK, -12.3, "rifleman", 4), ("L4Rifle3", 30, DECK, 10, "rifleman", 4),
    ("L4Rifle4", 8, DECK, 12, "rifleman", 4), ("L4Rifle5", -8, DECK, -24, "rifleman", 4), ("L4Rifle6", -30, DECK, -5, "rifleman", 4),
    ("L4Rusher1", 14, DECK, 0, "rusher", 4), ("L4Rusher2", 26, DECK, -24, "rusher", 4),
    ("L4Machete1", -6, DECK, 4, "machete", 4), ("L4Machete2", 2, DECK, -4, "machete", 4),
]

materials = [
    ("Asphalt", "asphalt", {}),
    ("Road", "asphalt", {"lane_spacing": 3.5, "lane_offset": -54.0, "puddles": 0.2}),
    ("Pavers", "concrete", {"base_color": "Color(0.66, 0.64, 0.6, 1)", "panel_width": 1.2, "grime_height": 0.0}),
    ("HallFloor", "concrete", {"base_color": "Color(0.5, 0.49, 0.46, 1)", "panel_width": 4.0, "grime_height": 0.0}),
    ("Concrete", "concrete", {"base_color": "Color(0.72, 0.71, 0.68, 1)", "panel_width": 0.0}),
    ("Deck", "concrete", {"base_color": "Color(0.68, 0.67, 0.64, 1)", "panel_width": 0.0, "grime_height": 0.0}),
    ("Stair", "concrete", {"base_color": "Color(0.6, 0.59, 0.56, 1)", "panel_width": 0.0, "grime_height": 0.0}),
    ("Admin", "concrete", {"base_color": "Color(0.86, 0.85, 0.8, 1)", "panel_width": 0.0, "grime_height": 0.8}),
    ("Planter", "concrete", {"base_color": "Color(0.78, 0.77, 0.73, 1)", "panel_width": 0.0, "grime_height": 0.3}),
    ("Stone", "concrete", {"base_color": "Color(0.82, 0.8, 0.76, 1)", "panel_width": 0.0, "grime_height": 0.0}),
    ("Mural", "concrete", {"base_color": "Color(0.2, 0.42, 0.24, 1)", "panel_width": 0.0, "grime_height": 0.4}),
    ("Boundary", "concrete", {"base_color": "Color(0.62, 0.6, 0.56, 1)", "panel_width": 3.0, "grime_height": 1.0}),
    ("Dirt", "dirt", {}),
    ("Grass", "dirt", {"grass": 1.0}),
    ("Crate", "crate", {}),
] + [("Store" + st[0], "concrete", {"base_color": st[6], "panel_width": 0.0, "grime_height": 0.9}) for st in stores]

JERSEY = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.16, 0.3), (0.09, 1.1), (-0.09, 1.1), (-0.16, 0.3), (-0.3, 0.08)]


def body_shape(name, size, group):
    sx, sy, sz = size
    if group == "jersey_barrier":
        long_x = sx >= sz
        length = sx if long_x else sz
        points = []
        for end in (-length / 2, length / 2):
            for u, v in JERSEY:
                points.extend((end, v - sy / 2, u) if long_x else (u, v - sy / 2, end))
        return (f'[sub_resource type="ConvexPolygonShape3D" id="Shape{name}"]\n'
                f'points = PackedVector3Array({", ".join(f"{c:g}" for c in points)})\n')
    return f'[sub_resource type="BoxShape3D" id="Shape{name}"]\nsize = Vector3({sx:g}, {sy:g}, {sz:g})\n'


def look_basis_rows(direction):
    length = math.sqrt(sum(c * c for c in direction))
    z = [-c / length for c in direction]
    up = [0.0, 1.0, 0.0]
    x = [up[1] * z[2] - up[2] * z[1], up[2] * z[0] - up[0] * z[2], up[0] * z[1] - up[1] * z[0]]
    xl = math.sqrt(sum(c * c for c in x))
    x = [c / xl for c in x]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    return [[x[i], y[i], z[i]] for i in range(3)]


def vec(v):
    return "Vector3(%s)" % ", ".join(f"{c:g}" for c in v)


# Respawn candidates (x, facing degrees, z; 0 = north) and buai bundles.
safe_spots = [(44, 90, 54), (60, 90, 50), (60, 90, -40), (-12, 90, 36.5), (-40, -90, -25), (-64, -90, -40), (-64, 180, 50),
              (20, 0, 58), (-14, 0, 16), (40, 0, 30), (66, 180, -50)]
buai_spots = [(-14, 0, 36), (24, 0, 28), (-54, 0, 16), (-40, 0, 36), (4, 0, -8), (24, 0, -16.5), (6, DECK, 4),
              (-4, DECK, -16), (-34, DECK, -5), (-46, 0, -20)]

lines = []
w = lines.append
w("[gd_scene format=3]")
w("")
w('[ext_resource type="Script" path="res://levels/gordons/gordons_market.gd" id="1_level"]')
w('[ext_resource type="PackedScene" path="res://player/player.tscn" id="3_player"]')
w('[ext_resource type="PackedScene" path="res://ui/debug_overlay.tscn" id="4_overlay"]')
w('[ext_resource type="PackedScene" path="res://ui/hud.tscn" id="5_hud"]')
w('[ext_resource type="Texture2D" path="res://levels/port/materials/noise.tres" id="6_noise"]')
w('[ext_resource type="Resource" path="res://data/levels/gordons_campaign.tres" id="7_campaign"]')
for shader in ["asphalt", "concrete", "dirt", "crate"]:
    w(f'[ext_resource type="Shader" path="res://levels/port/materials/{shader}.gdshader" id="shader_{shader}"]')
w("")
w('[sub_resource type="ProceduralSkyMaterial" id="SkyMaterial"]')
w("sky_top_color = Color(0.06, 0.08, 0.19, 1)")
w("sky_horizon_color = Color(0.66, 0.38, 0.26, 1)")
w("sky_curve = 0.09")
w("ground_bottom_color = Color(0.02, 0.02, 0.025, 1)")
w("ground_horizon_color = Color(0.32, 0.22, 0.17, 1)")
w("sun_angle_max = 12.0")
w("sun_curve = 0.06")
w("")
w('[sub_resource type="Sky" id="Sky"]')
w('sky_material = SubResource("SkyMaterial")')
w("")
w('[sub_resource type="Environment" id="Environment"]')
w("background_mode = 2")
w('sky = SubResource("Sky")')
w("ambient_light_source = 3")
w("ambient_light_color = Color(0.38, 0.37, 0.48, 1)")
w("ambient_light_sky_contribution = 0.55")
w("ambient_light_energy = 1.9")
w("tonemap_mode = 2")
w("tonemap_exposure = 1.15")
w("fog_enabled = true")
w("fog_light_color = Color(0.34, 0.27, 0.27, 1)")
w("fog_density = 0.008")
w("fog_sun_scatter = 0.35")
w("fog_aerial_perspective = 0.6")
w("fog_sky_affect = 0.25")
w("adjustment_enabled = true")
w("adjustment_saturation = 1.08")
w("")
w('[sub_resource type="NavigationMesh" id="NavMesh"]')
w("cell_size = 0.125")
w("cell_height = 0.125")
w("agent_height = 1.75")
w("agent_radius = 0.375")
w("agent_max_climb = 0.25")
w("agent_max_slope = 46.0")
# Drop isolated islands under ~14 m2 (value squared = cells of 0.125 m): the tops of stall
# tables, cars and buses, where a cover point could be chosen that nobody can reach.
w("region_min_size = 30.0")
w("geometry_parsed_geometry_type = 1")
w("geometry_collision_mask = 33")  # world + guard: railings are walls to the navmesh
w("")
for name, shader, params in materials:
    w(f'[sub_resource type="ShaderMaterial" id="{name}"]')
    w(f'shader = ExtResource("shader_{shader}")')
    w('shader_parameter/noise_tex = ExtResource("6_noise")')
    for key, value in params.items():
        w(f"shader_parameter/{key} = {value}")
    w("")
for mat, color, metallic, rough in [("SteelPaint", "Color(0.86, 0.87, 0.86, 1)", 0.4, 0.45),
                                    ("Railing", "Color(0.8, 0.82, 0.82, 1)", 0.6, 0.4),
                                    ("Fence", "Color(0.62, 0.64, 0.64, 1)", 0.7, 0.45),
                                    ("PoleSteel", "Color(0.32, 0.33, 0.34, 1)", 0.6, 0.5)]:
    w(f'[sub_resource type="StandardMaterial3D" id="{mat}"]')
    w(f"albedo_color = {color}")
    w(f"metallic = {metallic}")
    w(f"roughness = {rough}")
    w("")
for name, center, size, group, surface in bodies:
    w(body_shape(name, size, group))
w('[sub_resource type="BoxShape3D" id="TaxiShape"]')
w("size = Vector3(1.7, 1.44, 4.4)")
w("")
w('[sub_resource type="BoxShape3D" id="BusShape"]')
w("size = Vector3(2.05, 2.5, 7)")
w("")
w('[sub_resource type="BoxShape3D" id="TruckShape"]')
w("size = Vector3(2.2, 2.6, 7.2)")
w("")
w('[node name="GordonsMarket" type="Node3D"]')
w('script = ExtResource("1_level")')
w("bounds = AABB(-70, -0.5, -60, 140, 7.5, 122)")
w('campaign = ExtResource("7_campaign")')
w("lamp_lit_count = 4")
w(f"cover_floors = PackedFloat32Array(0, {DECK:g})")
w("safe_spots = PackedVector3Array(%s)" % ", ".join(f"{a:g}, {b:g}, {c:g}" for a, b, c in safe_spots))
w("buai_spots = PackedVector3Array(%s)" % ", ".join(f"{a:g}, {b:g}, {c:g}" for a, b, c in buai_spots))
w("")
w('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
w('environment = SubResource("Environment")')
w("")
# Low sun in the west: the light comes in under the hall's roof from the car park side.
rows = look_basis_rows([0.88, -0.2, 0.43])
flat = ", ".join(f"{c:.4f}" for row in rows for c in row)
w('[node name="Sun" type="DirectionalLight3D" parent="."]')
w(f"transform = Transform3D({flat}, 0, 20, 0)")
w("light_color = Color(1, 0.6, 0.36, 1)")
w("light_energy = 1.25")
w("shadow_enabled = true")
w("shadow_bias = 0.04")
w("shadow_normal_bias = 1.5")
w("directional_shadow_mode = 0")
w("directional_shadow_max_distance = 50.0")
w("")
w('[node name="Player" parent="." instance=ExtResource("3_player")]')
w(f"transform = Transform3D({', '.join(f'{c:g}' for c in (0, 0, 1, 0, 1, 0, -1, 0, 0))}, 44, 0, 54)")  # stage 1 start
w("")
w('[node name="HUD" parent="." instance=ExtResource("5_hud")]')
w("")
w('[node name="DebugOverlay" parent="." instance=ExtResource("4_overlay")]')
w("")
w('[node name="Navigation" type="NavigationRegion3D" parent="."]')
w('navigation_mesh = SubResource("NavMesh")')
w("")
for name, (x, y, z), (sx, sy, sz), group, surface in bodies:
    w(f'[node name="{name}" type="StaticBody3D" parent="Navigation" groups=["{group}"]]')
    w(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, {y:g}, {z:g})")
    w(f'metadata/surface = "{surface}"')
    w(f"metadata/size = Vector3({sx:g}, {sy:g}, {sz:g})")
    w("")
    w(f'[node name="Shape" type="CollisionShape3D" parent="Navigation/{name}"]')
    w(f'shape = SubResource("Shape{name}")')
    w("")
for name, (x, y, z), (sx, sy, sz), material, surface, params, rows in boxes:
    store = next((st for st in stores if st[0] == name), None)
    groups = ' groups=["store"]' if store else ""
    w(f'[node name="{name}" type="CSGBox3D" parent="Navigation"{groups}]')
    basis = ", ".join(f"{c:g}" for c in (rows or (1, 0, 0, 0, 1, 0, 0, 0, 1)))
    w(f"transform = Transform3D({basis}, {x:g}, {y:g}, {z:g})")
    if store:
        w(f'metadata/sign = "{store[5]}"')
        w(f"metadata/sign_color = {store[6]}")
        w(f"metadata/facing = {store[7]}")
    for key, value in params.items():
        w(f"instance_shader_parameters/{key} = {vec(value) if isinstance(value, tuple) else f'{value:g}'}")
    w("use_collision = true")
    if material in ("Railing", "Fence"):
        w("collision_layer = 32")  # PhysicsLayers.GUARD: stops walkers, not bullets or sight
    w(f"size = Vector3({sx:g}, {sy:g}, {sz:g})")
    w(f'material = SubResource("{material}")')
    w(f'metadata/surface = "{surface}"')
    w("")
for name, x, z, arm in poles:
    w(f'[node name="{name}" type="CSGCylinder3D" parent="Navigation" groups=["lamp_pole"]]')
    w(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, 4, {z:g})")
    if arm:
        w(f"metadata/arm = {arm}")
    w("use_collision = true")
    w("radius = 0.12")
    w("height = 8.0")
    w("sides = 10")
    w('material = SubResource("PoleSteel")')
    w('metadata/surface = "steel"')
    w("")
for name, x, z, rows, livery, route, plate, headlights in buses:
    w(f'[node name="{name}" type="StaticBody3D" parent="Navigation" groups=["pmv_bus"]]')
    w(f"transform = Transform3D({rows}, {x:g}, 0, {z:g})")
    w('metadata/surface = "vehicle"')
    w(f"metadata/livery = {livery}")
    w(f'metadata/route = "{route}"')
    w(f'metadata/plate = "{plate}"')
    w(f"metadata/headlights = {'true' if headlights else 'false'}")
    w("")
    w(f'[node name="Shape" type="CollisionShape3D" parent="Navigation/{name}"]')
    w("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.25, 0)")
    w('shape = SubResource("BusShape")')
    w("")
for name, x, z, rows, plate in taxis:
    w(f'[node name="{name}" type="StaticBody3D" parent="Navigation" groups=["taxi"]]')
    w(f"transform = Transform3D({rows}, {x:g}, 0, {z:g})")
    w('metadata/surface = "vehicle"')
    w(f'metadata/plate = "{plate}"')
    w("")
    w(f'[node name="Shape" type="CollisionShape3D" parent="Navigation/{name}"]')
    w("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.72, 0)")
    w('shape = SubResource("TaxiShape")')
    w("")
for name, x, z, rows, color in trucks:
    w(f'[node name="{name}" type="StaticBody3D" parent="Navigation" groups=["truck"]]')
    w(f"transform = Transform3D({rows}, {x:g}, 0, {z:g})")
    w('metadata/surface = "vehicle"')
    w(f"metadata/cab_color = {color}")
    w("")
    w(f'[node name="Shape" type="CollisionShape3D" parent="Navigation/{name}"]')
    w("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.3, 0)")
    w('shape = SubResource("TruckShape")')
    w("")
w('[node name="EnemySpawns" type="Node3D" parent="."]')
w("")
for name, x, y, z, kind, level in spawns:
    w(f'[node name="{name}" type="Marker3D" parent="EnemySpawns" groups=["enemy_spawn"]]')
    w(f"transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, {x:g}, {y:g}, {z:g})")
    w(f'metadata/enemy = "{kind}"')
    w(f"metadata/level = {level}")
    w("")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(lines), encoding="utf-8")
print(f"wrote {out}: {len(boxes)} boxes, {len(bodies)} bodies, {len(poles)} poles, "
      f"{len(buses) + len(taxis) + len(trucks)} vehicles, {len(spawns)} spawns")
