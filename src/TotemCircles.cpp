// TotemCircles
// GPL-3.0-or-later see LICENSE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <MinHook.h>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <atomic>
#include <array>
#include <vector>
#include <algorithm>
#include <d3d9.h>

namespace {

constexpr uintptr_t A_FRAME_UPDATE = 0x00614A90;
constexpr uintptr_t A_LOAD_SCRIPT_FUNCTIONS = 0x00490250;
constexpr uintptr_t A_REGISTER_FUNCTION = 0x00704120;
constexpr uintptr_t A_LUA_TONUMBER = 0x006F3620;
constexpr uintptr_t A_LUA_TOSTRING = 0x006F3690;
constexpr uintptr_t A_LUA_PUSHBOOLEAN = 0x006F39F0;
constexpr uintptr_t A_LOCAL_PLAYER = 0x00B41414;
constexpr uintptr_t A_GET_NAME = 0x00609210;
constexpr uintptr_t A_WORLD_INTERSECT = 0x00672170;
constexpr uintptr_t A_GX_DEVICE = 0x00C0ED38;
constexpr uintptr_t A_GX_D3D_VTABLE = 0x00809EF8;
// ClassicAPI Nearest.cpp uses this engine transform for camera-relative vertices.
constexpr uintptr_t A_WORLD_FRAME = 0x00B4B2BC;
constexpr uintptr_t A_TRANSFORM_VECTOR = 0x007BCB40;
constexpr int O_WORLD_CAMERA = 0x65B8;
constexpr int O_CAMERA_POSITION = 0x08;
constexpr int O_WORLD_VIEW_PROJECTION = 0x3B0;
constexpr int O_D3D_DEVICE = 0x38A8;
constexpr int O_D3D_ALIVE = 0xF2C;
constexpr float PI = 3.14159265358979323846f;
constexpr int MAX_SEGMENTS = 192;
constexpr int O_PLAYER_GUID = 0xC0;
constexpr int O_UNIT_FIELDS = 0x110;
constexpr int O_UNIT_OWNER = 0x20;
constexpr int O_UNIT_CREATED_BY_SPELL = 0x230;
constexpr int O_GET_POSITION_VT = 0x14;

using FrameUpdate = void(__fastcall*)(void*, void*, int);
using LoadScripts = void(__fastcall*)();
using RegisterFunc = void(__fastcall*)(const char*, int(__fastcall*)(void*));
using LuaNumber = double(__fastcall*)(void*, int);
using LuaString = const char*(__fastcall*)(void*, int);
using LuaBoolean = void(__fastcall*)(void*, int);
using Position = float*(__thiscall*)(void*, float*);
using GetName = const char*(__thiscall*)(const void*, const char**);
struct Vec3 { float x,y,z; };
using WorldIntersect = char(__fastcall*)(const Vec3*, const Vec3*, int, Vec3*, float*, uint32_t);
using TransformVector = float*(__fastcall*)(float*, const float*, const float*);

FrameUpdate previousFrame = nullptr;
LoadScripts previousLoad = nullptr;
// Read from the same game/render thread as the hook
struct Slot { char name[128]; float radius = 20.f; bool active = false; };
Slot slots[4];
bool enabled = true;
float ringHeight = 0.35f;
float ringThickness = 0.10f;
int ringSegments = 96;
bool followTerrain = true;
bool wallOcclusion = true;
// Only one object is drawn at a time
struct CachedRing {
  const void* object = nullptr;
  Vec3 center{};
  float radius = -1.f;
  int segments = 0;
  bool terrain = false;
  DWORD sampledAt = 0;
  std::vector<Vec3> centerline;
  std::vector<uint8_t> validFloor; 
  std::vector<uint8_t> visible;
  std::vector<uint8_t> segmentVisible;
  Vec3 visibilityCamera{};
  DWORD visibilityAt = 0;
};
CachedRing cache[4];
// Slots are Fire=1, Earth=2, Water=3, Air=4
// Format ARGB: alpha, red, green, blue
uint32_t colors[4] = {0xB0FF3030, 0xB08B5A2B, 0xB03090FF, 0xB0A0A0A0};
std::atomic<bool> initialized{false};
std::atomic<bool> ready{false};

template<typename T> T at(uintptr_t address) { return *reinterpret_cast<const T*>(address); }
template<typename T> T field(const void* base, size_t offset) {
  return *reinterpret_cast<const T*>(reinterpret_cast<uintptr_t>(base) + offset);
}
template<typename T> T slotFunction(void* obj, int offset) {
  return field<T>(field<const void*>(obj, 0), offset);
}

int __fastcall Script_SetSlot(void* L) {
  const int index = static_cast<int>(reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L, 1));
  const char* name = reinterpret_cast<LuaString>(A_LUA_TOSTRING)(L, 2);
  const double radius = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L, 3);
  bool valid = index >= 1 && index <= 4 && std::isfinite(radius) && radius >= 1.0 && radius <= 50.0;
  if(valid) {
    Slot &s = slots[index-1];
    s.active = name && *name;
    s.radius = static_cast<float>(radius);
    s.name[0] = '\0';
    if(s.active) {
      strncpy_s(s.name, name, _TRUNCATE);
    }
  }
  reinterpret_cast<LuaBoolean>(A_LUA_PUSHBOOLEAN)(L, valid ? 1 : 0);
  return 1;
}
int __fastcall Script_Enable(void* L) {
  enabled = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L, 1) != 0.0;
  return 0;
}
int __fastcall Script_SetColor(void* L) {
  const double rawSlot = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L, 1);
  const char* hex = reinterpret_cast<LuaString>(A_LUA_TOSTRING)(L, 2);
  bool valid = std::isfinite(rawSlot) && rawSlot >= 1 && rawSlot <= 4 &&
               std::floor(rawSlot) == rawSlot && hex != nullptr;
  uint32_t color = 0;
  if(valid) {
    size_t n = std::strlen(hex);
    valid = (n == 6 || n == 8);
    if(valid) {
      for(size_t i=0; i<n; ++i) {
        const char ch = hex[i];
        int nibble = (ch >= '0' && ch <= '9') ? ch-'0' :
                     (ch >= 'a' && ch <= 'f') ? ch-'a'+10 :
                     (ch >= 'A' && ch <= 'F') ? ch-'A'+10 : -1;
        if(nibble < 0) { valid = false; break; }
        color = (color << 4) | static_cast<uint32_t>(nibble);
      }
      if(valid && n == 6) color |= 0xB0000000;
    }
  }
  if(valid) colors[static_cast<int>(rawSlot)-1] = color;
  reinterpret_cast<LuaBoolean>(A_LUA_PUSHBOOLEAN)(L, valid ? 1 : 0);
  return 1;
}
int __fastcall Script_SetMeshConfig(void* L) {
  const double h = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L,1);
  const double t = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L,2);
  const double n = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L,3);
  const double ground = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L,4);
  const bool ok = std::isfinite(h) && std::isfinite(t) && std::isfinite(n) &&
     h >= 0.02 && h <= 5 && t >= 0.01 && t <= 2 && n >= 12 && n <= MAX_SEGMENTS &&
     std::floor(n) == n && std::isfinite(ground);
  if(ok) {
    ringHeight=static_cast<float>(h);
    ringThickness=static_cast<float>(t);
    ringSegments=static_cast<int>(n);
    followTerrain=(ground != 0);
  }
  reinterpret_cast<LuaBoolean>(A_LUA_PUSHBOOLEAN)(L,ok?1:0);
  return 1;
}

