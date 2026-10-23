"""Build the R4 doll antechamber, without touching runtime or source images.

Native editable meshes use existing R2 textures. Two unmodified R4 source
cards provide the new landmarks; this is an adapted layout, not a source map.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/r2"))
from build_route_worlds import ANGLE, COS, PPM, SIN, World, gd, vec, world

WALK = [36, 245, 852, 345]  # source-ground x0,y0,x1,y1
FLOOR = [-170, 220, 1060, 450]
FOOT_RADIUS = .18
OUTPUTS = ["scenes/tower_doll_gallery_world.tscn",
           "scenes/tower_doll_gallery_collisions.tscn",
           "docs/r4_doll_gallery_layout_reference.json"]
R2_TEXTURES = ["interior/paving.png", "interior/column.png", "approach/bridge_0.png"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class DollGallery(World):
    def __init__(self):
        super().__init__("TowerDollGalleryWorld")
        self.footprints, self.cards = [], []
        self.scene.nodes[0] = self.scene.nodes[0].replace(
            "Adapted R2 route; original source pixels, new3D geometry.",
            "Adapted R4 doll antechamber; original PNG cards and editable native architecture.")

    def tinted(self, path, rgba, *, scale=(1, 1), offset=(0, 0), unlit=False):
        return self.resource("StandardMaterial3D", {
            "albedo_texture": self.scene.resource("res://assets/r2/" + path),
            "albedo_color": "Color(" + ", ".join(map(str, rgba)) + ")",
            "shading_mode": "0" if unlit else "1", "roughness": "1.0",
            "texture_filter": "0", "uv1_scale": vec([*scale, 1]),
            "uv1_offset": vec([*offset, 0]),
        })

    def record(self, name, x, y, width, height, depth, bottom, support=False):
        half_x, half_y = width * PPM / 2, depth * PPM * SIN / 2
        bounds = [x - half_x, y - half_y, x + half_x, y + half_y]
        ex, ey = FOOT_RADIUS * PPM, FOOT_RADIUS * PPM * SIN
        expanded = [bounds[0] - ex, bounds[1] - ey, bounds[2] + ex, bounds[3] + ey]
        outside = (expanded[2] < WALK[0] or expanded[0] > WALK[2]
                   or expanded[3] < WALK[1] or expanded[1] > WALK[3])
        assert support or outside, (name, expanded)
        center = world(x, y, bottom + height / 2)
        self.footprints.append({
            "node": name, "mesh": "PlaneMesh" if height == 0 else "BoxMesh",
            "source_ground_center": [x, y], "source_ground_aabb_xyxy": bounds,
            "actor_expanded_aabb_xyxy": expanded,
            "world_aabb_min": [center[0] - width / 2, bottom, center[2] - depth / 2],
            "world_aabb_max": [center[0] + width / 2, bottom + height, center[2] + depth / 2],
            "below_foot_support": support, "outside_walk_with_actor_clearance": outside,
        })
        if support:
            assert bottom + height < .025, (name, "support rises above actor foot")

    def box(self, name, x, y, width, height, depth, material, bottom=.015, *, support=False):
        super().box(name, x, y, width, height, depth, material, bottom)
        self.record(name, x, y, width, height, depth, bottom, support)

    def source_card(self, name, key, x, y, depth):
        path = f"res://assets/r4/doll_gallery/{key}.png"
        with Image.open(ROOT / path.removeprefix("res://")) as image:
            size = image.size
        position = world(x, y)
        position[1] += SIN * depth
        position[2] += COS * depth
        self.scene.node(name, "Sprite3D", ".", texture=self.scene.resource(path),
                        position=vec(position), rotation=vec([-ANGLE, 0, 0]),
                        pixel_size=str(1 / PPM), offset=f"Vector2(0, {size[1] / 2})",
                        billboard="0", alpha_cut="1", alpha_scissor_threshold="0.25",
                        texture_filter="0", shaded="false", cast_shadow="0",
                        **{"metadata/source_pixel_policy": gd("Original RGBA crop at 1 source pixel per logical pixel; adapted bottom anchor, view-ray depth only.")})
        self.cards.append({"node": name, "texture": path, "size": list(size),
                           "visible_crop_bottom_center": [x, y], "view_ray_depth_m": depth,
                           "pixel_scale": 1, "ground_collision": False,
                           "source_projected_rect_xyxy": [x - size[0] / 2, y - size[1],
                                                          x + size[0] / 2, y]})


def build():
    w = DollGallery()
    stone = w.tinted("approach/bridge_0.png", (.77, .72, .61, 1),
                     scale=(64 / 224, 32 / 306), offset=(24 / 224, 80 / 306))
    dark = w.tinted("interior/paving.png", (.40, .38, .35, 1), scale=(2, 3))
    gold = w.tinted("interior/column.png", (.86, .75, .59, 1),
                    scale=(11 / 29, 60 / 93), offset=(9 / 29, 16 / 93))
    floor = w.tinted("interior/paving.png", (.80, .77, .68, 1), unlit=True,
                     scale=((FLOOR[2] - FLOOR[0]) / 192, (FLOOR[3] - FLOOR[1]) / 96))
    x, y = (FLOOR[0] + FLOOR[2]) / 2, (FLOOR[1] + FLOOR[3]) / 2
    width, depth = (FLOOR[2] - FLOOR[0]) / PPM, (FLOOR[3] - FLOOR[1]) / (PPM * SIN)
    w.box("GalleryStoneFoundation", x, y, width, .24, depth, stone, -.23, support=True)
    plane = w.resource("PlaneMesh", {"material": floor, "size": f"Vector2({width}, {depth})"})
    w.scene.node("ContinuousGalleryFloor", "MeshInstance3D", ".",
                 position=vec(world(x, y, .015)), mesh=plane)
    w.count += 1
    w.record("ContinuousGalleryFloor", x, y, width, 0, depth, .015, True)
    w.source_card("OriginalDollGalleryVista", "far", 448, 230, -3.0)
    # The source vista remains 640px wide. Its two architectural side panels
    # close the exposed edges instead of stretching or mirroring the bitmap.
    for side, x0, x1 in [("Left", -170, 128), ("Right", 768, 1060)]:
        w.box("RearVistaSideWall_" + side, (x0 + x1) / 2, 207,
              (x1 - x0) / PPM, 5.6, .28, dark)
    # Low rear stone is interrupted by two statue alcoves, not a central banner.
    for side, x0, x1 in [("Left", -170, 260), ("Middle", 412, 596), ("Right", 748, 1060)]:
        center = (x0 + x1) / 2
        w.box("RearDado_" + side, center, 225, (x1 - x0) / PPM, .58, .26, dark)
        w.box("RearCoping_" + side, center, 225, (x1 - x0) / PPM, .09, .34,
              gold, .595)
    for side, center in [("Left", 336), ("Right", 672)]:
        w.box("StatuePlinth_" + side, center, 226, 1.82, .14, .50, stone)
        w.box("StatuePlinthCap_" + side, center, 226, 1.96, .08, .56, gold, .155)
        for edge, px in [("Left", center - 62), ("Right", center + 62)]:
            w.box(f"NichePier_{side}_{edge}", px, 211, .25, 4.6, .32, stone)
        w.box("NicheLintel_" + side, center, 211, 2.48, .20, .38, gold, 4.615)
        w.source_card("SourceStatue_" + side, "statue", center, 218, .10)
    # Side-facing return arch stays left of the whole legal walking strip.
    for edge, py in [("Rear", 278), ("Front", 362)]:
        w.box("ReturnArchPier_" + edge, -20, py, .50, 2.8, .46, stone)
    w.box("ReturnArchSideBeam", -20, 320, .56, .22, 100 / (PPM * SIN), gold, 2.815)
    for side, center in [("Left", 224), ("Right", 784)]:
        w.box("FrontLowWall_" + side, center, 386, 2.70, .25, .32, dark)
        w.box("FrontLowCoping_" + side, center, 386, 2.80, .07, .40, gold, .265)
    assert w.count == 27 and len(w.cards) == 3
    return w


def sources():
    r2 = json.loads((ROOT / "docs/r2_asset_manifest.json").read_text())
    r4 = json.loads((ROOT / "docs/r4_stonemaster_source_reference.json").read_text())
    indexed = {item["texture"]: item for item in r2["frames"] + r2["derived"]}
    selected = [indexed["res://assets/r2/" + p] for p in R2_TEXTURES] + r4["environment_outputs"]
    for source in selected:
        path = ROOT / source["texture"].removeprefix("res://")
        with Image.open(path) as image:
            rgba = hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()
        assert digest(path) == source["sha256_png"], str(path)
        assert rgba == source["sha256_rgba"], str(path)
    assert {s["key"]: s["size"] for s in r4["environment_outputs"]} == {
        "statue": [99, 205], "far": [640, 410]}
    return selected


def main():
    assets = sources()
    before = {s["texture"]: digest(ROOT / s["texture"].removeprefix("res://")) for s in assets}
    w = build()
    for output in OUTPUTS:
        (ROOT / output).parent.mkdir(parents=True, exist_ok=True)
    result = w.save(OUTPUTS[0])
    (ROOT / OUTPUTS[1]).write_text('''[gd_scene format=3]

[node name="TowerDollGalleryCollisions" type="Node3D"]
metadata/obstacle_count = 0
metadata/ground_policy = "Intentionally empty: all decorative native mesh AABBs expanded by actor foot radius 0.18m lie outside walk [36,245,852,345]. Floor and foundation are below-foot support. See docs/r4_doll_gallery_layout_reference.json."
''')
    support = [s for s in w.footprints if s["below_foot_support"]]
    solids = [s for s in w.footprints if not s["below_foot_support"]]
    # The framing cap covers transferred scene state too, not just legal-x targets.
    camera_x = [-152, 896 + 152]
    floor_margins = [camera_x[0] - FLOOR[0], FLOOR[2] - camera_x[1]]
    legal_offsets = [36 - 184, 852 - (896 - 184)]
    visible_y_bottom = 404 - 43 + 40
    assert min(floor_margins) > 0 and FLOOR[3] > visible_y_bottom
    assert all(digest(ROOT / p.removeprefix("res://")) == h for p, h in before.items())
    all_meshes = w.footprints
    native_aabb = {key: [fn(s[key][axis] for s in all_meshes) for axis in range(3)]
                   for key, fn in [("world_aabb_min", min), ("world_aabb_max", max)]}
    report = {
        "schema_version": 1, "stage": "R4/06 doll antechamber layout", "region_id": "doll_gallery",
        "layout_policy": "One adapted open walking lane with twin rear statue niches. No recovered original adjacency or 3D-map claim; no new combat, route or save behavior here.",
        "camera": {"elevation_degrees": 38, "pixels_per_meter": PPM,
                   "ground_formula": "X=(sourceX-448)/60; Y=.025; Z=(sourceY-159)/(60*sin38)-1.6",
                   "screen_ground_formula": "screenY=sourceY+43-framing_offset_y"},
        "walk_bounds_xyxy": WALK, "arrival": [176, 320], "enemy_initial": [640, 300],
        "floor_source_bounds_xyxy": FLOOR,
        "return_route_integration_pending": {"trigger_xywh": [36, 295, 6, 50], "hold": "move_left",
                                             "target_region": "depths", "target_spawn": [816, 320]},
        "source_statue_placement": {"visible_bottom_centers": [[336, 218], [672, 218]],
                                   "equivalent_original_ani_origins": [[336.5, 212], [672.5, 212]],
                                   "crop_top_left_relative_to_ani_origin": [-50, -199],
                                   "crop_bottom_center_relative_to_ani_origin": [-.5, 6],
                                   "policy": "Adapted placement by visible crop bottom; retains original 99x205 pixels and records rather than discards original ANI/IMG offset."},
        "far_placement": {"original_ani_offset": [0, -80], "adapted_visible_bottom_center": [448, 230],
                          "size": [640, 410], "source_x_coverage": [128, 768],
                          "edge_policy": "Unscaled source vista is framed by textured native side walls through x-170..128 and 768..1060; no bitmap padding."},
        "pixel_policy": {"source_cards": "Original RGBA, unlit, nearest, 1:1 logical pixels, no flip or crop change.",
                         "architecture": "Native source-textured meshes, lit albedo multipliers; rendered RGB is not source exact.",
                         "floor": "Opaque existing 192x96 R2 paving repeated by UV, unlit warm multiplier; no new bitmap.",
                         "multipliers": {"stone": [.77, .72, .61, 1], "dark": [.40, .38, .35, 1],
                                         "gold": [.86, .75, .59, 1], "floor": [.80, .77, .68, 1]},
                         "texture_subrects_xyxy": {"approach/bridge_0.png": [24, 80, 88, 112],
                                                  "interior/column.png": [9, 16, 20, 76]}},
        "native_mesh_instances": w.count, "source_card_count": len(w.cards), "native_mesh_world_aabb": native_aabb,
        "collision_audit": {"actor_foot_radius_m": FOOT_RADIUS,
                            "source_radius_xy": [FOOT_RADIUS * PPM, FOOT_RADIUS * PPM * SIN],
                            "all_25_decorative_solids_outside_expanded_walk": all(s["outside_walk_with_actor_clearance"] for s in solids),
                            "support_count": len(support), "obstacle_shapes": 0,
                            "nearest_rear_expanded_y": max(s["actor_expanded_aabb_xyxy"][3] for s in solids if s["source_ground_center"][1] < WALK[1]),
                            "meshes": all_meshes},
        "edge_camera_floor_audit": {"viewport_size": [896, 404], "conservative_horizontal_offset_range": [-152, 152],
                                    "legal_walk_target_offsets": legal_offsets, "required_source_x_range": camera_x,
                                    "floor_margin_left_right_px": floor_margins,
                                    "framing_vertical_max": 40, "visible_ground_bottom_source_y": visible_y_bottom,
                                    "floor_bottom_margin_px": FLOOR[3] - visible_y_bottom,
                                    "rear_floor_overlap": "Floor begins y220, underneath rear dado centered y225; no open strip between rear wall and floor.",
                                    "side_void_policy": "Conservative full-width floor covers every legal side view. Upper edge fields are native walls plus original vista; parent must preview after integration."},
        "source_cards": w.cards, "source_references": ["docs/r2_asset_manifest.json", "docs/r4_stonemaster_source_reference.json"],
        "assets": assets, "outputs": [result, {"scene": OUTPUTS[1], "obstacle_shapes": 0}],
        "offline_checks": {"five_source_png_and_rgba_hashes_match_export_reports": True,
                           "source_pngs_unchanged_after_build": True, "mesh_budget_20_to_30": 20 <= w.count <= 30,
                           "all_decorative_expanded_aabbs_outside_walk": True,
                           "floor_covers_full_framing_cap": True},
        "not_run": ["Godot parse or live scene", "Blender", "client executable"],
        "integration_pending": ["Parent loads new world and empty collision scene for doll_gallery",
                                "Parent adds gated depths forward/return travel and separate encounter",
                                "Parent verifies native appearance, card layering, lighting and camera edges"],
    }
    (ROOT / OUTPUTS[2]).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"outputs": OUTPUTS, "native_meshes": w.count, "source_cards": len(w.cards),
                      "solid_aabbs_checked": len(solids), "obstacle_shapes": 0,
                      "floor_edge_margins_px": floor_margins}, ensure_ascii=False))


if __name__ == "__main__":
    main()
