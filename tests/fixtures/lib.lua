-- helpers
function lerp(a,b,t)
 return a+(b-a)*t
end

function obj_new(x,y)
 return {x=x,y=y,draw=function(self) spr(1,self.x,self.y) end}
end