int __fastcall Script_SetOcclusion(void* L) {
  const double value = reinterpret_cast<LuaNumber>(A_LUA_TONUMBER)(L, 1);
  wallOcclusion = std::isfinite(value) && value != 0.0;
  return 0;
}

constexpr float STEP_UP = 1.25f;
constexpr float STEP_DOWN = 3.5f;
constexpr float TRACE_EPSILON = 0.08f;
constexpr int MAX_RADIAL_STEPS = 16;

bool NearbyFloor(float x, float y, float expectedZ, float &resultZ) {
  const Vec3 from{x,y,expectedZ+STEP_UP};
  const Vec3 to{x,y,expectedZ-STEP_DOWN};
  Vec3 hit{};
  float fraction=1.f;
  const char found = reinterpret_cast<WorldIntersect>(A_WORLD_INTERSECT)(
    &from,&to,0,&hit,&fraction,0x100111);
  if(!found || !std::isfinite(hit.z) || !std::isfinite(fraction) ||
     fraction<0.f || fraction>1.f) return false;

  if(hit.z > expectedZ+STEP_UP+TRACE_EPSILON ||
     hit.z < expectedZ-STEP_DOWN-TRACE_EPSILON) return false;
  resultZ=hit.z;
  return true;
}

struct FloorSample {
  float z;
  bool valid;
};


