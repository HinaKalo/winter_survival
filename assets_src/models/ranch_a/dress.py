import bpy, math, os, random, json, hashlib
from mathutils import Vector
random.seed(42)
ROOT=r'C:\develop\blender\ranch_a_dressed'
SOURCE=r'C:\develop\blender\ranch_a_optimized\house.blend'
bpy.ops.wm.open_mainfile(filepath=SOURCE)
sc=bpy.context.scene
original={o.name:{'matrix':[round(v,6) for row in o.matrix_world for v in row], 'mesh': hashlib.sha256(b''.join(bytes(str(tuple(v.co)), 'utf8') for v in o.data.vertices)).hexdigest() if o.type=='MESH' else None} for o in sc.objects}
# Recreate any palette colors not used by the source blend (Blender purges unused materials).
import ast
tree=ast.parse(open(r'C:\develop\blender\ranch_a_optimized\build.py',encoding='utf-8-sig').read())
palette=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pal' for t in n.targets))
for family,values in palette.items():
 for i,h in enumerate(values):
  name=f'{family}_{i}'
  if name in bpy.data.materials: continue
  color=tuple(int(h[j:j+2],16)/255 for j in (0,2,4))+(1,)
  mat=bpy.data.materials.new(name); mat.diffuse_color=color; mat.use_nodes=True
  bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'); bsdf.inputs['Base Color'].default_value=color
  if family=='fire': bsdf.inputs['Emission Color'].default_value=color; bsdf.inputs['Emission Strength'].default_value=1.5
cols={n:bpy.data.collections[n] for n in ('B1','F1','F2','ROOF','REF')}
for level in ('B1','F1','F2'):
 c=bpy.data.collections.new('DRESS_'+level); sc.collection.children.link(c); cols['DRESS_'+level]=c
D=[]
def mesh(name,lev,parts):
 verts=[]; faces=[]; mids=[]; mats=[]
 for center,size,mat,rot in parts:
  if mat not in mats: mats.append(mat)
  mi=mats.index(mat); x,y,z=center; a,b,c=[q/2 for q in size]; ca,sa=math.cos(rot),math.sin(rot); start=len(verts)
  for X,Y,Z in [(-a,-b,-c),(-a,-b,c),(-a,b,-c),(-a,b,c),(a,-b,-c),(a,-b,c),(a,b,-c),(a,b,c)]: verts.append((x+X*ca-Y*sa,y+X*sa+Y*ca,z+Z))
  for f in ((0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6),(0,1,3,2),(4,6,7,5)): faces.append(tuple(start+i for i in f)); mids.append(mi)
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update(); ob=bpy.data.objects.new(name,me); cols['DRESS_'+lev].objects.link(ob)
 for mat in mats: me.materials.append(bpy.data.materials[mat])
 for p,i in zip(me.polygons,mids): p.material_index=i
 ob['set_dressing']=True; ob['collision']=False; ob['floor']=lev; D.append(ob); return ob
def add(p,x,y,z,sx,sy,sz,mat,r=0): p.append(((x,y,z),(sx,sy,sz),mat,r))
def prop(name,lev,x,y,z,sx,sy,sz,mat,rot=0): return mesh(name,lev,[((x,y,z),(sx,sy,sz),mat,rot)])
def cylindergroup(name,lev,spec):
 # Hexagonal cylinders aligned to X or Z, retained as one low-poly prop.
 verts=[]; faces=[]; inds=[]; materials=[]; n=6
 for (x,y,z),rad,length,axis,mat in spec:
  if mat not in materials: materials.append(mat)
  mi=materials.index(mat); start=len(verts)
  for end in (-length/2,length/2):
   for j in range(n):
    a=2*math.pi*j/n; u=rad*math.cos(a); v=rad*math.sin(a)
    verts.append((x+end,y+u,z+v) if axis=='X' else (x+u,y+v,z+end))
  faces.append(tuple(start+j for j in reversed(range(n)))); inds.append(mi)
  faces.append(tuple(start+n+j for j in range(n))); inds.append(mi)
  for j in range(n): faces.append((start+j,start+(j+1)%n,start+n+(j+1)%n,start+n+j)); inds.append(mi)
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update(); ob=bpy.data.objects.new(name,me); cols['DRESS_'+lev].objects.link(ob)
 for mat in materials: me.materials.append(bpy.data.materials[mat])
 for p,i in zip(me.polygons,inds): p.material_index=i
 ob['set_dressing']=True; ob['collision']=False; ob['floor']=lev; D.append(ob); return ob
def note(name,lev,x,y,z,w,h,ink='outline_1'):
 p=[]; add(p,x,y,z,w,.025,h,'snow_1')
 for k in range(3): add(p,x-w*.04,y-.02,z+h*.24-k*h*.19,w*(.57-.1*(k%2)),.012,.015,ink)
 mesh(name,lev,p)
