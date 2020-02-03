--------------------------------------------------------------
--        Fixed Rate Pig - a fixed logic frame rate demo
--------------------------------------------------------------
--  Copyright (C) 2004 David Olofson <david@olofson.net>
--  Copyright (C) 2020 Jesper Quorning
--
--  This software is released under the terms of the GPL.
--
--  Contact author for permission if you want to use this
--  software, or work derived from it, under other terms.

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Finalization;

with SDL.Video.Rectangles;
with SDL.Video.Surfaces;
with SDL.Video.Windows;

with Dirty;

package Engines is

   ----------------------------------------------------------
   --        Game Engine
   ----------------------------------------------------------
   type Object_States is
     (Waiting,
      Walking,
      Falling,
      Knocked,
      Next_Level,
      Dead);
   --  Moved from pig.adb

   type Power_Ups is
     (Power_Life,
      Power_Bonus_1,
      Power_Bonus_2);
   --  Moved from pig.adb

   type PIG_Object;
   type PIG_Engine;
   type PIG_Object_Access is access all PIG_Object;
   type PIG_Engine_Access is access all PIG_Engine;

   --  Interpolated point
   type PIG_Ipoint is record
      --  From the last logic frame:
      Ox, Oy : Float;         --  Position

      --  From the last/current rendered frame:
      Gimage : Integer;       --  Sprite frame index
      Gx, Gy : Float;         --  Interpolated position
   end record;

   PIG_TIMERS : constant := 3;

   --
   --  Game logic events
   --
   type PIG_Events is
     (
      PIG_PREFRAME,
      --  Occurs once per logic frame, before collision and
      --  off-screen detection, and before timer handlers.

      PIG_TIMER0,
      PIG_TIMER1,
      PIG_TIMER2,
      --  Occurs whenever timer x expires. Timers are one-
      --  shot, but can be reloaded by the handler for
      --  periodic action. Timer events are handled before
      --  before collision and off-screen detection.

      PIG_HIT_TILE,
      --  Occurs when the hot-spot of an object hits a
      --  marked side of a tile, and the corresponding bit
      --  in 'tilemask' is set.

      PIG_HIT_OBJECT,
      --  Occurs when the collision circle of an object
      --  intersects the collision circle of another object,
      --  provided one or more bits in 'hitgroup' of the
      --  other object matches bits in 'hitmask'.

      PIG_OFFSCREEN,
      --  Occurs when an object is off-screen. This takes
      --  in account the hot-spot and bounding rectangle of
      --  the current sprite frame.

      PIG_POSTFRAME
        --  Occurs once per logic frame, after collision
        --  detection, off-screen detection and all other
        --  events.
   );

   type Pig_Sides is record
      Top    : Boolean;
      Bottom : Boolean;
      Left   : Boolean;
      Right  : Boolean;
   end record;
   PIG_Top  : constant Pig_Sides := (Top => True, others => False);
   PIG_None : constant Pig_Sides := (others => False);
   PIG_All  : constant Pig_Sides := (others => True);

   --  Magic values
   PIG_UNCHANGED : constant := -10000000;
   PIG_MIN       : constant := -10000001;
   PIG_CENTER    : constant := -10000002;
   PIG_MAX       : constant := -10000003;

   --  Collision info
   type PIG_Cinfo is record
      Ff    : Float;      --  Fractional frame
      X, Y  : Integer;    --  Exact position
      Sides : Pig_Sides;  --  Side of tile hit
   end record;


   type PIG_Event is record
      Type_C : PIG_Events;

      --  For HIT_TILE, HIT_OBJECT and OFFSCREEN:
      Cinfo : PIG_Cinfo;  --  Detailed collision info

      --  For HIT_OBJECT:
      Obj   : PIG_Object_Access;   --  Which object?
   end record;


   --  Logic object
   type Timer_Array is array (0 .. PIG_TIMERS - 1) of Integer;
   type Handler_Access is access
     procedure (Object : in out PIG_Object;
                Event  : in     PIG_Event);
   type PIG_Object is record
      Owner : PIG_Engine_Access;
--        PIG_object      *next, *prev;

      Id       : Integer;       -- Unique ID. 0 means "free".

      Ibase    : Integer;       -- Sprite frame base index
      Image    : Integer;       -- Sprite frame offset
      X, Y     : Float;         -- Position
      Vx, Vy   : Float;         -- Speed
      Ax, Ay   : Float;         -- Acceleration
      Ip       : PIG_Ipoint;
      Tilemask : Pig_Sides;     -- Sprite/tile mask [PIG_ALL]

      Hitmask  : Integer;       -- Sprite/sprite mask [0]
      Hitgroup : Integer;       -- Sprite/sprite group [0]

      Timer    : Timer_Array;   -- Down-counting timers
      Age      : Integer;       -- Age timer (logic frames)

      Score    : Natural;
      Power    : Integer;
      Target   : Integer;
      State    : Object_States;

      Handler  : Handler_Access;