FloorSample TraceFloorRadially(const Vec3& center, float angle, float radius) {
  const float cs=std::cos(angle),sn=std::sin(angle);
  const int steps=std::max(1,std::min(64,
    static_cast<int>(std::ceil(radius/1.0f))));
  float floorZ=center.z;
  for(int j=1;j<=steps;++j) {
    const float distance=radius*static_cast<float>(j)/steps;
    const float x=center.x+cs*distance;
    const float y=center.y+sn*distance;
    float z=0.f;
    if(!NearbyFloor(x,y,floorZ,z)) {
      return {floorZ,false};
    }
    floorZ=z;
  }
  return {floorZ,true};
}

void UpdateRing(CachedRing& c, const void* object,const Vec3& pos,float radius) {
  const DWORD now=GetTickCount();
  const float dx=pos.x-c.center.x, dy=pos.y-c.center.y, dz=pos.z-c.center.z;
  if(c.object==object && c.radius==radius && c.segments==ringSegments &&
     c.terrain==followTerrain && c.centerline.size()==static_cast<size_t>(ringSegments+1) &&
     c.validFloor.size()==static_cast<size_t>(ringSegments+1) &&
     dx*dx+dy*dy+dz*dz<0.01f && now-c.sampledAt<5000) return;
  c.object=object; c.center=pos; c.radius=radius;
  c.segments=ringSegments; c.terrain=followTerrain; c.sampledAt=now;
  c.centerline.clear(); c.centerline.reserve(ringSegments+1);
  c.validFloor.clear(); c.validFloor.reserve(ringSegments+1);
  for(int i=0;i<=ringSegments;++i) {
    const float a=2.f*PI*static_cast<float>(i%ringSegments)/ringSegments;
    const float x=pos.x + std::cos(a)*radius;
    const float y=pos.y + std::sin(a)*radius;
    const FloorSample floor = followTerrain
      ? TraceFloorRadially(pos,a,radius)
      : FloorSample{pos.z,true};
    c.centerline.push_back({x,y,floor.z+0.08f});
    c.validFloor.push_back(floor.valid ? 1 : 0);
  }
}
// World-position points are projected using WoW's camera matrix and drawn
// as pretransformed D3D9 triangles. This is the in-game-tested render-5 path.

bool HasCameraLineOfSight(const Vec3& camera, const Vec3& target) {
  const float vx=target.x-camera.x, vy=target.y-camera.y, vz=target.z-camera.z;
  const float distance=std::sqrt(vx*vx+vy*vy+vz*vz);
  if(!std::isfinite(distance) || distance<0.40f) return true;

  const float inset=std::min(0.25f, distance*0.25f);
  const Vec3 end{target.x-vx*(inset/distance),
                 target.y-vy*(inset/distance),
                 target.z-vz*(inset/distance)};
  Vec3 hit{};
  float fraction=1.f;
  const char found=reinterpret_cast<WorldIntersect>(A_WORLD_INTERSECT)(
      &camera,&end,0,&hit,&fraction,0x100111);
  if(!found || !std::isfinite(fraction) || fraction<0.f || fraction>=0.985f) return true;
  const float hitDistance=fraction*(distance-inset);
  return hitDistance<=0.20f;
}

