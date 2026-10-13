#pragma once
#include <algorithm>
#include <cmath>
#include <iterator>

// Platform-independent placement math; the caller supplies physical work-area
// coordinates and the target monitor's DPI. Negative monitor origins are valid.
namespace orb_layout {
struct Rect { int left, top, right, bottom; };
struct Placement { int x, y, size; };
inline int diameter(int requested) { return std::clamp(requested, 32, 96); }
inline int pixels(int dip, unsigned dpi) {
 return std::max(1, int(std::lround(double(dip) * (dpi ? dpi : 96) / 96.0)));
}
inline Placement place(int x, int y, int requested, unsigned dpi, Rect work, bool snap, int dockedEdge=-1) {
 const int width=std::max(1,work.right-work.left),height=std::max(1,work.bottom-work.top);
 const int size=std::min({pixels(diameter(requested),dpi),width,height});
 const int margin=pixels(8,dpi);
 const int marginX=std::min(margin,(width-size)/2),marginY=std::min(margin,(height-size)/2);
 const int left=work.left+marginX,right=work.right-size-marginX;
 const int top=work.top+marginY,bottom=work.bottom-size-marginY;
 x=std::clamp(x,left,right);y=std::clamp(y,top,bottom);
 if(snap){
  const int distances[]{x-left,right-x,y-top,bottom-y};
  const auto edge=dockedEdge>=0&&dockedEdge<=3?dockedEdge:int(std::min_element(std::begin(distances),std::end(distances))-std::begin(distances));
  if(edge==0)x=left;else if(edge==1)x=right;else if(edge==2)y=top;else y=bottom;
 }
 return {x,y,size};
}
inline int edgeOf(Placement p, int requested, unsigned dpi, Rect work) {
 for(int edge=0;edge<4;++edge){
  const auto aligned=place(p.x,p.y,requested,dpi,work,true,edge);
  if(aligned.x==p.x&&aligned.y==p.y)return edge;
 }
 return -1;
}
}
