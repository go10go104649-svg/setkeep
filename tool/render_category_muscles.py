"""Render category PNGs from the same CC0 MPFB human as exercise forms."""
import os, pathlib, math, runpy, bpy
from mathutils import Vector
root=pathlib.Path(__file__).resolve().parents[1]
categories=os.environ.get('SETKEEP_CATEGORIES', os.environ.get('MUSCLEMORY_CATEGORIES','chest,back,shoulders,arms,legs,abs')).split(',')
upper=[c for c in categories if c in ('chest','back','shoulders','arms','abs')]
if upper:
 os.environ['SETKEEP_UPPER_CATEGORIES']=','.join(upper)
 runpy.run_path(str(root/'tool/render_upper_body_categories.py'), run_name='__main__')
 categories=[c for c in categories if c not in upper]
if not categories:
 raise SystemExit(0)
work=pathlib.Path(os.environ.get('SETKEEP_ART_WORK', os.environ.get('MUSCLEMORY_ART_WORK','/private/tmp/musclemory-3d-tools')))
bpy.ops.wm.open_mainfile(filepath=str(work/'base.blend'))
human=bpy.data.objects['Athlete'];scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=40;scene.cycles.use_denoising=True
scene.render.resolution_x=600;scene.render.resolution_y=480;scene.render.resolution_percentage=100
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.8,.8,.8,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.06
mat=human.data.materials[0];mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.7
bpy.context.view_layer.objects.active=human
sub=human.modifiers.new('Category paint sampling','SUBSURF');sub.subdivision_type='SIMPLE';sub.levels=2
bpy.ops.object.modifier_apply(modifier=sub.name)
colors=human.data.color_attributes['MuscleColor']
rig=bpy.data.objects['Athlete.rig']
for side,sign in [('l',1),('r',-1)]:
 for name,direction in [('upperarm',Vector((sign*.09,0,-.235))),('lowerarm',Vector((sign*.035,0,-.265)))]:
  bone=rig.data.bones[f'{name}_{side}'];pb=rig.pose.bones[bone.name]
  head=pb.head.copy()
  matrix=(bone.tail_local-bone.head_local).normalized().rotation_difference(direction.normalized()).to_matrix().to_4x4()@bone.matrix_local
  matrix.translation=head;pb.matrix=matrix;bpy.context.view_layer.update()

def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='CategoryOrthographic';cam.data.type='ORTHO';scene.camera=cam
lights=[]
for pos,power,size in [((-2,-3,3),130,2),((2,-2,1.5),35,3),((0,3,3),100,2)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,1.2));lights.append(o)
def smooth(a,b,v):
 t=max(0,min(1,(v-a)/(b-a)));return t*t*(3-2*t)
def oval(x,z,cx,cz,rx,rz):return 1-smooth(.85,1.02,math.sqrt(((x-cx)/rx)**2+((z-cz)/rz)**2))
for category in categories:
 for v in human.data.vertices:
  x,y,z=abs(v.co.x),v.co.y,v.co.z
  front=smooth(-.012,-.045,y);back=smooth(.005,.04,y)
  assert category=='legs', 'Activity categories use render_activity_categories.py'
  w=max(oval(x,z,.116,.735,.077,.205),oval(x,z,.115,.305,.062,.143))
  w=max(0,min(1,w));base=(.50,.52,.54);red=(.40,.006,.016)
  colors.data[v.index].color=(*(base[k]*(1-w)+red[k]*w for k in range(3)),1)
 scene.render.resolution_y=600 if category=='legs' else 480
 height=.54 if category=='legs' else 1.25
 direction=1 if category=='back' else -1
 cam.location=(0,4*direction,height);aim(cam,(0,0,height));cam.data.ortho_scale=1.06 if category=='legs' else .78
 for i,o in enumerate(lights):
  o.location.y=abs(o.location.y)*(direction if i<2 else -direction);aim(o,(0,0,height))
 scene.render.filepath=str(root/'assets/category_muscles'/f'{category}.png')
 bpy.ops.render.render(write_still=True)