# F1 living: 18 short pieces of stacked firewood, accessible from an open side.
logs=[]
for layer in range(3):
 for j in range(6):
  logs.append(((15.15+(j%3)*.29,-3.20+(j//3)*.33,.13+layer*.23),.105,.72,'X','wood_2' if (j+layer)%2 else 'wood_3'))
cylindergroup('DRESS_F1_firewood_18','F1',logs)
p=[]
for i,(x,y,a) in enumerate([(14.65,-4.35,.08),(15.85,-5.15,-.06)]):
 add(p,x,y,.10,.75,1.55,.20,'cloth_a_1',a); add(p,x-.05,y+.1,.23,.68,1.12,.08,'cloth_b_1',a); add(p,x+.11,y-.15,.30,.48,.48,.11,'cloth_a_2',a+.12)
mesh('DRESS_F1_living_bedrolls','F1',p)
p=[]; add(p,12.2,-5.48,.52,.83,.6,.11,'cloth_a_1',.09); add(p,12.15,-5.45,.60,.5,.40,.07,'cloth_a_2',-.15); mesh('DRESS_F1_sofa_blanket','F1',p)
p=[]; add(p,13.9,-2.15,2.27,5,.035,.035,'wood_1')
for i in range(4):
 x=12.15+i*1.1; y=-2.15; add(p,x,y,2.01,.57,.035,.49,('cloth_a_1','cloth_b_1','cloth_a_2','cloth_b_2')[i]); add(p,x-.18,y,2.26,.05,.06,.055,'wood_2'); add(p,x+.18,y,2.26,.05,.06,.055,'wood_2')
mesh('DRESS_F1_clothesline','F1',p)
# Candles cluster on a low side surface, avoiding the circulation path.
cylindergroup('DRESS_F1_candles','F1',[((14.4+i*.12,-1.35,.07),.035,.14,'Z','snow_1') for i in range(4)])
p=[]
for x,z,a in [(17.2,1.1,.12),(17.5,1.55,-.15),(17.8,.85,.08)]: add(p,x,-.385,z,.85,.06,.12,'wood_1',a)
add(p,17.5,-.37,1.65,.68,.035,.83,'cloth_a_1'); add(p,17.55,-.95,.035,1.3,.65,.07,'snow_2')
mesh('DRESS_F1_breach_patch_and_snow','F1',p)
# Bedroom displaced clothes and winter diary, kept clear of bed and wardrobe access.
p=[]
for x,y,a,m in [(5.3,-5.4,.3,'cloth_a_1'),(6,-5.1,-.25,'cloth_b_1'),(6.7,-5.6,.12,'cloth_a_2')]: add(p,x,y,.035,.52,.33,.07,m,a)
mesh('DRESS_F1_bedroom_clothes','F1',p)
note('DRESS_F1_calendar','F1',6,-.37,1.82,.52,.6)
# Kitchen cooking tools: on existing non-movable surfaces, no floor access obstructed.
p=[]; add(p,4.7,-12.48,1.45,.50,.40,.12,'concrete_1'); add(p,4.7,-12.48,1.55,.36,.30,.09,'concrete_2'); add(p,5.25,-12.48,1.53,.24,.25,.27,'concrete_2'); add(p,5.25,-12.48,1.7,.11,.11,.09,'concrete_1')
mesh('DRESS_F1_cooking_pots','F1',p)
cylindergroup('DRESS_F1_empty_cans','F1',[((4.7+i*.19,-8.5,.97),.07,.12,'Z','concrete_2') for i in range(4)])
p=[]; add(p,6,-10.5,.78,.38,.25,.012,'snow_1',.08); add(p,6,-10.5,.79,.22,.015,.012,'outline_1',.08); add(p,6.27,-10.6,.84,.07,.07,.16,'snow_1'); mesh('DRESS_F1_ration_note','F1',p)
cylindergroup('DRESS_F1_melt_bucket','F1',[((3.15,-10.25,.25),.25,.48,'Z','concrete_2')])
p=[]; add(p,3.6,-8.3,.09,.12,.38,.12,'concrete_1',-.15); add(p,3.6,-8.12,.09,.15,.08,.15,'concrete_3'); mesh('DRESS_F1_flashlight','F1',p)
# Work area: add tabletop hardware and a sawdust decal near the wall, not in the route.
p=[]
for i in range(4): add(p,18.42,-9.35-i*.14,.99,.17,.06,.06,'concrete_2',i*.19)
add(p,18.45,-10.1,1.01,.30,.12,.06,'concrete_1'); add(p,18.45,-10.32,.99,.24,.18,.10,'wood_1'); mesh('DRESS_F1_workbench_parts','F1',p)
p=[]
for i in range(8): add(p,16.65+random.random()*.8,-9.45-random.random()*.6,.012,.12+random.random()*.2,.06,.02,'wood_3',random.random()*2)
mesh('DRESS_F1_sawdust','F1',p)
cylindergroup('DRESS_F1_empty_fuel_can','F1',[((14,-11.8,.33),.22,.66,'Z','rust_1')])
p=[]; add(p,16,-12.25,.36,.07,.65,.07,'wood_2',.35); add(p,16.1,-12.53,.08,.26,.3,.06,'concrete_2',.35); mesh('DRESS_F1_shovel','F1',p)
# Basement boiler, root cellar, storage, and shelter.
p=[]; add(p,15,-4.8,-2.987,1.4,.75,.018,'concrete_1',.18)
for i in range(4): add(p,14.6+i*.25,-4.7+random.random()*.2,-2.976,.20,.12,.01,'outline_1',random.random())
mesh('DRESS_B1_oil_stain','B1',p)
p=[]
for y in (-2,-2.55,-3.1,-3.65): add(p,17,y,-.75,.23,.17,.23,'cloth_a_1')
mesh('DRESS_B1_pipe_insulation','B1',p)
note('DRESS_B1_thermometer','B1',15,-.37,-1.35,.22,.52)
cylindergroup('DRESS_B1_bucket','B1',[((14.4,-5.5,-2.76),.22,.46,'Z','concrete_2')])
p=[]
for i in range(7): add(p,4.7+random.random()*.75,-5.2+random.random()*.6,-2.97,.12,.16,.04,'ice_2',random.random()*3)
mesh('DRESS_B1_broken_jars','B1',p)
p=[]; add(p,7.8,-6.25,-2.96,.31,.19,.05,'wood_1'); add(p,7.8,-6.25,-2.92,.19,.02,.025,'concrete_2'); mesh('DRESS_B1_mousetrap','B1',p)
p=[]; add(p,6.8,-12.35,-2.95,.75,.5,.08,'wood_2',.12); add(p,6.8,-12.35,-2.75,.75,.05,.4,'wood_1',.12)
for i in range(6): add(p,7.5+random.random()*.55,-12.3+random.random()*.35,-2.97,.025,.15,.025,'concrete_2',random.random()*2)
mesh('DRESS_B1_open_crate_nails','B1',p)
cylindergroup('DRESS_B1_plastic_roll','B1',[((5,-12.5,-2.8),.18,1.1,'X','ice_2')])
# Low-poly bicycle indicated by frames and wheels, leaned against the east side of storage.
p=[]
for x in (6.4,7.55):
 for j in range(8):
  a=math.tau*j/8; add(p,x+.28*math.cos(a),-12.72,-2.69+.28*math.sin(a),.07,.06,.07,'concrete_1')
for x in (6.7,7.2): add(p,x,-12.72,-2.65,.55,.06,.06,'concrete_2',.08)
add(p,6.95,-12.72,-2.38,.06,.06,.5,'concrete_2'); mesh('DRESS_B1_old_bicycle','B1',p)
p=[]
for x,y in ((12,-9.5),(12,-11.5)):
 add(p,x+.2,y,-2.54,1.1,.7,.08,'cloth_b_2',.04); add(p,x+.45,y+.05,-2.47,.35,.6,.07,'cloth_a_1',-.08)
mesh('DRESS_B1_shelter_blankets','B1',p)
note('DRESS_B1_handdrawn_map','B1',14.3,-7.39,-1.35,.8,.56)
note('DRESS_B1_names','B1',13.3,-7.39,-1.35,.48,.65)
cylindergroup('DRESS_B1_lidded_bucket','B1',[((17,-10.5,-2.74),.24,.5,'Z','concrete_2'),((17,-10.5,-2.47),.25,.05,'Z','concrete_1')])
# Attic: thin dust on existing beds, wind frost, child's drawing, ornaments and insulation flakes.
p=[]
for y in (-2.5,-5.5): add(p,2,y,3.405,1.6,.68,.012,'concrete_4')
mesh('DRESS_F2_bed_dust','F2',p)
note('DRESS_F2_child_drawing','F2',6.5,-7.39,4.0,.68,.5,ink='rust_2')
p=[]
for i in range(4): add(p,4.2+i*.23,-11.65,3.06,.15,.12,.11,('wood_3','rust_2','cloth_b_2')[i%3],i*.2)
mesh('DRESS_F2_scattered_toys','F2',p)
p=[]; add(p,15,-1.5,3.52,.66,.55,.08,'wood_3'); add(p,15,-1.8,3.77,.7,.05,.5,'wood_2')
for i in range(5): add(p,14.8+i*.1,-1.5,3.62,.07,.07,.13,('rust_2','cloth_b_2','snow_2')[i%3])
mesh('DRESS_F2_open_holiday_box','F2',p)
p=[]
for i in range(8): add(p,16+random.random()*1.2,-10.8-random.random()*.8,3.025,.16,.12,.04,'rust_3',random.random()*2)
mesh('DRESS_F2_insulation_scraps','F2',p)
cylindergroup('DRESS_F2_snow_leak_basin','F2',[((16,-8.6,3.08),.35,.16,'Z','concrete_2')])
# Interior frost applied to glass. The source windows stay untouched.
for lev,c,r,z in [('F1',0,9,0),('F1',19,3,0),('F1',19,11,0),('F2',0,6,3),('F2',19,6,3)]:
 x=c+.5+(.12 if c==0 else -.12); y=-r-.5; p=[]
 for k in range(3): add(p,x,y-.28+k*.27,z+1.10,.012,.23,.34,'snow_2')
 mesh(f'DRESS_{lev}_frost_{c}_{r}',lev,p)
# Soot, draught seals and story notes, all thin wall decals.
p=[]; add(p,11.1,-.38,1.65,1.0,.015,1.35,'concrete_2'); mesh('DRESS_F1_soot_patch','F1',p)
p=[]; add(p,11.99,-13.38,1.05,.12,.035,2.05,'cloth_b_1'); add(p,13.01,-13.38,1.05,.12,.035,2.05,'cloth_b_1'); mesh('DRESS_F1_door_draught_seal','F1',p)
note('DRESS_F1_family_photo','F1',7.6,-.39,1.45,.42,.34)
# Exterior siding: continuous horizontal board faces, clipped around the original openings.
for lev,z0 in [('F1',0),('F2',3)]:
 verts=[]; faces=[]; mids=[]
 for r,y in [(0,-.37),(13,-13.63)]:
  gaps=(set(range(1,8))|set(range(11,18)) if r==0 else set(range(1,11))|{12}|set(range(14,19))) if lev=='F1' else (set(range(10,17)) if r==0 else set(range(11,19)))
  runs=[]; start=None
  for c in range(21):
   filled=c<20 and c not in gaps
   if filled and start is None: start=c
   if not filled and start is not None: runs.append((start,c)); start=None
  top=2.7 if lev=='F1' else 1.0; bands=5 if lev=='F1' else 2
  for x1,x2 in runs:
   for j in range(bands):
    low=z0+j*top/bands; high=z0+(j+1)*top/bands-.018; k=len(verts)
    verts.extend([(x1+.03,y,low),(x2-.03,y,low),(x2-.03,y,high),(x1+.03,y,high)]); faces.append((k,k+1,k+2,k+3)); mids.append(j%2)
 me=bpy.data.meshes.new('EXT_siding_'+lev); me.from_pydata(verts,[],faces); ob=bpy.data.objects.new('EXT_DRESS_'+lev+'_horizontal_siding',me); cols['DRESS_'+lev].objects.link(ob); D.append(ob)
 for m in ('cloth_a_1','cloth_a_2'): me.materials.append(bpy.data.materials[m])
 for poly,mi in zip(me.polygons,mids): poly.material_index=mi
 ob['set_dressing']=True; ob['collision']=False; ob['floor']=lev
# Chimney aligned with stove pipe; smoke and icicles are additions only.
p=[]; add(p,12.5,-3.5,5.69,.52,.52,1.55,'rust_1'); add(p,12.5,-3.5,6.48,.68,.68,.12,'concrete_2'); add(p,12.5,-3.5,6.56,.42,.42,.06,'outline_1')
for i in range(4): add(p,12.5+i*.12,-3.5+i*.04,6.78+i*.25,.28+i*.06,.25+i*.05,.22,'concrete_4',i*.13)
mesh('EXT_DRESS_F2_chimney_smoke','F2',p)
p=[]
for y in (-.57,-13.43):
 for i in range(16):
  x=.9+i*1.2; h=.12+(i%4)*.055; add(p,x,y,3.96-h/2,.06,.06,h,'ice_3')
mesh('EXT_DRESS_F2_icicles','F2',p)
# Rounded snowbanks are faceted half-domes, separated at the entrance path.
def snowbank(name,x,y,sx,sy):
 n=12; verts=[]; faces=[]
 for radius,height in ((1,0),(.78,.28),(.4,.52),(.05,.62)):
  for i in range(n):
   a=math.tau*i/n; verts.append((x+sx*radius*math.cos(a),y+sy*radius*math.sin(a),-.29+height))
 for r in range(3):
  for i in range(n): faces.append((r*n+i,r*n+(i+1)%n,(r+1)*n+(i+1)%n,(r+1)*n+i))
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.materials.append(bpy.data.materials['snow_3']);
 for poly in me.polygons: poly.use_smooth=True
 ob=bpy.data.objects.new(name,me); cols['DRESS_F2'].objects.link(ob); D.append(ob); ob['collision']=False; ob['set_dressing']=True; ob['floor']='F2'
for i,(x,y,sx,sy) in enumerate([(3,-14.3,2,.8),(8,-14.25,2.1,.8),(17,-14.2,2.8,.8),(-.55,-5,.8,2.6),(-.55,-10,.8,2.2),(20.55,-4,.8,2.8),(20.55,-10,.8,2.5)]): snowbank('EXT_DRESS_F2_snowbank_%02d'%i,x,y,sx,sy)
# WAR DAMAGE PASS: heavy soot, exposed lath and shrapnel scars are added as non-colliding overlays.
# Existing walls and traversable openings remain intact beneath the damage meshes.
for lev,z0,seed in [('F1',0,101),('B1',-3,102),('F2',3,103)]:
 rng=random.Random(seed); p=[]
 # Dense dark impact scars across solid north/south wall spans; skip all openings.
 for y,intervals in [(-.625,[(1.0,8.7),(10.1,16.75),(18.15,18.8)]),(-13.375,[(1.0,11.75),(13.2,18.8)])]:
  for x1,x2 in intervals:
   for i in range(15):
    x=rng.uniform(x1,x2); z=z0+rng.uniform(.12,1.12); w=rng.uniform(.06,.23); h=rng.uniform(.05,.22)
    add(p,x,y,z,w,.012,h,rng.choice(['concrete_1','wood_1','outline_1']),rng.uniform(-.08,.08))
 # Large plaster loss with exposed wooden lath, on intact perimeter wall away from exits.
 for x,y in [(2.8,-.63),(6.8,-.63),(11.4,-.63),(16,-13.37),(7,-13.37)]:
  add(p,x,y,z0+.75,1.05,.014,.62,'concrete_2')
  for j in range(4): add(p,x,y-.012,z0+.52+j*.14,.9,.018,.035,'wood_1')
  for dx,dz in [(-.43,.4),(.38,1.08),(.49,.9)]: add(p,x+dx,y-.016,z0+dz,.10,.018,.16,'outline_1')
 # A jagged crack per partition segment, on solid wall and below cut height.
 for x in (1.7,6.9,11.9,17.8):
  for j in range(4): add(p,x+(-1 if j%2 else 1)*.035,-7.38,z0+.25+j*.16,.075,.015,.19,'concrete_1')
 mesh('DRESS_'+lev+'_war_wall_scars',lev,p)
# Floor litter concentrated in corners and around existing rubble, away from door and stair cells.
for lev,z0,locations,seed in [
 ('F1',0,[(7.5,-6.2),(14.1,-1.4),(16.8,-11.8),(17.4,-12.2),(11.0,-12.2)],211),
 ('B1',-3,[(4.8,-4.7),(7.3,-6.0),(6.7,-12.1),(16.8,-12.3),(18.1,-8.6)],212),
 ('F2',3,[(7.7,-6.1),(4.6,-12.2),(11.3,-12.2),(16.5,-10.6),(14.1,-6.5)],213)]:
 rng=random.Random(seed); p=[]
 for cx,cy in locations:
  for i in range(9):
   x=cx+rng.uniform(-.36,.36); y=cy+rng.uniform(-.30,.30)
   add(p,x,y,z0+.025+rng.random()*.055,rng.uniform(.11,.34),rng.uniform(.05,.16),rng.uniform(.035,.10),rng.choice(['concrete_2','concrete_3','wood_1','wood_2']),rng.uniform(-2,2))
 mesh('DRESS_'+lev+'_war_floor_shards',lev,p)
# Irregular broken siding and large blackened blast marks obscure the clean facade on solid spans.
p=[]
for x,z in [(2.8,.8),(6,1.5),(8.3,.7),(14.3,1.65),(17.8,.9)]:
 y=-13.665; add(p,x,y,z,1.1,.018,.5,'outline_1')
 for i in range(4): add(p,x-.42+i*.28,y-.015,z-.15+i*.09,.35,.02,.055,'wood_1',(-1)**i*.08)
 for dx,dz in [(-.55,.28),(.5,-.23),(.28,.32)]: add(p,x+dx,y-.02,z+dz,.12,.02,.12,'concrete_2')
mesh('EXT_DRESS_F1_blast_scars','F1',p)
# Three rough rust-colored roof scars laid directly onto the snow, visually reading as missing roof patches.
verts=[]; faces=[]; mats=[]
def roof_z(y): return 4+2.2*min((-y-.5)/6.5,(13.5+y)/6.5)+.19
for x,y,rx,ry in [(4,-4.2,.8,.55),(9.7,-10.5,1,.6),(17.3,-3.8,.65,.45)]:
 base=len(verts)
 for dx,dy in [(-rx,-ry),(.15*rx,-ry*.65),(rx,-.1*ry),(.4*rx,ry),(-.65*rx,ry*.7)]:
  yy=y+dy; verts.append((x+dx,yy,roof_z(yy)))
 faces.append(tuple(base+j for j in range(5)))
me=bpy.data.meshes.new('war_roof_damage'); me.from_pydata(verts,[],faces); me.materials.append(bpy.data.materials['rust_1']); ob=bpy.data.objects.new('EXT_DRESS_F2_roof_blast_scars',me); cols['DRESS_F2'].objects.link(ob); D.append(ob); ob['set_dressing']=True; ob['collision']=False; ob['floor']='F2'

# Keep decorative marks paper-thin: retain only visible faces to protect the 30k house budget.
import bmesh
for name in ['DRESS_F1_war_wall_scars','DRESS_B1_war_wall_scars','DRESS_F2_war_wall_scars','DRESS_F1_war_floor_shards','DRESS_B1_war_floor_shards','DRESS_F2_war_floor_shards','EXT_DRESS_F1_blast_scars']:
 ob=bpy.data.objects[name]; bm=bmesh.new(); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
 keep={1} if '_floor_' in name else {2,3}
 remove=[f for i,f in enumerate(bm.faces) if i%6 not in keep]; bmesh.ops.delete(bm,geom=remove,context='FACES_ONLY')
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS'); bm.to_mesh(ob.data); bm.free(); ob.data.update()

# Authorized structural destruction: edit mesh data only, preserving object names and transforms.
# Deliberate breaches avoid all named doorway and stair cells.
wall_regions={
 'F1':[(1,8,-.71,-.29),(11,17,-.71,-.29),(1,11,-13.71,-13.29),(14,19,-13.71,-13.29),(6,8,-7.71,-7.29)],
 'F2':[(10,17,-.71,-.29),(11,19,-13.71,-13.29)],
 'B1':[(5,9,-13.71,-13.29),(19.29,19.71,-7,-4)]}
def remove_components_in_regions(ob,regions):
 bm=bmesh.new(); bm.from_mesh(ob.data); unseen=set(bm.verts); remove=[]
 while unseen:
  seed=unseen.pop(); stack=[seed]; comp=[seed]
  while stack:
   v=stack.pop()
   for e in v.link_edges:
    other=e.other_vert(v)
    if other in unseen: unseen.remove(other); stack.append(other); comp.append(other)
  center=sum((v.co for v in comp),Vector())/len(comp); x,y=center.x,center.y
  if any(x1+1e-5<x<x2-1e-5 and y1+1e-5<y<y2-1e-5 for x1,x2,y1,y2 in regions): remove.extend(comp)
 if remove: bmesh.ops.delete(bm,geom=remove,context='VERTS')
 bm.to_mesh(ob.data); bm.free(); ob.data.update()
for lev,regions in wall_regions.items():
 for tier in ('low','high'): remove_components_in_regions(bpy.data.objects[lev+'_wall_'+tier],regions)
 # Remove added wall marks that would otherwise float across the breach.
 for suffix in ('war_wall_scars',): remove_components_in_regions(bpy.data.objects['DRESS_'+lev+'_'+suffix],regions)
# Rebuild the same floor objects as contiguous solid strips, removing only selected damaged tiles.
floor_holes={'F1':{(c,r) for c in (16,17) for r in (11,12)},'F2':{(c,r) for c in (16,17,18) for r in (8,9)}|{(c,10) for c in (17,18)}}
for lev,holes in floor_holes.items():
 ob=bpy.data.objects[lev+'_floor']; z=0 if lev=='F1' else 3; verts=[]; faces=[]
 def cuboid(x1,x2,y1,y2,z1,z2):
  k=len(verts); verts.extend([(x1,y1,z1),(x1,y1,z2),(x1,y2,z1),(x1,y2,z2),(x2,y1,z1),(x2,y1,z2),(x2,y2,z1),(x2,y2,z2)])
  for f in [(0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6),(0,1,3,2),(4,6,7,5)]: faces.append(tuple(k+i for i in f))
 for r in range(14):
  start=None
  for c in range(21):
   stair=(lev=='F1' and c in (1,2) and 8<=r<=12) or (lev=='F2' and c in (17,18) and 1<=r<=5)
   filled=c<20 and not stair and (c,r) not in holes
   if filled and start is None: start=c
   if not filled and start is not None: cuboid(start,c,-r-1,-r,z-.3,z); start=None
 ob.data.clear_geometry(); ob.data.from_pydata(verts,[],faces); ob.data.update()
 # Remove decorative seams above missing tiles, keeping the hole visually open.
 remove_components_in_regions(bpy.data.objects[lev+'_floorboard_seams'],[(c,c+1,-r-1,-r) for c,r in holes])
# Fractured stubs, exposed framing and crooked planks around the new wall openings.
for lev,z0,regions in [('F1',0,wall_regions['F1']),('F2',3,wall_regions['F2']),('B1',-3,wall_regions['B1'])]:
 p=[]
 for x1,x2,y1,y2 in regions:
  if x2-x1<.6: continue
  y=(y1+y2)/2
  for x,h in [(x1+.07,.42),(x2-.08,.78)]: add(p,x,y,z0+h/2,.13,.22,h,'wood_1',.1)
  add(p,(x1+x2)/2,y,z0+1.38,x2-x1-.2,.09,.09,'wood_1',.12)
  add(p,x1+.4,y,z0+.13,.6,.19,.22,'concrete_2',.25)
 mesh('DRESS_'+lev+'_fractured_wall_edges',lev,p)
for lev,z0,segments in [('F1',0,[(16,18,-11.5),(16,18,-12.5)]),('F2',3,[(16,19,-8.5),(16,19,-9.5),(17,19,-10.5)])]:
 p=[]
 for x1,x2,y in segments:
  for j in range(3):
   # Incomplete, uneven boards make the unsupported hole obvious without filling it.
   add(p,(x1+x2)/2,y-.28+j*.28,z0-.03,(x2-x1)*(.72 if j==1 else .96),.10,.08,'wood_1' if j==1 else 'wood_2',(.04 if j%2 else -.03))
 mesh('DRESS_'+lev+'_fractured_floor_boards',lev,p)
# Actual roof and snow perforations. Modifier targets only existing roof panels, not walls or objects in rooms.
for i,(x,y,w,d) in enumerate([(6,-3.2,4.0,2.5),(15,-10.5,4.0,2.4),(17,-4.5,3.0,1.8),(4,-10.5,3.5,2.3)]):
 bpy.ops.mesh.primitive_cube_add(size=1,location=(x,y,5.2)); cutter=bpy.context.object; cutter.name='_temporary_roof_cutter'; cutter.dimensions=(w,d,4.5); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for name in ('roof_panel_0','roof_panel_1','roof_snow_0','roof_snow_1'):
  target=bpy.data.objects[name]; target.hide_set(False); bpy.ops.object.select_all(action='DESELECT'); target.select_set(True); bpy.context.view_layer.objects.active=target
  mod=target.modifiers.new('war_damage_boolean','BOOLEAN'); mod.operation='DIFFERENCE'; mod.solver='EXACT'; mod.object=cutter; bpy.ops.object.modifier_apply(modifier=mod.name)
 bpy.data.objects.remove(cutter,do_unlink=True)

# Broken roof rafters and splintered ribs, with nonparallel, incomplete spans.
verts=[]; faces=[]
def beam3(a,b,width):
 a=Vector(a); b=Vector(b); direction=(b-a).normalized(); side=direction.cross(Vector((0,0,1)))
 if side.length<1e-5: side=Vector((1,0,0))
 side.normalize(); up=direction.cross(side).normalized(); k=len(verts)
 for p in (a,b):
  for u,v in [(-1,-1),(-1,1),(1,-1),(1,1)]: verts.append(tuple(p+side*(u*width/2)+up*(v*width/2)))
 for f in [(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)]: faces.append(tuple(k+i for i in f))
def roof_at(y): return 4+2.2*min((-y-.5)/6.5,(13.5+y)/6.5)+.08
for x,y,w,d in [(6,-3.2,4.0,2.5),(15,-10.5,4.0,2.4),(17,-4.5,3.0,1.8),(4,-10.5,3.5,2.3)]:
 for j in range(4):
  yy=y-d*.36+j*d*.24; reach=w*(.28+(j%3)*.12); left=x-w*.53; right=left+reach
  beam3((left,yy,roof_at(yy)),(right,yy+.06,roof_at(yy+.06)-.05*(j%2)),.10)
 for side in (-1,1):
  xx=x+side*w*.49; beam3((xx,y-d*.53,roof_at(y-d*.53)),(xx+.12,y+d*.28,roof_at(y+d*.28)-.09),.12)
me=bpy.data.meshes.new('splintered_rafters'); me.from_pydata(verts,[],faces); me.materials.append(bpy.data.materials['wood_1']); ob=bpy.data.objects.new('EXT_DRESS_F2_splintered_rafters',me); cols['DRESS_F2'].objects.link(ob); D.append(ob); ob['set_dressing']=True; ob['collision']=False; ob['floor']='F2'
# Heavier collapsed fragments around existing damaged floor areas, not in doorways or stairs.
for lev,z,cx,cy in [('F1',0,17,-11.7),('F2',3,17.2,-9),('B1',-3,18.3,-12.2)]:
 p=[]; rng=random.Random(350+int(z*3))
 for i in range(12):
  add(p,cx+rng.uniform(-.7,.7),cy+rng.uniform(-.65,.65),z+.08+rng.random()*.12,rng.uniform(.18,.55),rng.uniform(.12,.30),rng.uniform(.08,.22),rng.choice(['concrete_2','wood_1','wood_2']),rng.uniform(-2,2))
 mesh('DRESS_'+lev+'_collapsed_fragments',lev,p)

# No usable beds or upholstered sofa remain: replace only their mesh data with broken debris,
# preserving object identifiers, origins and transforms for consumers that track them.
for objname,x,y,z in [('F1_bed',2,-2,0),('F1_sofa',12.5,-5.5,0),('B1_cot_1',12,-9.5,-3),('B1_cot_2',12,-11.5,-3),('F2_bed_1',2,-2.5,3),('F2_bed_2',2,-5.5,3),('F2_kid_bed',2,-11.5,3)]:
 ob=bpy.data.objects[objname]; verts=[]; faces=[]; rng=random.Random(objname)
 inv=ob.matrix_world.inverted()
 for j in range(8):
  x0=x+rng.uniform(-.5,.5); y0=y+rng.uniform(-.4,.4); length=rng.uniform(.3,.8); width=rng.uniform(.04,.1); angle=rng.uniform(-1.1,1.1); ca=math.cos(angle); sa=math.sin(angle); k=len(verts)
  for dx,dy,dz in [(-length/2,-width/2,0),(-length/2,-width/2,.05),(-length/2,width/2,0),(-length/2,width/2,.05),(length/2,-width/2,0),(length/2,-width/2,.05),(length/2,width/2,0),(length/2,width/2,.05)]:
   verts.append(tuple(inv @ Vector((x0+dx*ca-dy*sa,y0+dx*sa+dy*ca,z+.025+dz))))
  for f in [(0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6),(0,1,3,2),(4,6,7,5)]: faces.append(tuple(k+i for i in f))
 ob.data.clear_geometry(); ob.data.from_pydata(verts,[],faces); ob.data.materials.clear(); ob.data.materials.append(bpy.data.materials['wood_1']); ob.data.update()
for name in ('DRESS_F1_living_bedrolls','DRESS_F1_sofa_blanket','DRESS_B1_shelter_blankets','DRESS_F2_bed_dust'):
 ob=bpy.data.objects.get(name)
 if ob:
  if ob in D: D.remove(ob)
  bpy.data.objects.remove(ob,do_unlink=True)
# Chimney remains as a ruined structure; remove its four smoke components.
remove_components_in_regions(bpy.data.objects['EXT_DRESS_F2_chimney_smoke'],[]) if False else None
ob=bpy.data.objects['EXT_DRESS_F2_chimney_smoke']; bm=bmesh.new(); bm.from_mesh(ob.data)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z>6.62],context='VERTS'); bm.to_mesh(ob.data); bm.free(); ob.data.update()

# Cold pass: windblown powder and ice are flat, non-colliding palette meshes.
def flat_polygons(name,lev,polygons):
 verts=[]; faces=[]; mids=[]; materials=[]
 for points,mat in polygons:
  if mat not in materials: materials.append(mat)
  k=len(verts); verts.extend(points); faces.append(tuple(k+i for i in range(len(points)))); mids.append(materials.index(mat))
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
 for mat in materials: me.materials.append(bpy.data.materials[mat])
 for poly,mi in zip(me.polygons,mids): poly.material_index=mi
 ob=bpy.data.objects.new(name,me); cols['DRESS_'+lev].objects.link(ob); D.append(ob)
 ob['set_dressing']=True; ob['collision']=False; ob['floor']=lev; return ob
# Irregular feathered snow tongues placed along broken outer walls and under the roof breaches.
for lev,z,patches in [
 ('F1',.014,[(5.25,-1.15,2.0,.72),(13.9,-1.2,2.2,.78),(16.0,-12.9,1.8,.38),(8.2,-12.95,1.35,.28)]),
 ('F2',3.014,[(6.2,-3.1,1.9,1.0),(12.6,-1.15,2.0,.72),(15.4,-10.7,1.2,.65),(4.1,-10.5,1.65,.72)]),
 ('B1',-2.986,[(5.2,-12.9,1.4,.38),(16.8,-5.4,1.1,.36)])]:
 polys=[]
 for x,y,w,d in patches:
  ring=[(-.53,-.32),(-.31,-.5),(.01,-.42),(.34,-.46),(.53,-.16),(.43,.25),(.18,.43),(-.16,.36),(-.48,.26)]
  outer=[(x+dx*w,y+dy*d,z) for dx,dy in ring]
  inner=[(x+dx*w*.65,y+dy*d*.55,z+.004) for dx,dy in ring]
  polys.append((outer,'snow_1')); polys.append((inner,'snow_2'))
 flat_polygons('DRESS_'+lev+'_windblown_snow',lev,polys)
# Thin irregular frozen seepage and shards; positions stay away from door and stair tiles.
for lev,z,patches in [('F1',.018,[(7.6,-5.8,1.1,.55),(15.4,-3.2,1,.45),(17,-10.6,1.1,.45)]),('F2',3.018,[(7.8,-5.8,1.0,.38),(15.3,-8.0,1.4,.55),(5.7,-11.9,.9,.35)]),('B1',-2.982,[(4.6,-5.1,1,.4),(17.7,-8.6,.9,.4)])]:
 polys=[]
 for x,y,w,d in patches:
  polys.append(([(x-w*.5,y-d*.25,z),(x-w*.25,y-d*.53,z),(x+w*.35,y-d*.42,z),(x+w*.52,y+d*.1,z),(x+w*.22,y+d*.48,z),(x-w*.4,y+d*.36,z)],'ice_2'))
  polys.append(([(x-w*.33,y,z+.003),(x+w*.22,y+d*.17,z+.003),(x+w*.34,y+d*.23,z+.003),(x-w*.20,y+.05,z+.003)],'snow_1'))
 flat_polygons('DRESS_'+lev+'_floor_ice',lev,polys)
# Ice crystals climb surviving side walls, with pointed tops rather than a flat blue stripe.
for lev,z,x,yside in [('F1',0,.625,(-3.0,-6.3)),('F2',3,19.375,(-8.0,-12.4)),('B1',-3,.625,(-3.2,-6.0))]:
 a,b=yside; polys=[]
 for i in range(14):
  y=a+(b-a)*(i+.5)/14; width=abs(b-a)/14*.72; h=.15+(i%5)*.08
  polys.append(([(x,y-width/2,z+.04),(x,y+width/2,z+.04),(x,y+.02,z+h)],'snow_2' if i%3 else 'ice_3'))
 flat_polygons('DRESS_'+lev+'_wall_frost',lev,polys)
# Filiform cracks remain visible in the surviving planks beside each actual floor failure.
for lev,z,cx,cy in [('F1',.022,15.5,-11.3),('F2',3.022,15.4,-8.8)]:
 polys=[]; px=cx; py=cy
 for i in range(12):
  nx=px-.13; ny=py+(.08 if i%2 else -.10); vx=nx-px; vy=ny-py; length=math.hypot(vx,vy); ox=-vy/length*.018; oy=vx/length*.018
  polys.append(([(px+ox,py+oy,z),(px-ox,py-oy,z),(nx-ox,ny-oy,z),(nx+ox,ny+oy,z)],'outline_1')); px,py=nx,ny
 flat_polygons('DRESS_'+lev+'_fractured_floor_cracks',lev,polys)

# Total-war pass: eliminate recognizable comfortable furniture and intact amenities.
# Their original object identifiers and origins survive, but their meshes become low, scattered wreckage.
ruined=[
 ('F1_nightstand',3.5,-1.5,0,'wood_1'),('F1_wardrobe',8,-1.5,0,'wood_1'),
 ('F1_shelf_a',10.5,-1.5,0,'wood_1'),('F1_shelf_b',10.5,-2.5,0,'wood_1'),
 ('F1_counter',6.5,-8.5,0,'wood_1'),('F1_table',6,-10.5,0,'wood_1'),
 ('F1_chair_1',5,-10.5,0,'wood_1'),('F1_chair_2',7,-10.5,0,'wood_1'),
 ('F1_fridge',8.5,-12.3,0,'concrete_2'),('F1_fridge_door',8.5,-12.3,0,'concrete_2'),
 ('F1_woodstove_off',12.5,-3.5,0,'concrete_1'),('F1_woodstove_on',12.5,-3.5,0,'concrete_1'),
 ('F1_hearth_off',5,-12.5,0,'rust_1'),('F1_hearth_on',5,-12.5,0,'rust_1'),
 ('F1_generator',12.5,-10.5,0,'rust_1'),('F1_workbench',18.4,-10,0,'wood_1'),
 ('F1_toolrack',15,-12.5,0,'wood_1'),('F1_electric_heater',15.5,-6.5,0,'concrete_1'),
 ('F1_humidifier',11.5,-1.5,0,'concrete_2'),('F1_oil_lamp',3.5,-1.5,0,'concrete_1'),
 ('F1_stove_pipe',12.5,-3.5,0,'concrete_1'),
 ('B1_cellar_shelf_1',2.5,-1.5,-3,'wood_1'),('B1_cellar_shelf_2',6,-1.5,-3,'wood_1'),
 ('B1_cellar_shelf_3',1.5,-4,-3,'wood_1'),('B1_metal_shelf',8.5,-9,-3,'concrete_1'),
 ('B1_potato_bin',7,-5.5,-3,'wood_1'),('B1_boiler_off',17,-3,-3,'concrete_1'),
 ('B1_boiler_on',17,-3,-3,'concrete_1'),('B1_oiltank',13,-1.6,-3,'rust_1'),
 ('B1_heater_small',15.5,-10.5,-3,'concrete_1'),('B1_lantern',14.5,-8.5,-3,'concrete_1'),
 ('F2_dresser',8,-1.5,3,'wood_1'),('F2_toy_chest',6.5,-12.5,3,'wood_1'),('F2_trunk',13.5,-10.5,3,'wood_1')]
# Tidy rugs, stacked cartons, barrels and most insulation are torn or crushed as well.
ruined.extend([('F1_rug_bedroom',5,-4,0,'rust_1'),('F2_rug_kids',5,-10.5,3,'cloth_a_1')])
for i in range(8): ruined.append(('F2_box_%02d'%i,11.5+i%4*1.2,-1.5-(i//4)*1.1,3,'wood_1'))
for i in range(6): ruined.append(('B1_crate_%02d'%i,5.5+i%3*.7,-11.5-i//3*.7,-3,'wood_1'))
for i in range(2): ruined.append(('B1_barrel_'+str(i+1),3.2+i*.7,-6.5,-3,'wood_1'))
for i in range(2): ruined.append(('F2_insulation_roll_'+str(i+1),15.5+i,-11.5,3,'rust_2'))
for objname,x,y,z,mat in ruined:
 ob=bpy.data.objects.get(objname)
 if not ob or ob.type!='MESH': continue
 verts=[]; faces=[]; rng=random.Random(objname); inv=ob.matrix_world.inverted()
 for j in range(6):
  x0=x+rng.uniform(-.38,.38); y0=y+rng.uniform(-.30,.30); length=rng.uniform(.23,.65); width=rng.uniform(.05,.14); angle=rng.uniform(-1.35,1.35); ca=math.cos(angle); sa=math.sin(angle); k=len(verts)
  for dx,dy,dz in [(-length/2,-width/2,0),(-length/2,-width/2,.045),(-length/2,width/2,0),(-length/2,width/2,.045),(length/2,-width/2,0),(length/2,-width/2,.045),(length/2,width/2,0),(length/2,width/2,.045)]:
   verts.append(tuple(inv @ Vector((x0+dx*ca-dy*sa,y0+dx*sa+dy*ca,z+.03+j*.008+dz))))
  for f in [(0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6),(0,1,3,2),(4,6,7,5)]: faces.append(tuple(k+i for i in f))
 ob.data.clear_geometry(); ob.data.from_pydata(verts,[],faces); ob.data.materials.clear(); ob.data.materials.append(bpy.data.materials[mat]); ob.data.update(); ob['ruined_nonfunctional']=True
# Clean staged lifestyle details off the now-destroyed surfaces.
for name in ('DRESS_F1_firewood_18','DRESS_F1_clothesline','DRESS_F1_candles','DRESS_F1_cooking_pots','DRESS_F1_empty_cans','DRESS_F1_ration_note','DRESS_F1_workbench_parts','DRESS_F1_workbench_supplies','DRESS_B1_pipe_insulation','DRESS_F2_open_holiday_box'):
 ob=bpy.data.objects.get(name)
 if ob:
  if ob in D: D.remove(ob)
  bpy.data.objects.remove(ob,do_unlink=True)
# The old free-standing tableware and workshop tools were introduced in the prior source.
for name in ('F1_tableware','F1_workbench_tools','F1_workbench_supplies'):
 ob=bpy.data.objects.get(name)
 if ob and ob.type=='MESH': ob.data.clear_geometry(); ob.data.update(); ob['ruined_nonfunctional']=True

# Capture provenance before any temporary render/explode transforms.
sc['set_dressing_source']=SOURCE
for ob in D:
 if 'set_dressing' not in ob: ob['set_dressing']=True; ob['collision']=False
# Export every original floor plus its corresponding dress collection; all object coordinates remain unchanged.
def export(fname,groups):
 for ob in sc.objects:
  ob.hide_set(False); ob.select_set(False)
 for group in groups:
  for ob in cols[group].objects:
   if ob.type=='MESH': ob.select_set(True)
 bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,fname),export_format='GLB',use_selection=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
for lev in ('B1','F1','F2'): export('floor_'+('1F' if lev=='F1' else '2F' if lev=='F2' else 'B1')+'.glb',[lev,'DRESS_'+lev])
export('house_full.glb',['B1','F1','F2','ROOF','DRESS_B1','DRESS_F1','DRESS_F2'])
cam=sc.camera; sc.render.engine='BLENDER_WORKBENCH'; sc.render.resolution_x=1280; sc.render.resolution_y=720; sc.render.resolution_percentage=100
cam.rotation_euler=(math.radians(60),0,math.radians(45))
def camera(z,scale):
 cam.data.ortho_scale=scale; cam.location=Vector((10,-7,z))+(cam.rotation_euler.to_matrix() @ Vector((0,0,35)))
def vis(levels,cut=False,exterior=False,night=False):
 for key,col in cols.items():
  for ob in col.objects:
   lev=key.replace('DRESS_',''); visible=(lev in levels)
   if key=='REF': visible=(ob.type!='MESH' or (not exterior and not night and any(ob.name.startswith('REF_'+n+'_') for n in levels)))
   if ob.name.startswith('EXT_'): visible=exterior
   if ob.name.endswith('_on'): visible=False
   if cut and (ob.name.endswith('_wall_high') or ob.name.startswith('B1_window_') or ob.name in {'DRESS_F1_calendar','DRESS_F1_family_photo','DRESS_B1_handdrawn_map','DRESS_B1_names','DRESS_B1_thermometer','DRESS_F2_child_drawing','DRESS_F1_soot_patch'}): visible=False
   if night and ob.type=='LIGHT': visible=True
   ob.hide_render=not visible

def render(name,levels,z,cut=False,exterior=False,scale=29):
 vis(levels,cut,exterior); camera(z,scale); sc.render.filepath=os.path.join(ROOT,name); bpy.ops.render.render(write_still=True)
render('preview_1F_cut.png',['F1'],0,True); render('preview_1F_full.png',['F1'],0); render('preview_B1_cut.png',['B1'],-3,True); render('preview_2F_cut.png',['F2'],3,True)
for key,delta in [('B1',-4),('DRESS_B1',-4),('F2',4),('DRESS_F2',4)]:
 for ob in cols[key].objects: ob.location.z+=delta
for ob in cols['REF'].objects:
 if ob.name.startswith('REF_B1_'): ob.location.z-=4
 if ob.name.startswith('REF_F2_'): ob.location.z+=4
render('preview_exploded.png',['B1','F1','F2'],0,True,scale=50)
for key,delta in [('B1',4),('DRESS_B1',4),('F2',-4),('DRESS_F2',-4)]:
 for ob in cols[key].objects: ob.location.z+=delta
for ob in cols['REF'].objects:
 if ob.name.startswith('REF_B1_'): ob.location.z+=4
 if ob.name.startswith('REF_F2_'): ob.location.z-=4
render('preview_exterior.png',['F1','F2','ROOF'],2,False,True,33)
# EEVEE night: no environment illumination, with two warm local sources at the stove and lamp.
world=bpy.data.worlds.new('DRESS_night_world'); world.use_nodes=True; bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND'); bg.inputs['Color'].default_value=(0,0,0,1); bg.inputs['Strength'].default_value=0; oldworld=sc.world; sc.world=world
for name,loc,power,col in []:
 ld=bpy.data.lights.new(name,'POINT'); ld.energy=power; ld.color=col; ld.shadow_soft_size=.4; ob=bpy.data.objects.new(name,ld); cols['REF'].objects.link(ob); ob.location=loc
# Original palette also uses fire_3 for jam; suppress its emission during the night render.
firemat=bpy.data.materials.get('fire_3'); fire_bsdf=next(n for n in firemat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
old_emit=fire_bsdf.inputs['Emission Strength'].default_value; fire_bsdf.inputs['Emission Strength'].default_value=0
fire_strengths=[]
for mat in bpy.data.materials:
 if mat.name.startswith('fire_') and mat.use_nodes:
  node=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
  if node: fire_strengths.append((node,node.inputs['Emission Strength'].default_value)); node.inputs['Emission Strength'].default_value=0
# Give only the burning stove a private emissive copy during the render.
stove=bpy.data.objects['F1_woodstove_on']; oldmats=list(stove.data.materials); flame=firemat.copy(); flame.name='DRESS_night_flame'
for i,m in enumerate(stove.data.materials):
 if m and m.name=='fire_3': stove.data.materials[i]=flame
try:
 sc.render.engine='BLENDER_EEVEE'; sc.eevee.taa_render_samples=64; vis(['F1'],True,False,True); camera(0,29); sc.render.filepath=os.path.join(ROOT,'preview_night_eevee.png'); bpy.ops.render.render(write_still=True); night='ok'
except Exception as exc:
 night='error: '+str(exc)
for node,strength in fire_strengths: node.inputs['Emission Strength'].default_value=strength
fire_bsdf.inputs['Emission Strength'].default_value=old_emit
for i,m in enumerate(oldmats): stove.data.materials[i]=m
sc.world=oldworld; sc.render.engine='BLENDER_WORKBENCH'; vis(['F1'],True); camera(0,29)
for ob in sc.objects:
 if ob.name.endswith('_on'): ob.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'house.blend'))
for ob in D: ob.data.calc_loop_triangles()
newtris=sum(len(ob.data.loop_triangles) for ob in D)
existing_diff=[]
for name,data in original.items():
 ob=bpy.data.objects.get(name)
 if ob is None: existing_diff.append([name,'missing']); continue
 matrix=[round(v,6) for row in ob.matrix_world for v in row]
 digest=hashlib.sha256(b''.join(bytes(str(tuple(v.co)), 'utf8') for v in ob.data.vertices)).hexdigest() if ob.type=='MESH' else None
 if matrix!=data['matrix'] or digest!=data['mesh']: existing_diff.append([name,'changed'])
summary={'source':SOURCE,'new_mesh_objects':len(D),'added_triangles':newtris,'existing_changed':existing_diff,'night_render':night}
open(os.path.join(ROOT,'dress_validation.json'),'w',encoding='utf-8').write(json.dumps(summary,indent=2,ensure_ascii=False)); print('RESULT:',json.dumps(summary,ensure_ascii=False))
