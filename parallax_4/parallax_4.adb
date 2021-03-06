--
--  "Parallax Scrolling IV - Overdraw Elimination +"
--
--   Nghia             <nho@optushome.com.au>
--   Randi J. Relander <rjrelander@users.sourceforge.net>
--   David Olofson     <david@olofson.net>
--
--  This software is released under the terms of the GPL.
--
--  Contact authors for permission if you want to use this
--  software, or work derived from it, under other terms.

with Ada.Numerics.Elementary_Functions;
with Ada.Real_Time;
with Ada.Text_IO;

with SDL.Video.Windows.Makers;
with SDL.Video.Palettes;

with SDL.Images.IO;

with SDL.Events.Events;
with SDL.Events.Keyboards;
with SDL.Events.Mice;

package body Parallax_4 is

   --
   --  Foreground map.
   --

   Foreground_Map : aliased Map_Data_Type :=
     -- 123456789ABCDEF
     (
      "3333333333333333",
      "3   2   3      3",
      "3   222 3  222 3",
      "3333 22     22 3",
      "3       222    3",
      "3   222 2 2  333",
      "3   2 2 222    3",
      "3   222      223",
      "3        333   3",
      "3  22 23 323  23",
      "3  22 32 333  23",
      "3            333",
      "3 3  22 33     3",
      "3    222  2  3 3",
      "3  3     3   3 3",
      "3333333333333333"
     );

   Single_Map : aliased Map_Data_Type :=
     --  123456789ABCDEF
     (
      "3333333333333333",
      "3000200030000003",
      "3000222030022203",
      "3333022000002203",
      "3000000022200003",
      "3000222020200333",
      "3000202022200003",
      "3000222000000223",
      "3000000003330003",
      "3002202303230023",
      "3002203203330023",
      "3000000000000333",
      "3030022033000003",
      "3000022200200303",
      "3003000003000303",
      "3333333333333333"
     );

   --
   --  Middle level map; where the planets are.
   --
   Middle_Map : aliased Map_Data_Type :=
     (
      --  123456789ABCDEF
      "   1    1       ",
      "           1   1",
      "  1             ",
      "     1  1    1  ",
      "   1            ",
      "         1      ",
      " 1            1 ",
      "    1   1       ",
      "          1     ",
      "   1            ",
      "        1    1  ",
      " 1          1   ",
      "     1          ",
      "        1       ",
      "  1        1    ",
      "                "
     );

   --
   --  Background map.
   --
   Background_Map : aliased Map_Data_Type :=
     (
      --  123456789ABCDEF
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000",
      "0000000000000000"
     );

   Detect_Runs : constant Boolean := True;

   ------------------------------------------------------------
   --    ...And some code. :-)
   ------------------------------------------------------------

   subtype Coordinate is SDL.Coordinate;

   type Tile_Kind is (Empty, Keyed, Opaque);

   function Tile_Mode (Tile : Tile_Raw_Type) return Tile_Kind;
   --  Checks if tile is opaqe, empty or color keyed

   procedure Draw_Tile (Screen : in out Surface;
                        Tiles  :        Surface;
                        X, Y   :        Coordinate;
                        Tile   :        Tile_Raw_Type;
                        Pixels :    out Integer);

   function Tile_Mode (Tile : Tile_Raw_Type) return Tile_Kind is
   begin
      case Tile is
         when '0' =>        return Opaque;
         when '1' =>        return Keyed;
         when '2' | '3' =>  return Opaque;
         when '4' =>        return Keyed;
         when others =>     return Empty;
      end case;
   end Tile_Mode;

   procedure Draw_Tile (Screen : in out Surface;
                        Tiles  :        Surface;
                        X, Y   :        Coordinate;
                        Tile   :        Tile_Raw_Type;
                        Pixels :    out Integer)
   is
      Source_Rect : Rectangle;
      Dest_Rect   : Rectangle;
      use SDL.C;
   begin
      --  Study the following expression. Typo trap! :-)
      if Tile = ' ' then
         Pixels := 0;
         return;
      end if;

      Source_Rect.X := 0;      -- Only one column, so we never change this.
      Source_Rect.Y := (Tile_Raw_Type'Pos (Tile)
                          - Tile_Raw_Type'Pos ('0')) * TILE_H;
      --  Select tile from image!

      Source_Rect.Width  := TILE_W;
      Source_Rect.Height := TILE_H;

      Dest_Rect.X := int (X);
      Dest_Rect.Y := int (Y);

      Screen.Blit (Source      => Tiles,
                   Source_Area => Source_Rect,
                   Self_Area   => Dest_Rect);

      --  Return area rendered for statistics
      Pixels := Integer (Dest_Rect.Width * Dest_Rect.Height);
   end Draw_Tile;

   procedure Main
   is
      use Ada.Text_IO;
      package Natural_IO is new Integer_IO (Natural);

      use SDL.Video.Windows;

      Window    : SDL.Video.Windows.Window;
      Screen    : Surface;
      Tiles_Bmp : Surface;
      Tiles     : Surface;
      Otiles    : Surface;
      Border    : Rectangle;

      Flags     : constant Window_Flags := (if Full_Screen
                                            then SDL.Video.Windows.Full_Screen
                                            else 0);
      Layers     : Layer_Set (1 .. Layer_Index (Num_Of_Layers));

      Total_Blits      : Natural;
      Total_Recursions : Natural;
      Total_Pixels     : Natural;

      Peak_Blits       : Natural := 0;
      Peak_Recursions  : Natural := 0;
      Peak_Pixels      : Natural := 0;

      Tick1      : Ada.Real_Time.Time;
      Tick2      : Ada.Real_Time.Time;
      Delta_Time : Duration;
      Time       : Long_Float := 0.0;
   begin
      Natural_IO.Default_Width := 8;

      --  Enable audio to prevent crash at program exit
      if not SDL.Initialise (SDL.Enable_Audio) then
         raise Program_Error with "Can not initialise SDLAda";
      end if;

      SDL.Video.Windows.Makers.Create (Window,
                                       Title    => "Parallax 4",
                                       Position => (100, 100),
                                       Size     => (SCREEN_W, SCREEN_H),
                                       Flags    => Flags);
      Screen := Window.Get_Surface;
      Border := Screen.Clip_Rectangle;

      SDL.Images.IO.Create (Tiles_Bmp, "parallax_4/assets/tiles.bmp");
--      tiles = SDL_DisplayFormat(tiles_bmp);
--      otiles = SDL_DisplayFormat(tiles_bmp);
--      SDL_FreeSurface(tiles_bmp);
      Tiles  := Tiles_Bmp;
      Otiles := Tiles_Bmp;

      --  Set colorkey for non-opaque tiles to bright magenta
      Tiles.Set_Colour_Key
        (Now  => SDL.Video.Palettes.Colour'(Red   => 255,
                                            Green => <>,
                                            Blue  => 255,
                                            Alpha => <>));

