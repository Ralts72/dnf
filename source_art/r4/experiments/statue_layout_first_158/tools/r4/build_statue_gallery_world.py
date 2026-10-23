"""Build a continuous 1280px R4 statue corridor from existing source textures.

Only the two new native scenes and their layout audit are written. No runtime,
route, camera, bitmap, Blender source or previous build manifest is changed.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/r2"))
from build_route_worlds import COS, PPM, SIN, World, vec, world

WALK = [36, 245, 1244, 345]
FLOOR = [-170, 220, 1444, 450]
CAMERA_PAN = [-152, 536]
FOOT_RADIUS = .18
MIN_GAP = 2.0
WINDOWS = [(224, 128, 320), (640, 544, 736), (1056, 960, 1152)]
TEXTURES = ["interior/paving.png", "interior/column.png", "approach/bridge_0.png", "interior/far.png"]
OUTPUTS = ["scenes/tower_statue_gallery_world.tscn",
           "scenes/tower_statue_gallery_collisions.tscn",
           "docs/r4_statue_gallery_layout_reference.json"]
COLORS = {"stone": [.78, .77, .72, 1], "wall": [.48, .47, .44, 1],
          "gold": [.70, .66, .56, 1], "floor": [.74, .73, .70, 1]}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class StatueGallery(World):
    def __init__(self):
        super().__init__("TowerStatueGalleryWorld")
        self.footprints, self.cards = [], []
        self.scene.nodes[0] = self.scene.nodes[0].replace(
            "Adapted R2 route; original source pixels, new3D geometry.",
            "Adapted R4 1280px continuous statue corridor; original PNGs, editable native architecture.")

    def tinted(self, path, color, *, unlit=False, scale=(1, 1), offset=(0, 0)):
        return self.resource("StandardMaterial3D", {
            "albedo_texture": self.scene.resource("res://assets/r2/" + path),
            "albedo_color": "Color(" + ", ".join(map(str, color)) + ")",
            "shading_mode": "0" if unlit else "1", "roughness": "1.0", "texture_filter": "0",
            "uv1_scale": vec([*scale, 1]), "uv1_offset": vec([*offset, 0]),
        })

    def record(self, name, kind, x, y, width, height, depth, bottom, support=False):
        sx, sy = width * PPM / 2, depth * PPM * SIN / 2
        bounds = [x - sx, y - sy, x + sx, y + sy]
        rx, ry = FOOT_RADIUS * PPM, FOOT_RADIUS * PPM * SIN
        expanded = [bounds[0] - rx, bounds[1] - ry, bounds[2] + rx, bounds[3] + ry]
        gaps = {"left": WALK[0] - expanded[2], "right": expanded[0] - WALK[2],
                "rear": WALK[1] - expanded[3], "front": expanded[1] - WALK[3]}
        separation = max(gaps.values())
        assert support or separation >= MIN_GAP, (name, expanded, gaps)
        assert not support or bottom + height < .025, name
        center = world(x, y, bottom + height / 2)
        self.footprints.append({
            "node": name, "mesh_type": kind, "source_ground_center": [x, y],
            "source_ground_aabb_xyxy": bounds, "actor_expanded_aabb_xyxy": expanded,
            "world_aabb_min": [center[0] - width / 2, bottom, center[2] - depth / 2],
            "world_aabb_max": [center[0] + width / 2, bottom + height, center[2] + depth / 2],
            "below_foot_support": support, "outside_walk_with_actor_clearance": separation > 0,
            "walk_separation_px": None if support else separation,
            "separated_axis": None if support else max(gaps, key=gaps.get),
        })

    def box(self, name, x, y, width, height, depth, material, bottom=.015, *, support=False):
        super().box(name, x, y, width, height, depth, material, bottom)
        self.record(name, "BoxMesh", x, y, width, height, depth, bottom, support)

    def cylinder(self, name, x, y, radius, height, material, bottom=.015, top=None):
        super().cylinder(name, x, y, radius, height, material, bottom, top)
        r = max(radius, radius if top is None else top)
        self.record(name, "CylinderMesh", x, y, r * 2, height, r * 2, bottom)

    def card(self, name, path, x, y, depth=0):
        super().card(name, path, x, y, depth)
        with Image.open(ROOT / "assets/r2" / path) as image:
            size = list(image.size)
        self.cards.append({"node": name, "texture": "res://assets/r2/" + path,
                           "size": size, "visible_crop_bottom_center": [x, y],
                           "view_ray_depth_m": depth, "pixel_scale": 1,
                           "ground_collision": False,
                           "source_projected_rect_xyxy": [x - size[0] / 2, y - size[1], x + size[0] / 2, y]})


def build():
    w = StatueGallery()
    stone = w.tinted("approach/bridge_0.png", COLORS["stone"],
                     scale=(64 / 224, 32 / 306), offset=(24 / 224, 80 / 306))
    wall = w.tinted("interior/paving.png", COLORS["wall"], scale=(2, 3))
    gold = w.tinted("interior/column.png", COLORS["gold"],
                    scale=(11 / 29, 60 / 93), offset=(9 / 29, 16 / 93))
    width = (FLOOR[2] - FLOOR[0]) / PPM
    depth = (FLOOR[3] - FLOOR[1]) / (PPM * SIN)
    center_x, center_y = (FLOOR[0] + FLOOR[2]) / 2, (FLOOR[1] + FLOOR[3]) / 2
    paving = w.tinted("interior/paving.png", COLORS["floor"], unlit=True,
                      scale=((FLOOR[2] - FLOOR[0]) / 192, (FLOOR[3] - FLOOR[1]) / 96))
    w.box("LongGalleryFoundation", center_x, center_y, width, .24, depth,
          stone, -.23, support=True)
    plane = w.resource("PlaneMesh", {"material": paving, "size": f"Vector2({width}, {depth})"})
    w.scene.node("ContinuousLongGalleryFloor", "MeshInstance3D", ".",
                 position=vec(world(center_x, center_y, .015)), mesh=plane)
    w.count += 1
    w.record("ContinuousLongGalleryFloor", "PlaneMesh", center_x, center_y,
             width, 0, depth, .015, True)
    # Three complete 630x355 original PNGs stay at 1:1. All bitmap boundaries
    # and overlaps are masked by the four physical wall fields, not new crops.
    for i, (center, _x0, _x1) in enumerate(WINDOWS):
        w.card(f"OriginalWindowVista_{i}", "interior/far.png", center, 230, -3.0)
    for i, (x0, x1) in enumerate([(-170, 128), (320, 544), (736, 960), (1152, 1444)]):
        w.box(f"RearWindowWall_{i}", (x0 + x1) / 2, 207,
              (x1 - x0) / PPM, 5.6, .28, wall)
    w.box("ContinuousRearDado", center_x, 225, width, .58, .26, wall)
    w.box("ContinuousRearCoping", center_x, 225, width, .09, .34, gold, .595)
    for i, (center, x0, x1) in enumerate(WINDOWS):
        for side, x in [("Left", x0 - 12), ("Right", x1 + 12)]:
            name = f"WindowColumn_{i}_{side}"
            w.cylinder(name + "_Base", x, 218, .44, .18, gold)
            w.cylinder(name + "_Shaft", x, 218, .22, 4.1, stone, .195, top=.18)
            w.cylinder(name + "_Capital", x, 218, .40, .24, gold, 4.295, top=.48)
        w.box(f"WindowLintel_{i}", center, 218, 3.92, .22, .38, stone, 4.535)
    w.box("ContinuousRearUpperBeam", center_x, 218, width, 1.45, .32, wall, 4.755)
    for side, x in [("Return", -20), ("End", 1304)]:
        for edge, y in [("Rear", 278), ("Front", 362)]:
            w.box(f"{side}ArchPier_{edge}", x, y, .50, 2.8, .46, stone)
        w.box(side + "ArchSideBeam", x, 320, .56, .22, 100 / (PPM * SIN), gold, 2.815)
    for i, x in enumerate([336, 1008]):
        w.box(f"FrontLowWall_{i}", x, 386, 3.20, .25, .32, wall)
        w.box(f"FrontLowCoping_{i}", x, 386, 3.30, .07, .40, gold, .265)
    assert w.count == 40 and len(w.cards) == 3
    return w


def source_assets():
    source = json.loads((ROOT / "docs/r2_asset_manifest.json").read_text())
    indexed = {item["texture"]: item for item in source["frames"] + source["derived"]}
    assets = []
    for relative in TEXTURES:
        path = ROOT / "assets/r2" / relative
        reference = indexed["res://assets/r2/" + relative]
        with Image.open(path) as image:
            rgba = image.convert("RGBA")
            rgba_hash = hashlib.sha256(rgba.tobytes()).hexdigest()
            alpha_range = list(rgba.getchannel("A").getextrema())
        assert digest(path) == reference["sha256_png"]
        assert rgba_hash == reference["sha256_rgba"]
        item = {**reference, "verified_alpha_range": alpha_range,
                "use_policy": "Existing unchanged PNG and full RGBA; no new crop or image export"}
        if item.get("derived_subrect"):
            item["original_source_frame_reference"] = indexed[item["source_texture"]]
        assets.append(item)
    assert assets[0]["verified_alpha_range"] == [255, 255]
    assert [assets[-1]["width"], assets[-1]["height"]] == [630, 355]
    for relative, rect in [("approach/bridge_0.png", (24, 80, 88, 112)),
                           ("interior/column.png", (9, 16, 20, 76))]:
        with Image.open(ROOT / "assets/r2" / relative) as image:
            assert image.convert("RGBA").crop(rect).getchannel("A").getextrema() == (255, 255)
    return assets


def main():
    assets = source_assets()
    before = {item["texture"]: digest(ROOT / item["texture"].removeprefix("res://")) for item in assets}
    w = build()
    for output in OUTPUTS:
        (ROOT / output).parent.mkdir(parents=True, exist_ok=True)
    result = w.save(OUTPUTS[0])
    (ROOT / OUTPUTS[1]).write_text('''[gd_scene format=3]

[node name="TowerStatueGalleryCollisions" type="Node3D"]
metadata/obstacle_count = 0
metadata/ground_policy = "Intentionally empty: every decorative native mesh AABB, expanded by 0.18m actor foot radius, is at least 2 source pixels outside walk [36,245,1244,345]. Floor/foundation are below-foot support. See docs/r4_statue_gallery_layout_reference.json."
''')
    solids = [item for item in w.footprints if not item["below_foot_support"]]
    minimum_gap = min(item["walk_separation_px"] for item in solids)
    source_view = [CAMERA_PAN[0], CAMERA_PAN[1] + 896]
    actual_offsets = [WALK[0] - 184, WALK[2] - 712]
    margins = [source_view[0] - FLOOR[0], FLOOR[2] - source_view[1]]
    assert margins == [18, 12] and minimum_gap >= MIN_GAP
    assert all(digest(ROOT / p.removeprefix("res://")) == h for p, h in before.items())
    aabb = {key: [fn(item[key][i] for item in w.footprints) for i in range(3)]
            for key, fn in [("world_aabb_min", min), ("world_aabb_max", max)]}
    report = {
        "schema_version": 1, "stage": "R4/08 1280px continuous statue gallery", "region_id": "statue_gallery",
        "layout_policy": "One continuous long corridor with three rear window bays; no internal room transition. Adapted native architecture, not recovered original map adjacency or source 3D geometry.",
        "camera": {"viewport_size": [896, 404], "logical_region_width": 1280,
                   "elevation_degrees": 38, "pixels_per_meter": PPM,
                   "ground_formula": "X=(sourceX-448)/60; Y=.025; Z=(sourceY-159)/(60*sin38)-1.6",
                   "screen_ground_formula": "screenX=sourceX-offsetX; screenY=sourceY+43-offsetY",
                   "required_region_horizontal_limits": CAMERA_PAN,
                   "pose_radius_px": 176, "pose_margin_px": 8,
                   "integration_status": "Parent configures region-specific camera limits; this builder does not modify SourceFraming."},
        "walk_bounds_xyxy": WALK, "arrival": [176, 320],
        "enemy_staging_suggestion": [1056, 300],
        "floor_source_bounds_xyxy": FLOOR,
        "return_route_integration_pending": {"trigger_xywh": [36, 295, 6, 50], "action": "move_left",
                                             "target_region": "doll_gallery", "target_spawn_suggestion": [816, 320]},
        "end_landmark": {"arch_source_x": 1304, "walk_end_x": 1244,
                         "policy": "Visible end framing beyond the legal foot lane; no unimplemented forward route is implied."},
        "source_cards": w.cards,
        "rear_window_masking": {"openings_x": [[x0, x1] for _c, x0, x1 in WINDOWS],
                                "wall_fields_x": [[-170, 128], [320, 544], [736, 960], [1152, 1444]],
                                "whole_PNG_coverage_x": [[-91, 539], [325, 955], [741, 1371]],
                                "adjacent_bitmap_overlaps_x": [[325, 539], [741, 955]],
                                "wall_mask_margin_each_overlap_px": [5, 5],
                                "upper_beam_source_bottom": 218 - (4.755 - .025) * PPM * COS,
                                "policy": "All three source PNGs remain whole 630x355, at 1:1. Native wall fields hide full bitmap edges/overlaps; a continuous upper beam and low dado frame the rear windows."},
        "material_policy": {"source_cards": "Original full RGBA crops, no resampling, tint, flip or new bitmap; view-facing at 38 degrees, unlit nearest.",
                            "architecture": "Existing source textures, native lighting and recorded albedo multipliers. Rendered geometry RGB is not claimed source exact.",
                            "floor": "Existing opaque 192x96 paving repeated over the full 26.9m plane with nearest unlit sampling.",
                            "albedo_multipliers": COLORS,
                            "UV_subrects_xyxy": {"approach/bridge_0.png": [24, 80, 88, 112], "interior/column.png": [9, 16, 20, 76]}},
        "native_mesh_instances": w.count, "source_card_count": len(w.cards), "native_mesh_world_aabb": aabb,
        "collision_audit": {"actor_foot_radius_m": FOOT_RADIUS,
                            "source_radius_xy": [FOOT_RADIUS * PPM, FOOT_RADIUS * PPM * SIN],
                            "minimum_required_gap_px": MIN_GAP, "minimum_actual_gap_px": minimum_gap,
                            "decorative_meshes": len(solids), "below_foot_support_meshes": 2, "obstacle_shapes": 0,
                            "all_decorative_expanded_aabbs_outside_walk": True, "meshes": w.footprints},
        "edge_camera_floor_audit": {"conservative_pan_limits": CAMERA_PAN,
                                    "legal_walk_endpoint_offsets": actual_offsets,
                                    "conservative_view_union_source_x": source_view,
                                    "conservative_floor_left_right_margins_px": margins,
                                    "legal_view_union_source_x": [actual_offsets[0], actual_offsets[1] + 896],
                                    "legal_floor_left_right_margins_px": [22, 16],
                                    "vertical_pan_limit": 40, "required_ground_bottom_source_y": 401,
                                    "floor_bottom_margin_px": FLOOR[3] - 401,
                                    "rear_floor_overlap": "Floor begins y220 underneath the rear dado centered y225, so the rear foundation joins continuously.",
                                    "end_walk_screen_x": 712, "end_maximum_pose_screen_x": 888},
        "sources": {"manifest": "docs/r2_asset_manifest.json", "assets": assets,
                    "pixel_exports_added": 0, "unchanged_reused_PNGs": len(assets)},
        "outputs": [{**result, "sha256": digest(ROOT / OUTPUTS[0])},
                    {"scene": OUTPUTS[1], "sha256": digest(ROOT / OUTPUTS[1]), "obstacle_shapes": 0}],
        "producer": "tools/r4/build_statue_gallery_world.py", "producer_sha256": digest(Path(__file__)),
        "offline_checks": {"source_PNG_and_full_RGBA_match_existing_manifest": True,
                           "source_PNGs_unchanged_after_build": True, "material_subrects_fully_opaque": True,
                           "all_38_decorative_AABBs_plus_foot_radius_separated_by_at_least_2px": True,
                           "full_conservative_camera_view_has_floor": True},
        "integration_pending": ["Parent adds statue_gallery region scene, enum/world selection and route definitions",
                                "Parent configures SourceFraming horizontal limits [-152,536] before travel spawn/snap",
                                "Parent maps the intentionally empty collision scene and adds standard UI/audio/runtime region allowlists",
                                "Separate statue encounter, damage type and gate belong to parent; no battle or profile behavior is authored here",
                                "Parent native preview verifies window masking, lit architecture and both extreme camera views"],
        "not_run": ["Godot process, parser, editor or live scene", "Blender", "client executable"],
    }
    (ROOT / OUTPUTS[2]).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"outputs": OUTPUTS, "native_meshes": w.count, "source_cards": len(w.cards),
                      "expanded_decorative_AABBs": len(solids), "minimum_gap_px": minimum_gap,
                      "floor_margins_px": margins}, ensure_ascii=False))


if __name__ == "__main__":
    main()