--        void            *userdata;
   end record;


   --  Level map
   type Tile_Index is range 0 .. 255;
   type Map_Array is array (Natural range <>, Natural range <>) of Tile_Index;
   type Map_Array_Access is access all Map_Array;
   type Hit_Array is array (Natural range <>, Natural range <>) of Pig_Sides;
   type Hit_Array_Access is access all Hit_Array;
   type Hitinfo_Array is array (Tile_Index) of Pig_Sides;

   type PIG_Map is new Ada.Finalization.Controlled with record
      Owner       : PIG_Engine_Access;

      Width       : Integer;                     --  Size of map (tiles)
      Height      : Integer;
      Map         : Map_Array_Access;            --  2D aray of tile indices
      Hit         : Hit_Array_Access;            --  2D aray of collision flags

      Tile_Width  : Integer;                     --  Size of one tile (pixels)
      Tile_Height : Integer;
      Tiles       : SDL.Video.Surfaces.Surface;  --  Tile palette image
      Hitinfo     : Hitinfo_Array;               --  Collision info for the tiles
   end record;
   type PIG_Map_Access is access all PIG_Map;

   --  Sprite frame
   type PIG_Sprite is new Ada.Finalization.Controlled with record
      Width, Height : Integer;     --  Size of sprite (pixels)
      Hotx, Hoty    : Integer;     --  Hot-spot offset (pixels)
      Radius        : Integer;     --  Collision zone radius (pixels)
      Surface       : SDL.Video.Surfaces.Surface; --  Access
   end record;
   type PIG_Sprite_Access is access all PIG_Sprite;

   --  Engine

   package Object_Lists is
      new Ada.Containers.Doubly_Linked_Lists (Element_Type => PIG_Object_Access);

   type Bef_Aft_Access      is access procedure (Pe : in out PIG_Engine);
   type Sprite_Array        is array (Natural range <>) of PIG_Sprite_Access;
   type Sprite_Array_Access is access all Sprite_Array;
   type Dirty_Array         is array (0 .. 1) of Dirty.Table_Access;

   type PIG_Engine is new Ada.Finalization.Controlled with record
      --  Video stuff
      Screen  : SDL.Video.Surfaces.Surface;
      Buffer  : SDL.Video.Surfaces.Surface;  --  For h/w surface displays
      Surface : SDL.Video.Surfaces.Surface;  --  Where to render to
      Pages   : Integer;                     --  # of display VRAM buffers
      View    : SDL.Video.Rectangles.Rectangle; --  Viewport pos & size (pixels)

      Page      : Integer range 0 .. 1;        --  Current page (double buffer)
      Pagedirty : Dirty_Array;                 --  One table for each page
      Workdirty : Dirty.Table_Access;          --  The work dirtytable

      --  "Live" switches
      Interpolation   : Boolean;
      Direct          : Boolean;    --  True: Render directly to screen
      Show_Dirtyrects : Boolean;

      --  Time
      Time  : Long_Float;           --  Logic time (frames)
      Frame : Integer;              --  Logic time; integer part

      --  Background graphics
      Map : PIG_Map_Access;

      --  Sprites and stuff
      Objects : Object_Lists.List;