--      if Alpha /= 0 then
--         Tiles.Set_Alpha (SDL_SRCALPHA|SDL_RLEACCEL, Alpha);
--      end if;

      if Num_Of_Layers > 1 then

         --  Assign maps and tile palettes to parallax layers
         Layer_Init (Layers (Layers'First), Foreground_Map'Access, Tiles, Otiles);
         for I in Layers'First + 1 .. Layers'Last - 1 loop
            if (I mod 2 = 0) and not No_Planets then
               Layer_Init (Layers (I), Middle_Map'Access,
                           Tiles, Otiles);
            else
               Layer_Init (Layers (I), Foreground_Map'Access,
                           Tiles, Otiles);
            end if;
         end loop;
         Layer_Init (Layers (Layers'Last), Background_Map'Access,
                     Tiles, Otiles);

         --  Set up the depth order for the
         --  recursive rendering algorithm.
         for I in Layers'First .. Layers'Last - 1 loop
            Layer_Next (Layers (I), I + 1);
         end loop;
      else
         Layer_Init (Layers (Layers'First), Single_Map'Access, Tiles, Otiles);
      end if;

      if Bounce_Around and Num_Of_Layers > 1 then

         for I in Layers'First .. Layers'Last - 1 loop
            declare
               use Ada.Numerics.Elementary_Functions;
               N : constant Float := Float (Num_Of_Layers);
               A : constant Float := 1.0 + Float (I - 1) * 2.0 * 3.1415 / N;
               V : constant Velocity_Type := 200.0 / Velocity_Type (I);
            begin
               Layer_Vel (Layers (I),
                          V * Velocity_Type (Cos (A)),
                          V * Velocity_Type (Sin (A)));
               if not Wrap then
                  Layer_Limit_Bounce (Layers (I));
               end if;
            end;
         end loop;

      else
         --  Set foreground scrolling speed and enable "bounce mode"
         Layer_Vel (Layers (Layers'First), FOREGROUND_VEL_X, FOREGROUND_VEL_Y);
         if not Wrap then
            Layer_Limit_Bounce (Layers (Layers'First));
         end if;

         --  Link all intermediate levels to the foreground layer
         for I in Layers'First + 1 .. Layers'Last - 1 loop
            Layer_Link (Layers (I), Layers'First, 1.5 / Float (I));
         end loop;
      end if;

      --  Get initial tick for time calculation
      Tick1 := Ada.Real_Time.Clock;

      loop
         declare
            use SDL.Events;
            use SDL.Events.Keyboards;
            Event : SDL.Events.Events.Events;
         begin
            if SDL.Events.Events.Poll (Event) then

               case Event.Common.Event_Type is

                  --  Click to exit
                  when Quit | Mice.Button_Down =>
                     exit;

                  when Keyboards.Key_Down =>
                     exit when
                       Event.Keyboard.Key_Sym.Key_Code
                       = SDL.Events.Keyboards.Code_Escape;

--              if (event.type == SDL_MOUSEBUTTONDOWN)
--                      break;

--              if (event.type & (SDL_KEYUP | SDL_KEYDOWN))
--              {
--                      Uint16  *x, *y;
--                      Uint8   *keys = SDL_GetKeyState(&i);
--                      if(keys[SDLK_ESCAPE])
--                              break;

--                      if(keys[SDLK_LSHIFT] || keys[SDLK_RSHIFT])
--                      {
--                              x = &border.w;
--                              y = &border.h;
--                      }
--                      else
--                      {
--                              x = &border.x;
--                              y = &border.y;
--                      }

--                      if(keys[SDLK_UP])
--                              -- *y;
--                      else if(keys[SDLK_DOWN])
--                              ++ *y;
--                      if(keys[SDLK_LEFT])
--                              -- *x;
--                      else if(keys[SDLK_RIGHT])
--                              ++ *x;
--              }
               when others => null;
               end case;
            end if;
         end; -- Event

         --  Calculate time since last update
         declare
            use Ada.Real_Time;
         begin
            Tick2      := Ada.Real_Time.Clock;
            Delta_Time := To_Duration (Tick2 - Tick1);
            Tick1      := Tick2;
            Time       := Time + Long_Float (Delta_Time);
         end;

         --  Set background velocity
         declare
            use Ada.Numerics.Elementary_Functions;
            T : constant Float := Float (Time);
         begin
            if Num_Of_Layers > 1 then
               Layer_Vel (Layers (Layers'Last),
                          Velocity_Type (Sin (T * 0.00011)) * BACKGROUND_VEL,
                          Velocity_Type (Cos (T * 0.00013)) * BACKGROUND_VEL);
            end if;
         end;

         --  Animate all layers
         for I in Layers'Range loop
            Layer_Animate (Layers, I, Delta_Time);
         end loop;

         --  Reset rendering statistics
         for I in Layers'Range loop
            Layer_Reset_Stats (Layers (I));
         end loop;

         --  Render layers (recursive!)
         Layer_Render (Layers, Layers'First, Screen, Border);

         Total_Blits      := 0;
         Total_Recursions := 0;
         Total_Pixels     := 0;

         if Verbose >= 1 then
            New_Line;
            Put_Line ("layer    blits recursions pixels");
         end if;

         if Verbose = 3 then
            for I in Layers'Range loop
               Put (I'Image);
               Natural_IO.Put (Layers (I).Blits);
               Natural_IO.Put (Layers (I).Recursions);
               Natural_IO.Put (Layers (I).Pixels);
               New_Line;
            end loop;
         end if;

         for Layer of Layers loop
            Total_Blits      := Total_Blits      + Layer.Blits;
            Total_Recursions := Total_Recursions + Layer.Recursions;
            Total_Pixels     := Total_Pixels     + Layer.Pixels;
         end loop;

         Peak_Blits      := Natural'Max (Peak_Blits,      Total_Blits);
         Peak_Recursions := Natural'Max (Peak_Recursions, Total_Recursions);
         Peak_Pixels     := Natural'Max (Peak_Pixels,     Total_Pixels);

         if Verbose >= 2 then
            Put ("TOTAL:  ");
            Natural_IO.Put (Total_Blits);
            Natural_IO.Put (Total_Recursions);
            Natural_IO.Put (Total_Pixels);
            New_Line;
         end if;

         if Verbose >= 1 then
            Put ("PEAK:   ");
            Natural_IO.Put (Peak_Blits);
            Natural_IO.Put (Peak_Recursions);
            Natural_IO.Put (Peak_Pixels);
            New_Line;
         end if;

            --  Draw "title" tile in upper left corner
         declare
            Dummy_Pixels : Integer;
         begin
            --  Screen.Set_Clip_Rectangle (Null_Rectangle);
            Draw_Tile (Screen, Tiles, 2, 2, '4', Dummy_Pixels);
         end;

         --  Make changes visible
         Window.Update_Surface;

         --  Let operating system breath
         delay 0.010;
      end loop;

      Put_Line ("Statistics: (All figures per rendered frame.)");
      Put ("        blits      = "); Natural_IO.Put (Peak_Blits); New_Line;
      Put ("        recursions = "); Natural_IO.Put (Peak_Recursions); New_Line;
      Put ("        pixels     = "); Natural_IO.Put (Peak_Pixels); New_Line;

      --  SDL_FreeSurface(tiles);
      --  Tiles.Finalize;
      SDL.Finalise;

   end Main;


   -----------------------------------------------------------
   --      layer_t functions
   -----------------------------------------------------------

   ----------
   -- Init --
   ----------

   procedure Layer_Init (Layer        : out Layer_Type;
                         Map          :     Map_Data_Access;
                         Tiles        :     Surface;
                         Opaque_Tiles :     Surface) is
   begin
      Layer := (Next         => 0,
                Pos_X        => 0.0,
                Pos_Y        => 0.0,
                Vel_X        => 0.0,
                Vel_Y        => 0.0,
                Map          => Map,
                Tiles        => Tiles,
                Opaque_Tiles => Opaque_Tiles,
                Link         => 0,
                Flags        => (others => False),
                Ratio        => 1.0,
                others       => 0);
   end Layer_Init;

   ----------
   -- Next --
   ----------

   procedure Layer_Next (Layer      : in out Layer_Type;
                         Next_Layer :        Layer_Index) is
   begin
      Layer.Next := Next_Layer;
   end Layer_Next;

   ---------
   -- Pos --
   ---------

   procedure Layer_Pos (Layer : in out Layer_Type;
                        X, Y  :        Position_Type) is
   begin
      Layer.Pos_X := X;
      Layer.Pos_Y := Y;
   end Layer_Pos;

   ---------
   -- Vel --
   ---------

   procedure Layer_Vel (Layer : in out Layer_Type;
                        X, Y  :        Velocity_Type) is
   begin
      Layer.Vel_X := X;
      Layer.Vel_Y := Y;
   end Layer_Vel;

   procedure X_Do_Limit_Bounce (Layer : in out Layer_Type);
   --  Spec

   procedure X_Do_Limit_Bounce (Layer : in out Layer_Type) is
      Max_X : constant Position_Type := Position_Type (MAP_W * TILE_W - SCREEN_W);
      Max_Y : constant Position_Type := Position_Type (MAP_H * TILE_H - SCREEN_H);
   begin
      if Layer.Pos_X >= Max_X then

         --  v.out = - v.in
         Layer.Vel_X := -Layer.Vel_X;

         --  Mirror over right limit. We need to do this
         --  to be totally accurate, as we're in a time
         --  discreet system! Ain't that obvious...? ;-)

         Layer.Pos_X := Max_X * 2.0 - Layer.Pos_X;

      elsif Layer.Pos_X <= 0.0 then

         --  Basic physics again...
         Layer.Vel_X := -Layer.Vel_X;
         --  Mirror over left limit
         Layer.Pos_X := -Layer.Pos_X;
      end if;

      if Layer.Pos_Y >= Max_Y then
         Layer.Vel_Y := -Layer.Vel_Y;
         Layer.Pos_Y := Max_Y * 2.0 - Layer.Pos_Y;
      elsif Layer.Pos_Y <= 0.0 then
         Layer.Vel_Y := -Layer.Vel_Y;
         Layer.Pos_Y := -Layer.Pos_Y;
      end if;
   end X_Do_Limit_Bounce;

   -------------
   -- Animate --
   -------------

   procedure Layer_Animate (Set     : in out Layer_Set;
                            Index   :        Layer_Index;
                            Delta_T :        Duration)
   is
      function "*" (Left : Duration; Right : Velocity_Type) return Position_Type;
      function "*" (Left : Duration; Right : Velocity_Type) return Position_Type is
      begin
         return Position_Type (Left) * Position_Type (Right);
      end "*";

      Layer : Layer_Type renames Set (Index);
   begin
      if Layer.Flags.Linked then
         Layer.Pos_X := Set (Layer.Link).Pos_X * Position_Type (Layer.Ratio);
         Layer.Pos_Y := Set (Layer.Link).Pos_Y * Position_Type (Layer.Ratio);
      else
         Layer.Pos_X := Layer.Pos_X + Delta_T * Layer.Vel_X;
         Layer.Pos_Y := Layer.Pos_Y + Delta_T * Layer.Vel_Y;
         if Layer.Flags.Limit_Bounce then
            X_Do_Limit_Bounce (Layer);
         end if;
      end if;
   end Layer_Animate;


   procedure Layer_Limit_Bounce (Layer : in out Layer_Type) is
   begin
      Layer.Flags.Limit_Bounce := True;
   end Layer_Limit_Bounce;

   ----------
   -- Link --
   ----------

   procedure Layer_Link (Layer    : in out Layer_Type;
                         To_Layer :        Layer_Index;
                         Ratio    :        Float) is
   begin
      Layer.Flags.Linked := True;
      Layer.Link  := To_Layer;
      Layer.Ratio := Ratio;
   end Layer_Link;

   ------------
   -- Render --
   ------------

   --  This version is slightly improved over the
   --  one in "Parallax 3"; it combines horizontal
   --  runs of transparent and partially transparent
   --  tiles before recursing down.

   procedure Layer_Render (Set    : in out Layer_Set;
                           Index  :        Layer_Index;
                           Screen : in out Surface;
                           Rect   :        Rectangle)
   is
      use SDL.Video.Rectangles, SDL.C;
      Layer      : Layer_Type renames Set (Index);
      Pos        : Rectangle;
      Local_Clip : Rectangle;
   begin

      if Rect = Null_Rectangle then
         Screen.Set_Clip_Rectangle (Null_Rectangle);
         Local_Clip := Screen.Clip_Rectangle;
      else
         --  Set up clipping
         --  (Note that we must first clip "rect" to the
         --  current cliprect of the screen - or we'll screw
         --  clipping up as soon as we have more than two
         --  layers!)

         declare
            Clip_Width, Clip_Height : Coordinate;
         begin
            Pos        := Screen.Clip_Rectangle;
            Local_Clip := Rect;

            --  Convert to (x2,y2)
            Pos.Width  := Pos.Width  + Pos.X;
            Pos.Height := Pos.Height + Pos.Y;
            Clip_Width  := Coordinate'Min (Local_Clip.Width  + Local_Clip.X,
                                           Pos.Width);
            Clip_Height := Coordinate'Min (Local_Clip.Height + Local_Clip.Y,
                                           Pos.Height);

            Local_Clip.X      := Coordinate'Max (Local_Clip.X, Pos.X);
            Local_Clip.Y      := Coordinate'Max (Local_Clip.Y, Pos.Y);

            --  Convert result back to w, h
            Clip_Width  := Clip_Width  - Local_Clip.X;
            Clip_Height := Clip_Height - Local_Clip.Y;

            --  Check if we actually have an area left!
            if Clip_Width <= 0 or Clip_Height <= 0 then
               return;
            end if;

            Local_Clip.Width  := C.int (Clip_Width);
            Local_Clip.Height := C.int (Clip_Height);

            Screen.Set_Clip_Rectangle (Local_Clip);
         end;
      end if;

      declare
         --  Position of clip rect in map space
         Map_Pos_X : constant Coordinate
           := Coordinate (Layer.Pos_X) + Screen.Clip_Rectangle.X;
         Map_Pos_Y : constant Coordinate
           := Coordinate (Layer.Pos_Y) + Screen.Clip_Rectangle.Y;

         --  Fine position - pixel offset; up to (1 tile - 1 pixel)
         Fine_X : constant Coordinate := Map_Pos_X mod TILE_W;
         Fine_Y : constant Coordinate := Map_Pos_Y mod TILE_H;

         --  Draw all visible tiles
         Max_X : constant Coordinate
           := Screen.Clip_Rectangle.X + Screen.Clip_Rectangle.Width;
         Max_Y : constant Coordinate
           := Screen.Clip_Rectangle.Y + Screen.Clip_Rectangle.Height;

         M_X      : Map_X_Type;
         M_Y      : Map_Y_Type;
         Mx_Start : Map_X_Type;
      begin

         --  Position on map in tiles
         M_X := Map_X_Type (Map_Pos_X / TILE_W);
         M_Y := Map_Y_Type (Map_Pos_Y / TILE_H);

         Mx_Start := M_X;

         Pos.Height := TILE_H;
         Pos.Y := Screen.Clip_Rectangle.Y - Fine_Y;
         while Pos.Y < Max_Y loop
            M_X   := Mx_Start;
            M_Y   := M_Y mod MAP_H;
            Pos.X := Screen.Clip_Rectangle.X - Fine_X;
            while Pos.X < Max_X loop
               declare
                  Tile  : Tile_Raw_Type;
                  Kind  : Tile_Kind;
                  Run_W : Map_X_Type;
               begin
                  M_X  := M_X mod MAP_W;
                  Tile := Layer.Map (M_Y, M_X);
                  Kind := Tile_Mode (Tile);

                  --  Calculate run length
                  --  (Kind will tell what kind of run it is)
                  Run_W := 1;
                  if Detect_Runs then
                     while Pos.X + Coordinate (Run_W * TILE_W) < Max_X loop
                        declare
                           Sort : constant Tile_Raw_Type :=
                             Layer.Map (M_Y, (M_X + Run_W) mod MAP_W);
                           TT   : Tile_Kind := Tile_Mode (Sort);
                        begin
                           if TT /= Opaque then
                              TT := Empty;
                           end if;

                           if Kind /= TT then
                              exit;
                           end if;
                        end;

                        Run_W := Run_W + 1;
                     end loop;
                  end if;

                  --  Recurse to next layer
                  if Kind /= Opaque and Layer.Next /= 0 then

                     Layer.Recursions := Layer.Recursions + 1;
                     Pos.Width := C.int (Run_W * TILE_W);
                     --  Recursive call !!!
                     Layer_Render (Set, Layer.Next, Screen, Pos);
                     Screen.Set_Clip_Rectangle (Local_Clip);
                  end if;

                  --  Render our tiles
                  Pos.Width := TILE_W;
                  while Run_W /= 0 loop
                     Run_W := Run_W - 1;

                     M_X := M_X mod MAP_W;
                     Tile := Layer.Map (M_Y, M_X);
                     Kind := Tile_Mode (Tile);
                     if Kind /= Empty then
                        declare
                           Tiles  : Surface;
                           Pixels : Integer;
                        begin
                           Tiles := (if Kind = Opaque
                                       then Layer.Opaque_Tiles
                                       else Layer.Tiles);
                           Layer.Blits := Layer.Blits + 1;

                           Draw_Tile (Screen, Tiles,
                                      Pos.X, Pos.Y,
                                      Tile, Pixels);
                           Layer.Pixels := Layer.Pixels + Pixels;
                        end;
                     end if;
                     M_X   := M_X + 1;
                     Pos.X := Pos.X + TILE_W;
                  end loop;
               end;
            end loop;
            M_Y   := M_Y + 1;
            Pos.Y := Pos.Y + TILE_H;
         end loop;
      end;
   end Layer_Render;

   -----------------
   -- Reset_Stats --
   -----------------

   procedure Layer_Reset_Stats (Layer : in out Layer_Type) is
   begin
      Layer.Calls      := 0;
      Layer.Blits      := 0;
      Layer.Recursions := 0;
      Layer.Pixels     := 0;
   end Layer_Reset_Stats;


end Parallax_4;
