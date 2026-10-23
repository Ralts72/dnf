"""Build one editable R4 deep gallery from ten already exported R2 PNGs.

No client reads or bitmap writes.  The existing R2 builder provides the shared
source-ground transform and native scene serializer, not the new layout.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/r2"))
from build_route_worlds import World, SIN, PPM, vec, world, gd

WALK = [36, 245, 852, 345]
FOOT_RADIUS = 0.18
OUTPUTS = [
    "scenes/tower_depths_world.tscn",
    "scenes/tower_depths.tscn",
    "scenes/tower_depths_collisions.tscn",
    "source_art/r4/depths_layout_reference.json",
    "docs/r4_depths_source_reference.json",
]
TEXTURES = [
    "interior/paving.png", "interior/column.png", "interior/far.png",
    "interior/banner.png",
] + [f"interior/wall_{i}.png" for i in range(6)]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Depths(World):
    def __init__(self):
        super().__init__("TowerDepthsWorld")
        self.footprints = []
        self.cards = []
        self.scene.nodes[0] = self.scene.nodes[0].replace(
            "Adapted R2 route; original source pixels, new3D geometry.",
            "Adapted R4 single deep gallery; original R2 PNGs, editable native 3D geometry.",
        )

    def tint(self, path, color, *, unlit=False, scale=(1, 1), offset=(0, 0)):
        return self.resource("StandardMaterial3D", {
            "shading_mode": "0" if unlit else "1",
            "albedo_texture": self.scene.resource("res://assets/r2/" + path),
            "albedo_color": "Color(" + ", ".join(map(str, color)) + ")",
            "roughness": "1.0", "texture_filter": "0",
            "uv1_scale": vec([*scale, 1]), "uv1_offset": vec([*offset, 0]),
        })

    def record(self, name, x, y, half_x_m, half_z_m, *, ground_support=False):
        bounds = [x - half_x_m * PPM, y - half_z_m * PPM * SIN,
                  x + half_x_m * PPM, y + half_z_m * PPM * SIN]
        expanded = [bounds[0] - FOOT_RADIUS * PPM,
                    bounds[1] - FOOT_RADIUS * PPM * SIN,
                    bounds[2] + FOOT_RADIUS * PPM,
                    bounds[3] + FOOT_RADIUS * PPM * SIN]
        separated = (expanded[2] < WALK[0] or expanded[0] > WALK[2]
                     or expanded[3] < WALK[1] or expanded[1] > WALK[3])
        assert ground_support or separated, (name, bounds, expanded)
        self.footprints.append({
            "node": name, "source_ground_center": [x, y],
            "source_ground_aabb": bounds,
            "aabb_with_0_18m_actor_clearance": expanded,
            "role": "below-foot ground support" if ground_support else "decoration outside navigation",
            "outside_walk_with_actor_clearance": separated,
        })

    def box(self, name, x, y, width, height, depth, material, bottom=.015,
            rotation=None, ground_support=False):
        assert rotation is None, "Footprint audit assumes upright native boxes"
        super().box(name, x, y, width, height, depth, material, bottom)
        self.record(name, x, y, width / 2, depth / 2, ground_support=ground_support)

    def cylinder(self, name, x, y, radius, height, material, bottom=.015, top=None):
        super().cylinder(name, x, y, radius, height, material, bottom, top)
        r = max(radius, radius if top is None else top)
        self.record(name, x, y, r, r)

    def card(self, name, path, x, y, depth=0):
        super().card(name, path, x, y, depth)
        self.cards.append({"node": name, "texture": "res://assets/r2/" + path,
                           "source_bottom_center": [x, y], "view_ray_depth_m": depth,
                           "pixel_scale": 1, "ground_collision": False})


def build():
    w = Depths()
    # The deeper space is cooler and darker through native material response.
    # PNGs retain their source RGBA; source cards remain unlit and unmodulated.
    stone = w.tint("interior/paving.png", (.50, .53, .64, 1))
    gold = w.tint("interior/column.png", (.72, .64, .58, 1),
                  scale=(11 / 29, 60 / 93), offset=(9 / 29, 16 / 93))
    paving = w.tint("interior/paving.png", (.68, .71, .80, 1), unlit=True,
                    scale=(1230 / 192, 215 / 96))
    w.box("DepthFoundation", 445, 342.5, 20.5, .24, 215 / (PPM * SIN),
          stone, bottom=-.23, ground_support=True)
    plane = w.resource("PlaneMesh", {"material": paving,
                       "size": f"Vector2(20.5, {215 / (PPM * SIN)})"})
    w.scene.node("ContinuousArenaFloor", "MeshInstance3D", ".",
                 position=vec(world(445, 342.5, .015)), mesh=plane)
    w.count += 1
    # All source floor portions terminate before the legal foot lane starts.
    # The whole rear arcade reads as a long, single space instead of a new room chain.
    w.card("DistantSourceVista", "interior/far.png", 448, 210, -3.0)
    for i, x in enumerate([-112, 112, 336, 560, 784, 1008]):
        w.card(f"RearSourceArcade_{i}", f"interior/wall_{i}.png", x, 218, -1.15)
    for side, x0, x1 in [("Left", -170, 470), ("Right", 810, 1060)]:
        x = (x0 + x1) / 2
        w.box("RearDado_" + side, x, 212, (x1 - x0) / PPM, .58, .34, stone)
        w.box("RearCoping_" + side, x, 212, (x1 - x0) / PPM, .09, .42,
              gold, bottom=.595)
    # 218 + (.48 + .18) * 60*sin38 = 242.38, strictly behind y245.
    for i, x in enumerate([112, 336, 808, 1032]):
        prefix = f"RearVolumeColumn_{i}"
        w.cylinder(prefix + "_Foot", x, 218, .46, .18, gold)
        w.cylinder(prefix + "_Ring", x, 218, .37, .16, stone, bottom=.195)
        w.cylinder(prefix + "_Shaft", x, 218, .22, 3.38, stone,
                   bottom=.355, top=.17)
        w.cylinder(prefix + "_Capital", x, 218, .42, .23, gold,
                   bottom=3.735, top=.48)
    # A three-level recessed stair and tall portal at x640 create the new landmark.
    # No step approaches the walk strip: the nearest one ends at y234 before clearance.
    for name, y, width, depth_px, height in [
        ("SanctumStepLower", 226, 5.7, 12, .10),
        ("SanctumStepMiddle", 213, 5.2, 14, .22),
        ("SanctumDais", 188, 4.8, 36, .38),
    ]:
        w.box(name, 640, y, width, height, depth_px / (PPM * SIN), stone)
    for side, x in [("Left", 516), ("Right", 764)]:
        w.box("SanctumArchFoot_" + side, x, 186, .62, .24, .62, gold)
        w.box("SanctumArchPier_" + side, x, 186, .34, 3.20, .43,
              stone, bottom=.255)
        w.box("SanctumArchCapital_" + side, x, 186, .72, .24, .66,
              gold, bottom=3.455)
    w.box("SanctumLintel", 640, 186, 4.8, .32, .46, stone, bottom=3.695)
    w.box("SanctumKeystone", 640, 186, .54, .54, .62, gold, bottom=3.585)
    w.card("DeepSanctumBakalBanner", "interior/banner.png", 640, 205, -.65)
    # This is a real side-facing arch at the left edge, not another front door.
    # Its entire X footprint stays left of x36 even with actor foot clearance.
    for side, y in [("Rear", 278), ("Front", 362)]:
        w.box("ReturnArchFoot_" + side, -18, y, .62, .19, .54, gold)
        w.box("ReturnArchPier_" + side, -18, y, .30, 2.65, .31,
              stone, bottom=.205)
        w.box("ReturnArchCapital_" + side, -18, y, .68, .20, .58,
              gold, bottom=2.855)
    w.box("ReturnArchSideBeam", -18, 320, .42, .24, 96 / (PPM * SIN),
          stone, bottom=3.055)
    # Foreground edges sit beyond both navigation and actor foot radius.
    # Leave the left return's visual lane free rather than drawing a full rail across it.
    for side, x in [("Left", 224), ("Right", 784)]:
        w.box("FrontLowDado_" + side, x, 386, 2.7, .25, .32, stone)
        w.box("FrontLowCoping_" + side, x, 386, 2.8, .07, .40,
              gold, bottom=.265)
    assert 30 <= w.count <= 45, w.count
    assert len(w.cards) == 8
    return w


def main():
    for output in OUTPUTS:
        (ROOT / output).parent.mkdir(parents=True, exist_ok=True)
    original_hashes = {p: digest(ROOT / "assets/r2" / p) for p in TEXTURES}
    manifest = json.loads((ROOT / "docs/r2_asset_manifest.json").read_text())
    indexed = {item["texture"]: item for item in manifest["frames"] + manifest["derived"]}
    assets = []
    for relative in TEXTURES:
        path = "res://assets/r2/" + relative
        source = indexed[path]
        image = Image.open(ROOT / "assets/r2" / relative).convert("RGBA")
        rgba = hashlib.sha256(image.tobytes()).hexdigest()
        assert original_hashes[relative] == source["sha256_png"], path
        assert rgba == source["sha256_rgba"], path
        item = {**source, "r4_use": "Reused unchanged; no new crop or PNG export"}
        if source.get("derived_subrect"):
            item["original_source_frame_reference"] = indexed[source["source_texture"]]
        assets.append(item)
    w = build()
    world_result = w.save(OUTPUTS[0])
    (ROOT / OUTPUTS[1]).write_text('''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/west_coast_r1.tscn" id="1_base"]
[ext_resource type="Script" path="res://scripts/exploration_stage.gd" id="2_stage"]

[node name="WestCoastR1" instance=ExtResource("1_base")]
script = ExtResource("2_stage")
region_id = "depths"
''')
    (ROOT / OUTPUTS[2]).write_text('''[gd_scene format=3]

[node name="TowerDepthsCollisions" type="Node3D"]
metadata/ground_policy = "No obstacle shapes: every decorative solid footprint, expanded by the shared 0.18m actor foot radius, is strictly outside walk [36,245,852,345]. Floor/foundation are support below the actor foot, not movement obstacles. See source_art/r4/depths_layout_reference.json."
metadata/obstacle_count = 0
''')
    layout = {
        "stage": "R4 deep gallery native layout", "region_id": "depths",
        "layout_policy": "One continuous broad arena and recessed rear sanctum; adapted geometry, not recovered original map adjacency.",
        "camera": {"elevation_degrees": 38, "source_pixels_per_meter": PPM,
                   "ground_formula": "X=(sourceX-448)/60; Y=.025; Z=(sourceY-159)/(60*sin38)-1.6"},
        "walk_bounds": WALK, "floor_source_bounds": [-170, 235, 1060, 450],
        "arrival": [176, 320], "boss_initial": [640, 300],
        "left_exit": {"trigger_bounds_xywh": [36, 295, 6, 50], "action": "move_left",
                      "target_region": "hall", "target_safe_spawn": [720, 320]},
        "hall_right_exit_integration": {"trigger_bounds_xywh": [770, 295, 6, 42],
                                        "action": "move_right", "target_safe_spawn": [176, 320]},
        "new_landmarks": ["Recessed three-level sanctum stair at x640 behind the legal walk strip",
                          "Tall native rear arch with protruding capital volumes and keystone",
                          "Cool dark continuous floor and rear colonnade; banner focal point shifted to x640",
                          "Side-facing left return arch outside the legal foot lane"],
        "native_material_policy": "Source textures plus native light and recorded albedo multipliers; rendered geometry RGB is not claimed source exact. Original source-card RGBA and PNG bytes are unchanged.",
        "material_multipliers": {"lit_stone": [.50, .53, .64, 1],
                                 "lit_gold": [.72, .64, .58, 1],
                                 "unlit_floor": [.68, .71, .80, 1]},
        "footprint_audit": {"actor_radius_m": FOOT_RADIUS,
                            "all_decorative_expanded_bounds_outside_walk": True,
                            "obstacle_shape_count": 0,
                            "ground_support_excluded": ["DepthFoundation", "ContinuousArenaFloor"],
                            "solids": w.footprints},
        "source_cards": w.cards, "outputs": [world_result],
        "integration_pending": ["Root extends exploration_stage region enum/world selection/title/backdrop for depths",
                                "Root adds route definitions, first-clear gate and obstacle scene mapping",
                                "Root attaches separate boss encounter; retain R3 quest/drop/equipment behavior"],
        "not_run": ["No Godot process or live scene call", "No Blender", "No client executable", "No image export"],
    }
    (ROOT / OUTPUTS[3]).write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")
    report = {
        "schema_version": 1, "stage": "R4 deep gallery source reuse", "region_id": "depths",
        "basis": {"r2_manifest": "docs/r2_asset_manifest.json",
                  "r2_layout": "source_art/r2/layout_reference.json",
                  "planning": "work/r4_tower_extension_plan.json",
                  "shared_transform_and_serializer": "tools/r2/build_route_worlds.py"},
        "source_client": manifest["client"], "source_pvf_sha256": manifest["source_pvf_sha256"],
        "required_new_crops": 0, "unchanged_reused_png_count": len(assets), "assets": assets,
        "outputs": OUTPUTS, "native_mesh_instances": w.count, "source_card_count": len(w.cards),
        "collision_policy": "Empty named root is intentional: all decorative solids remain outside the legal walking rectangle with 0.18m clearance. Existing route bounds prevent unreachable outer decoration from being contacted. No invisible internal obstacles.",
        "checks": {"ten_png_and_decoded_rgba_match_existing_manifest": True,
                   "source_png_hashes_unchanged_after_build": all(digest(ROOT / "assets/r2" / p) == h for p, h in original_hashes.items()),
                   "native_mesh_budget_30_to_45": True,
                   "all_decorative_footprints_outside_walk_with_actor_clearance": True,
                   "exact_existing_runtime_or_asset_files_modified": 0,
                   "scene_runtime_parse": "Not run; parent coordinates Godot parse and live QA after integration"},
        "nonclaims": ["New adapted geometry, no claim of original 3D map layout or recovered route adjacency",
                      "Native material shading/tint is not a claim of rendered source-pixel equality",
                      "Scene resource and source provenance only; boss/travel/profile integration remains with root"],
    }
    (ROOT / OUTPUTS[4]).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"outputs": OUTPUTS, "native_mesh_instances": w.count,
                      "source_cards": len(w.cards), "reused_pngs": len(assets),
                      "decorative_footprints_checked": len(w.footprints) - 1,
                      "obstacle_shapes": 0}, ensure_ascii=False))


if __name__ == "__main__":
    main()
