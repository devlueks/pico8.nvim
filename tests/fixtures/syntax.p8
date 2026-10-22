pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- syntax test cart
-- by pico8.nvim
#include lib.lua

function _init()
 player={x=64,y=64,spd=1.5}
 hi=0x1f.8 lo=0b1010.1 h=.5
 local s="\f8red\#1\^o8ffout\^uline\n"
 msg=[[long
string]]
end

function _update60()
 if (btn(⬅️)) player.x-=player.spd
 if (btnp(❎)) sfx(0)
 player.x\=1 n=@0x5f2d
 a=b!=c and d^^e or f>>>1
 --[[ block
 comment ]]
 ?"hi"
end
-->8
-- draw
function _draw()
 cls()
 fillp(▒)
 rrectfill(10,10,30,20,3,8) // c-style comment
 ::top::
end
__gfx__
00000000777777770000000000000000
0880088079999997000000000000000c
__label__
0000ggvv
__map__
0102030405
__sfx__
000100001805018050
__music__
00 01020304