void UpdateVisibility(CachedRing& c, const Vec3& camera, float height) {
  if(!wallOcclusion) return;
  const DWORD now=GetTickCount();
  const float dx=c.visibilityCamera.x-camera.x;
  const float dy=c.visibilityCamera.y-camera.y;
  const float dz=c.visibilityCamera.z-camera.z;
  const size_t n=c.centerline.size();
  if(c.visible.size()==n && c.segmentVisible.size()==n-1 &&
     dx*dx+dy*dy+dz*dz<0.015625f &&
     now-c.visibilityAt<100 && c.visibilityAt>=c.sampledAt) return;

  c.visible.assign(n,1);
  c.segmentVisible.assign(n-1,0);
  c.visibilityCamera=camera;
  c.visibilityAt=now;
  const float lift=std::max(0.18f,height*0.5f);
  for(size_t i=0;i<n;++i) {
    if(!c.validFloor[i]) {c.visible[i]=0;continue;}
    const Vec3& point=c.centerline[i];
    c.visible[i]=HasCameraLineOfSight(camera,{point.x,point.y,point.z+lift})?1:0;
  }

  for(size_t i=1;i<n;++i) {
    if(!c.visible[i-1] || !c.visible[i]) continue;
    const Vec3& a=c.centerline[i-1];
    const Vec3& b=c.centerline[i];
    const Vec3 midpoint{(a.x+b.x)*0.5f,(a.y+b.y)*0.5f,
                        (a.z+b.z)*0.5f+lift};
    c.segmentVisible[i-1]=HasCameraLineOfSight(camera,midpoint)?1:0;
  }
}

