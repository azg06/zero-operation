import bpy, math
from mathutils import Vector
OUT = 'E:/工作目录2/models_probe'
for vid in ('jeep', 'tank', 'apc', 'aa'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath='E:/工作目录2/zero/steel_frontline_godot/models/vehicles/%s.glb' % vid)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    w = bpy.data.worlds.new('W')
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[0].default_value = (0.16, 0.20, 0.26, 1)
    w.node_tree.nodes['Background'].inputs[1].default_value = 1.2
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in sc.collection.objects:
        if o.type == 'MESH':
            for c in o.bound_box:
                wc = o.matrix_world @ Vector(c)
                mn.x = min(mn.x, wc.x); mn.y = min(mn.y, wc.y); mn.z = min(mn.z, wc.z)
                mx.x = max(mx.x, wc.x); mx.y = max(mx.y, wc.y); mx.z = max(mx.z, wc.z)
    ctr = (mn + mx) / 2
    size = (mx - mn).length
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam'))
    sc.collection.objects.link(cam)
    sc.camera = cam
    d = size * 1.55
    cam.location = ctr + Vector(((-d * 0.55), (-d * 0.60), (d * 0.42)))
    direction = ctr - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    sc.render.resolution_x = 800
    sc.render.resolution_y = 500
    sc.render.filepath = OUT + '/vglb_%s.png' % vid
    bpy.ops.render.render(write_still=True)
    print('SHOT', vid)
print('DONE')
