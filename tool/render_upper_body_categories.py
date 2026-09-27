"""Render upper-body categories from one mannequin, pose, camera and palette.

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python-exit-code 1 --python tool/render_upper_body_categories.py
"""
from pathlib import Path
import math
import os
import sys
import bpy
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
from category_highlight_regions import REGIONS, surface_weights
from mathutils import Vector, kdtree

ROOT = Path(__file__).resolve().parents[1]
UPPER_CATEGORIES = {
    'chest': ('pectoralisMajor',),
    'shoulders': ('anteriorDeltoid', 'posteriorDeltoid'),
    'arms': ('biceps', 'triceps', 'forearms'),
    'abs': ('rectusAbdominis',),
    'back': ('trapezius', 'latissimusDorsi'),
}
GRAY = (.50, .52, .54)
# The accepted abdominal thumbnail is the color/material reference for all.
HIGHLIGHT = (.48, .015, .025)
CATEGORIES = os.environ.get('SETKEEP_UPPER_CATEGORIES', ','.join(UPPER_CATEGORIES)).split(',')
assert all(c in UPPER_CATEGORIES for c in CATEGORIES)


def smoothstep(a, b, value):
    t = max(0, min(1, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def relax_arms(mesh):
    # Render-only continuous deformation: identical for every category. The
    # source GLB stays intact, including its abdominal surface and muscle masks.
    angle = math.radians(28)
    for vertex in mesh.vertices:
        x, y, z = vertex.co
        side = 1 if x >= 0 else -1
        weight = smoothstep(.16, .245, abs(x)) * smoothstep(.70, .88, z)
        theta = angle * weight
        dx, dz = abs(x) - .185, z - 1.37
        vertex.co.x = side * (.185 + math.cos(theta)*dx + math.sin(theta)*dz)
        vertex.co.z = 1.37 - math.sin(theta)*dx + math.cos(theta)*dz
    mesh.update()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/models/body_tab.glb'))
# Reuse the model's continuous mesh and existing anatomical material boundaries.
# Do not paint rectangles, add separate muscle objects, or alter the source mesh.
for obj in list(bpy.context.scene.objects):
    if obj.type != 'MESH':
        continue
    # Refine color sampling only; SIMPLE preserves the mannequin surface.
    bpy.context.view_layer.objects.active = obj
    sampling = obj.modifiers.new('Thumbnail color sampling', 'SUBSURF')
    sampling.subdivision_type = 'SIMPLE'
    sampling.levels = 2
    bpy.ops.object.modifier_apply(modifier=sampling.name)
    mesh = obj.data
    # Keep rest-position masks and coordinates before applying the shared pose.
    rest_positions = [v.co.copy() for v in mesh.vertices]
    masks = {}
    for face in mesh.polygons:
        name = mesh.materials[face.material_index].name
        masks.setdefault(name, set()).update(face.vertices)
    colors = mesh.color_attributes.new(name='CategoryHighlight', type='FLOAT_COLOR', domain='POINT')
    relax_arms(mesh)
    posed_positions = np.array([v.co[:] for v in mesh.vertices], dtype=np.float32)
    material = bpy.data.materials.new('Shared upper body heatmap')
    material.use_nodes = True
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .7
    attribute = material.node_tree.nodes.new('ShaderNodeVertexColor')
    attribute.layer_name = colors.name
    material.node_tree.links.new(attribute.outputs['Color'], shader.inputs['Base Color'])
    mesh.materials.clear()
    mesh.materials.append(material)
    for face in mesh.polygons:
        face.material_index = 0

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.threads_mode = 'FIXED'
scene.render.threads = 4
scene.render.resolution_x = 600
scene.render.resolution_y = 480
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.world = bpy.data.worlds.new('Upper body studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.8, .8, .8, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .06

# Match the upper-body category camera (chest/shoulders/arms).
# Mouth at the top edge, common shoulder width and torso position.
target = Vector((0, 0, 1.25))
def aim(obj):
    obj.rotation_euler = (target - obj.location).to_track_quat('-Z', 'Y').to_euler()

bpy.ops.object.camera_add(location=(0, -4, 1.25))
camera = bpy.context.object
camera.data.type = 'ORTHO'
camera.data.ortho_scale = .78
scene.camera = camera
for location, energy, size in [((-2, -3, 3), 130, 2), ((2, -2, 1.5), 35, 3), ((0, 3, 3), 100, 2)]:
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 1.16)) - light.location).to_track_quat('-Z', 'Y').to_euler()
aim(camera)

def highlight(category):
    if category in REGIONS:
        weights = surface_weights(category, posed_positions)
        rgba = np.ones((len(weights), 4), dtype=np.float32)
        rgba[:, :3] = np.array(GRAY) + weights[:, None] * (np.array(HIGHLIGHT) - np.array(GRAY))
        colors.data.foreach_set('color', rgba.ravel())
        mesh.update()
        return
    indices = set().union(*(masks['body_' + name] for name in UPPER_CATEGORIES[category]))
    if category == 'abs':
        indices = {i for i in indices if rest_positions[i].z < 1.215}
    tree = kdtree.KDTree(len(indices))
    for index, i in enumerate(sorted(indices)):
        tree.insert(rest_positions[i], index)
    tree.balance()
    lower = [min(rest_positions[i][axis] for i in indices) - .025 for axis in range(3)]
    upper = [max(rest_positions[i][axis] for i in indices) + .025 for axis in range(3)]
    for i, co in enumerate(rest_positions):
        weight = 0
        if category == 'abs':
            if .99 <= co.z < 1.215 and abs(co.x) <= .12 and co.y <= 0:
                distance = min(tree.find(co + Vector((0, 0, offset)))[2]
                               for offset in (-.018, -.009, 0, .009, .018))
                weight = math.exp(-((distance / .018) ** 2))
                edge = 1.215 - .022 * min(1, (abs(co.x) / .080) ** 2)
                weight *= smoothstep(0, .012, edge - co.z)
                if i in masks['body_pectoralisMajor']:
                    weight = 0
        elif all(lower[a] <= co[a] <= upper[a] for a in range(3)):
            distance = tree.find(co)[2]
            weight = math.exp(-((distance / .008) ** 2))
        colors.data[i].color = tuple(GRAY[k]*(1-weight) + HIGHLIGHT[k]*weight for k in range(3)) + (1,)


for category in CATEGORIES:
    highlight(category)
    direction = 1 if category == 'back' else -1
    camera.location.y = 4 * direction
    aim(camera)
    # Mirror the same studio for the posterior anatomical view.
    for light in (o for o in scene.objects if o.type == 'LIGHT'):
        is_rim = light.data.energy == 100
        light.location.y = abs(light.location.y) * (-direction if is_rim else direction)
        light.rotation_euler = (Vector((0, 0, 1.16)) - light.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(ROOT / 'assets/category_muscles' / f'{category}.png')
    bpy.ops.render.render(write_still=True)