void DrawRing(CachedRing& c, float height,float thickness,uint32_t color) {
  if(c.centerline.size()<3) return;
  void* gxDev = at<void*>(A_GX_DEVICE);
  if(!gxDev || field<void*>(gxDev,0) != reinterpret_cast<void*>(A_GX_D3D_VTABLE) ||
     !field<int>(gxDev,O_D3D_ALIVE)) return;
  IDirect3DDevice9* dev=field<IDirect3DDevice9*>(gxDev,O_D3D_DEVICE);
  if(!dev) return;
  IDirect3DStateBlock9* saved=nullptr;
  if(FAILED(dev->CreateStateBlock(D3DSBT_ALL,&saved)) || !saved) return;
  if(FAILED(saved->Capture())) { saved->Release(); return; }
  dev->SetVertexShader(nullptr); dev->SetPixelShader(nullptr);
  dev->SetTexture(0,nullptr);
  dev->SetRenderState(D3DRS_LIGHTING,FALSE);
  dev->SetRenderState(D3DRS_ZENABLE,D3DZB_FALSE);
  dev->SetRenderState(D3DRS_ZWRITEENABLE,FALSE);
  dev->SetRenderState(D3DRS_ALPHABLENDENABLE,TRUE);
  dev->SetRenderState(D3DRS_SRCBLEND,D3DBLEND_SRCALPHA);
  dev->SetRenderState(D3DRS_DESTBLEND,D3DBLEND_INVSRCALPHA);
  dev->SetRenderState(D3DRS_CULLMODE,D3DCULL_NONE);
  dev->SetRenderState(D3DRS_FOGENABLE,FALSE);
  dev->SetRenderState(D3DRS_ALPHATESTENABLE,FALSE);
  dev->SetTextureStageState(0,D3DTSS_COLOROP,D3DTOP_SELECTARG1);
  dev->SetTextureStageState(0,D3DTSS_COLORARG1,D3DTA_DIFFUSE);
  dev->SetTextureStageState(0,D3DTSS_ALPHAOP,D3DTOP_SELECTARG1);
  dev->SetTextureStageState(0,D3DTSS_ALPHAARG1,D3DTA_DIFFUSE);
  dev->SetTextureStageState(1,D3DTSS_COLOROP,D3DTOP_DISABLE);

  struct ScreenVertex { float x,y,z,rhw; uint32_t color; };
  D3DVIEWPORT9 vp{};
  void* world = at<void*>(A_WORLD_FRAME);
  const void* cam = world ? field<const void*>(world,O_WORLD_CAMERA) : nullptr;
  if(cam && SUCCEEDED(dev->GetViewport(&vp)) && vp.Width && vp.Height) {
    const auto* cp=reinterpret_cast<const float*>(reinterpret_cast<uintptr_t>(cam)+O_CAMERA_POSITION);
    const Vec3 camera{cp[0],cp[1],cp[2]};
    UpdateVisibility(c,camera,height);
    const float* matrix=reinterpret_cast<const float*>(reinterpret_cast<uintptr_t>(world)+O_WORLD_VIEW_PROJECTION);
    auto project=[&](const Vec3& pt, ScreenVertex& output)->bool {
      const float rel[4]={pt.x-cp[0],pt.y-cp[1],pt.z-cp[2],0.f};
      float clip[4]={};
      reinterpret_cast<TransformVector>(A_TRANSFORM_VECTOR)(clip,rel,matrix);

      if(!std::isfinite(clip[3]) || clip[3]<=0.30f) return false;
      const float nx=clip[0]/clip[3],ny=clip[1]/clip[3],nz=clip[2]/clip[3];
      if(!std::isfinite(nx)||!std::isfinite(ny)||!std::isfinite(nz)||
         fabsf(nx)>2.f||fabsf(ny)>2.f) return false;
      output={vp.X+(nx+1.f)*0.5f*vp.Width,
              vp.Y+(1.f-ny)*0.5f*vp.Height,0.25f,1.f,color};
      return true;
    };
    std::vector<ScreenVertex> triangles;
    triangles.reserve((c.centerline.size()-1)*12);
    auto tri=[&](const Vec3 &a,const Vec3 &b,const Vec3 &d){
      ScreenVertex aa,bb,dd;
      if(project(a,aa)&&project(b,bb)&&project(d,dd)) {
        triangles.push_back(aa);triangles.push_back(bb);triangles.push_back(dd);
      }
    };
    for(size_t i=1;i<c.centerline.size();++i) {
      if(!c.validFloor[i-1] || !c.validFloor[i]) continue;
      if(wallOcclusion && (c.visible.size()!=c.centerline.size() ||
           c.segmentVisible.size()!=c.centerline.size()-1 ||
           !c.segmentVisible[i-1])) continue;
      const Vec3& a=c.centerline[i-1]; const Vec3& b=c.centerline[i];

      const float horizontal=std::hypot(b.x-a.x,b.y-a.y);
      const float maxStep=std::max(0.75f,1.15f*horizontal);
      if(std::fabs(b.z-a.z)>maxStep) continue;
      const float ax=a.x-c.center.x,ay=a.y-c.center.y;
      const float bx=b.x-c.center.x,by=b.y-c.center.y;
      const float al=std::sqrt(ax*ax+ay*ay),bl=std::sqrt(bx*bx+by*by);
      const float anX=al>0.001f?ax/al:1.f,anY=al>0.001f?ay/al:0.f;
      const float bnX=bl>0.001f?bx/bl:1.f,bnY=bl>0.001f?by/bl:0.f;
      const float half=thickness*0.5f;
      const Vec3 ao{a.x+anX*half,a.y+anY*half,a.z};
      const Vec3 bo{b.x+bnX*half,b.y+bnY*half,b.z};
      const Vec3 at{ao.x,ao.y,ao.z+height},bt{bo.x,bo.y,bo.z+height};
      const Vec3 ai{a.x-anX*half,a.y-anY*half,a.z+height};
      const Vec3 bi{b.x-bnX*half,b.y-bnY*half,b.z+height};
      tri(ao,bo,at);tri(bo,bt,at);
      tri(at,bt,ai);tri(bt,bi,ai);
    }
    if(!triangles.empty()) {
      dev->SetFVF(D3DFVF_XYZRHW|D3DFVF_DIFFUSE);
      dev->DrawPrimitiveUP(D3DPT_TRIANGLELIST,
        static_cast<UINT>(triangles.size()/3),triangles.data(),sizeof(ScreenVertex));
    }
  }
  saved->Apply();saved->Release();
}