--          PIG_object      *objects;
--          PIG_object      *object_pool;
      Object_Id_Counter : Integer;
      Nsprites : Integer;
      Sprites  : Sprite_Array_Access;

      --  Logic frame global handlers
      Before_Objects : Bef_Aft_Access;
      After_Objects  : Bef_Aft_Access;

      --  Space for user data
      Userdata : Long_Integer;
   end record;

   --
   --  Engine
   --
   procedure Pig_Open (Engine :    out PIG_Engine_Access;
                       Screen : in     SDL.Video.Surfaces.Surface);
   procedure Pig_Close (Engine : in out PIG_Engine);

   procedure Pig_Viewport (Engine        : in out PIG_Engine;
                           X, Y          : in     Integer;
                           Width, Height : in     Positive);
   --  Set viewport size and position

   procedure Pig_Start (Engine : in out PIG_Engine;
                        Frame  : in     Integer);
   --  Start engine at logic time 'frame'

   procedure Pig_Sprites (Engine        : in out PIG_Engine;
                          Filename      : in     String;
                          Width, Height : in     Integer;
                          Handle        :    out Integer);
   --  Load a sprite palette image. The image is chopped up into
   --  sprites, based on Width and Height, and added as new frames
   --  in the sprite bank. Default values:
   --       Hot-spot:               (Width / 2, Height / 2)
   --       Collision radius:       0.2 * (Width + Height)
   --
   --  Passing 0 for With and/or Height makes pig_sprites() take
   --  the respective value from the image width and/or height.
   --
   --  Returns the index of the first frame loaded.


   procedure Pig_Hotspot (Engine     : in out PIG_Engine;
                          Frame      : in     Integer;
                          Hotx, Hoty : in     Integer);
   --  Set hot-spot of sprite 'frame' to (hotx, hoty)

   procedure Pig_Radius (Engine : in out PIG_Engine;
                         Frame  : in     Integer;
                         Radius : in     Integer);
   --  Set sprite/sprite collision zone radius of 'frame'

   procedure Pig_Animate (Engine : in out PIG_Engine;
                          Frames : in     Float);
   --  Advance logic time by 'frames' logic frames

   procedure Pig_Dirty (Engine : in out PIG_Engine;
                        Area   : in     SDL.Video.Rectangles.Rectangle);
   --  Manually add a dirtyrect for pig_refresh().
   --  Area can be outside the engine viewport.

   procedure Pig_Flip (Engine : in out PIG_Engine;
                       Window : in out SDL.Video.Windows.Window);
   --  Do what's needed to deal with the dirtyrects
   --  and then make the new frame visible.

   procedure Pig_Refresh (Engine : in out PIG_Engine);
   --  Refresh the viewport and any additional dirtyrects.
   --
   --  Note that this does not refresh the entire viewport;
   --  only the areas that have actually changed!

   procedure Pig_Refresh_All (Engine : in out PIG_Engine);
   --  Refresh the whole viewport, including sprites.

   procedure Pig_Draw_Sprite (Engine : in out PIG_Engine;
                              Frame  : in     Integer;
                              X, Y   : in     Integer);
   --  Render a sprite "manually", bypassing the engine

   function Pig_Test_Map (Engine : in PIG_Engine;
                          X, Y   :    Integer) return Pig_Sides;
   --  Get the collision flags for the tile at (x, y),
   --  where the unit of x and y is pixels. The return
   --  is the PIG_sides flags for the tile, or PIG_NONE
   --  if (x, y) is outside the map.

   type PIG_Cinfo_Access is access all PIG_Cinfo;
   function Pig_Test_Map_Vector (Engine         : in out PIG_Engine;
                                 X1, Y1, X2, Y2 : in     Integer;
                                 Mask           : in     Pig_Sides;
                                 Ci             : in     PIG_Cinfo_Access)
                                return Pig_Sides;
   --  Find the first "collidable" tile side when going from
   --  (x1, y1) to (x2, y2). 'mask' determines which tile sides
   --  are considered for collisions.
   --
   --  Returns the side(s) hit, if any tile was hit. If the return
   --  is non-zero, the PIG_cinfo struct at 'ci' contains detailed
   --  information about the collision.


   --
   --  Map
   --
   procedure Pig_Map_Open (Map           :    out PIG_Map_Access;
                           Engine        : in     PIG_Engine_Access;
                           Width, Height : in     Integer);
   procedure Pig_Map_Close (Map : in out PIG_Map);

   procedure Pig_Map_Tiles (Map           : in out PIG_Map;
                            Filename      : in     String;
                            Width, Height : in     Integer;
                            Result        :    out Integer);
   --  Load a tile palette image

   procedure Pig_Map_Collisions (Map   : in out PIG_Map;
                                 First : in     Natural;
                                 Count : in     Natural;
                                 Sides : in     Pig_Sides);
   --  Set tile collision info for 'count' tiles, starting at
   --  'first'. Each tile in the tile palette has a set of
   --  PIG_sides flags that determine which sides the tile are
   --  considered for sprite/map collisions.

   procedure Pig_Map_From_String (Map   : in out PIG_Map;
                                  Trans : in     String;
                                  Data  : in     String);
   --  Load a map from a string (one byte/tile). 'trans'
   --  is a string used for translating 'data' into integer
   --  tile indices. Each position in 'trans' corresponds
   --  to one tile in the tile palette.


   --
   --  Object
   --

   function Pig_Object_Open (Engine : in PIG_Engine_Access;
                             X, Y   : in Integer;
                             Last   : in Boolean) return PIG_Object_Access;
   --  Create an object with the initial position (x, y). If
   --  Last, the object will end up last in the
   --  processing and rendering order, otherwise, first.
   --
   --  Note that relative processing order is very important
   --  to objects that chase each other and stuff like that!
   --  If they're placed in the "wrong" order, the tracking
   --  objects get an extra frame of reaction time, which is
   --  annoying if it's not what you intend.

   procedure Pig_Object_Close (Object : in out PIG_Object);
   --  Delete an object.
   --
   --  Note that objects are never actually deleted. Instead,
   --  they are placed in a free pool, where pig_object_open()
   --  looks for objects to recycle.
   --
   --  In fact, they are not even freed when you ask for it,
   --  but rather kept around until the next rendered frame,
   --  so they can be removed from the screen correctly.

   procedure Pig_Object_Close_All (Engine : in out PIG_Engine);
   --  Close all objects.

   function Pig_Object_Find (Start : in out PIG_Object;
                             Id    :        Integer) return PIG_Object_Access;
   --  Find object by 'id', starting at object 'start'.
   --
   --  The search starts at 'start' and is done in both
   --  directions in parallel, assuming that the matching
   --  object is near 'start' in the list. (It usually is
   --  when dealing with linked objects.)
   --
   --  Returns NULL if the object was not found.

end Engines;
