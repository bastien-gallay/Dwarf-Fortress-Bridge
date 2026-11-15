-- Guard tests use synthetic inputs and never mutate the live fortress.
local args,report=...
local passed=0
local function check(v,msg) assert(v,msg) passed=passed+1 end
local function run(name,params,overrides)
  local result
  local env=setmetatable({ARGS=params,emit=function(v) result=v end,
    need_map=function() return true end,
    try=function(fn,d) local ok,v=pcall(fn) if ok then return v end return d end}, {__index=_ENV})
  for k,v in pairs(overrides or {}) do env[k]=v end
  -- shared farm helpers come from the prelude, bound to the same (fake) df/dfhack
  local fh=assert(io.open(args.root..'/lua/prelude.lua')) local src=fh:read('a') fh:close()
  env.plot_conditions,env.crop_mismatch=assert(load(src..'\nreturn plot_conditions, crop_mismatch','prelude','t',env))()
  assert(loadfile(args.root..'/lua/'..name..'.lua','t',env))()
  return result
end
local fake={id=1,x1=1,y1=1,x2=1,y2=1,z=1,plant_id={[0]=-1,[1]=-1,[2]=-1,[3]=-1},
  getBuildStage=function() return 0 end,getMaxBuildStage=function() return 1 end}
local fake_df=setmetatable({building={find=function() return fake end},
  building_farmplotst={is_instance=function() return true end}}, {__index=df})
local bad=run('crop',{action='set',plot_id=1,plant='plump helmet'},{df=fake_df,
  dfhack=setmetatable({buildings={containsTile=function() return true end}}, {__index=dfhack})})
check(bad.error and bad.error:find('not built'),'unbuilt farm must reject crop assignment')
check(fake.plant_id[0]==-1,'rejected unbuilt assignment must leave crops untouched')
fake.getBuildStage=function() return 1 end
local fake_hack=setmetatable({maps={getTileFlags=function() return {light=true,subterranean=false} end},
  buildings={containsTile=function() return true end}}, {__index=dfhack})
bad=run('crop',{action='set',plot_id=1,plant='plump helmet'},{df=fake_df,dfhack=fake_hack})
check(bad.error and bad.error:find('underground crop'),'surface plots must reject underground crops')
check(fake.plant_id[0]==-1,'incompatible crop must not be written')
-- a surface crop must also match the plot's biome: nothing grows on a MOUNTAIN plot
local biome=df.biome_type.MOUNTAIN
fake_hack.maps.getTileBiomeRgn=function() return 0,0 end
fake_hack.maps.getBiomeType=function() return biome end
bad=run('crop',{action='set',plot_id=1,plant='wild carrot'},{df=fake_df,dfhack=fake_hack})
check(bad.error and bad.error:find('MOUNTAIN biome'),'a crop outside the plot biome must be rejected')
check(fake.plant_id[0]==-1,'out-of-biome crop must not be written')
check(bad.plot.warning and bad.plot.warning:find('No crop can grow here'),'a MOUNTAIN plot must say nothing can grow')
biome=df.biome_type.FOREST_TEMPERATE_CONIFER
local ok=run('crop',{action='set',plot_id=1,plant='wild carrot'},{df=fake_df,dfhack=fake_hack})
check(ok.ok and fake.plant_id[0]>=0,'a crop of the plot biome must be accepted')
bad=run('items',{type='NOT_AN_ITEM_TYPE'})
check(bad.error and bad.error:find('Unknown item type'),'invalid item filter must not broaden the search')
local map=setmetatable({maps={getTileFlags=function() return {hidden=false,flow_size=0} end,
  getTileType=function() return df.tiletype.StoneFloor1 end},buildings={findAtTile=function() return nil end}}, {__index=dfhack})
bad=run('room_check',{z=1,rooms={{x=1,y=1,door_y=0}}},{dfhack=map})
check(not bad.ok and #bad.invalid_rooms==1,'open floor must fail bedroom enclosure validation')
report({passed=passed,map_mutated=false})
