#include "snapliq_core.h"
#include <algorithm>
#include <cmath>
static double hi(double a,double b){return std::max(a,b);}
static double lo(double a,double b){return std::min(a,b);}
SLRect sl_normalize(SLPoint a,SLPoint b){return {lo(a.x,b.x),lo(a.y,b.y),std::abs(a.x-b.x),std::abs(a.y-b.y)};}
SLRect sl_intersect(SLRect a,SLRect b){
 double x=hi(a.x,b.x),y=hi(a.y,b.y);
 return {x,y,hi(0,lo(a.x+a.width,b.x+b.width)-x),hi(0,lo(a.y+a.height,b.y+b.height)-y)};
}
SLRect sl_clamp(SLRect r,SLRect b){
 r.width=lo(hi(0,r.width),b.width);r.height=lo(hi(0,r.height),b.height);
 r.x=std::clamp(r.x,b.x,b.x+b.width-r.width);r.y=std::clamp(r.y,b.y,b.y+b.height-r.height);return r;
}
int sl_contains(SLRect r,SLPoint p){return p.x>=r.x&&p.y>=r.y&&p.x<=r.x+r.width&&p.y<=r.y+r.height;}
// Handle order: bottom-left, bottom, bottom-right, right, top-right, top, top-left, left.
int sl_handle(SLRect r,SLPoint p,double radius){
 double xs[]={r.x,r.x+r.width/2,r.x+r.width,r.x+r.width,r.x+r.width,r.x+r.width/2,r.x,r.x};
 double ys[]={r.y,r.y,r.y,r.y+r.height/2,r.y+r.height,r.y+r.height,r.y+r.height,r.y+r.height/2};
 for(int i=0;i<8;i++)if(std::hypot(p.x-xs[i],p.y-ys[i])<=radius)return i;
 return -1;
}
SLRect sl_resize(SLRect r,SLPoint d,int h,double m){
 double l=r.x,b=r.y,rr=l+r.width,t=b+r.height;
 if(h==0||h==6||h==7)l=lo(l+d.x,rr-m);
 if(h==2||h==3||h==4)rr=hi(rr+d.x,l+m);
 if(h==0||h==1||h==2)b=lo(b+d.y,t-m);
 if(h==4||h==5||h==6)t=hi(t+d.y,b+m);
 return {l,b,rr-l,t-b};
}
SLRect sl_toolbar(SLRect s,SLRect b,double w,double h,double gap){
 w=lo(w,b.width);h=lo(h,b.height);
 SLRect r{s.x+s.width-w,s.y-h-gap,w,h};
 if(r.y<b.y)r.y=s.y+s.height+gap;
 if(r.y+h>b.y+b.height){r.x=s.x+s.width+gap;r.y=s.y+s.height-h;}
 return sl_clamp(r,b);
}
// Input native desktop coordinates here use bottom-left; output raster coordinates use top-left.
SLRect sl_pixels(SLRect s,SLRect d,double pw,double ph){
 if(d.width<=0||d.height<=0||pw<=0||ph<=0)return {0,0,0,0};
 s=sl_intersect(s,d);if(s.width<=0||s.height<=0)return {0,0,0,0};
 double l=std::floor((s.x-d.x)*pw/d.width),t=std::floor((d.y+d.height-s.y-s.height)*ph/d.height);
 double r=std::ceil((s.x+s.width-d.x)*pw/d.width),b=std::ceil((d.y+d.height-s.y)*ph/d.height);
 l=std::clamp(l,0.0,pw);r=std::clamp(r,0.0,pw);t=std::clamp(t,0.0,ph);b=std::clamp(b,0.0,ph);
 return {l,t,r-l,b-t};
}