int __fastcall Script_IsReady(void* L) {
  reinterpret_cast<LuaBoolean>(A_LUA_PUSHBOOLEAN)(L, ready.load() ? 1 : 0);
  return 1;
}
void __fastcall LoadScriptsHook() {
  previousLoad();
  const auto reg = reinterpret_cast<RegisterFunc>(A_REGISTER_FUNCTION);
  reg("TCR_SetTotem", Script_SetSlot);
  reg("TCR_Enable", Script_Enable);
  reg("TCR_IsReady", Script_IsReady);
  reg("TCR_SetMeshConfig", Script_SetMeshConfig);
  reg("TCR_SetColor", Script_SetColor);
  reg("TCR_SetOcclusion", Script_SetOcclusion);
}

// Draws only actual units owned by the player and with an exact matching active totem name.
void __fastcall FrameHook(void* obj, void* edx, int arg) {
  if(ready.load() && enabled && obj) {
    const void* player = at<const void*>(A_LOCAL_PLAYER);
    if(player) {
      const uint64_t playerGuid = field<uint64_t>(player, O_PLAYER_GUID);
      const void* descriptor = field<const void*>(obj, O_UNIT_FIELDS);
      if(playerGuid && descriptor && field<uint64_t>(descriptor, O_UNIT_OWNER) == playerGuid
         && field<uint32_t>(descriptor, O_UNIT_CREATED_BY_SPELL) != 0) {
        const char* name = reinterpret_cast<GetName>(A_GET_NAME)(obj, nullptr);
        if(name && *name) {
          for(int i=0; i<4; ++i) {
            const Slot &s=slots[i];
            if(!s.active || std::strcmp(name,s.name)!=0) continue;
            auto posFn=slotFunction<Position>(obj,O_GET_POSITION_VT);
            if(!posFn) break;
            float pos[3];
            posFn(obj,pos);
            const float radius=s.radius;
            UpdateRing(cache[i],obj,{pos[0],pos[1],pos[2]},radius);
            DrawRing(cache[i],ringHeight,ringThickness,colors[i]);
            break;
          }
        }
      }
    }
  }
  previousFrame(obj,edx,arg);
}

bool initHooks() {
  if(initialized.exchange(true)) return ready.load();
  if(MH_Initialize()!=MH_OK) return false;
  if(MH_CreateHook(reinterpret_cast<void*>(A_LOAD_SCRIPT_FUNCTIONS),
                   reinterpret_cast<void*>(&LoadScriptsHook),
                   reinterpret_cast<void**>(&previousLoad))!=MH_OK) return false;
  if(MH_CreateHook(reinterpret_cast<void*>(A_FRAME_UPDATE),
                   reinterpret_cast<void*>(&FrameHook),
                   reinterpret_cast<void**>(&previousFrame))!=MH_OK) return false;
  if(MH_QueueEnableHook(reinterpret_cast<void*>(A_LOAD_SCRIPT_FUNCTIONS))!=MH_OK) return false;
  if(MH_QueueEnableHook(reinterpret_cast<void*>(A_FRAME_UPDATE))!=MH_OK) return false;
  if(MH_ApplyQueued()!=MH_OK) return false;
  ready.store(true);
  return true;
}
DWORD WINAPI initWorker(void*) {return initHooks()?0:1;}
}

// namespace
extern "C" DWORD __cdecl Load() { return initHooks()?0:1; }
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if(reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(instance);
    if(!GetModuleHandleW(L"VfPatcher.dll")) {
      HANDLE worker=CreateThread(nullptr,0,initWorker,nullptr,0,nullptr);
      if(worker) CloseHandle(worker);
    }
  }

  return TRUE;
}
