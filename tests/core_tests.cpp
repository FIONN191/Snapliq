#include "snapliq_core.h"
#include <cassert>
#include <cmath>
#include <iostream>
static void eq(double a,double b){assert(std::abs(a-b)<0.00001);}
int main(){
 auto r=sl_normalize({40,60},{-20,-30});eq(r.x,-20);eq(r.width,60);eq(r.height,90);
 auto p=sl_pixels({-90,20,20,10},{-100,0,100,100},200,200);eq(p.x,20);eq(p.y,140);eq(p.width,40);eq(p.height,20);
 p=sl_pixels({0.2,0.2,1,1},{0,0,100,100},150,150);eq(p.x,0);eq(p.y,148);eq(p.width,2);eq(p.height,2);
 p=sl_pixels({200,0,10,10},{0,0,100,100},100,100);eq(p.width,0);
 r=sl_resize({0,0,100,100},{200,200},0,2);eq(r.width,2);eq(r.height,2);
 r=sl_toolbar({0,0,1920,1080},{0,0,1920,1080},440,44,10);
 assert(r.x>=0&&r.y>=0&&r.x+r.width<=1920&&r.y+r.height<=1080);
 r=sl_toolbar({-10,-20,40,40},{-100,-100,80,80},400,44,10);eq(r.width,80);assert(r.x>=-100);
 for(int i=0;i<8;i++){r=sl_resize({-100,-50,200,100},{500,-500},i,1);assert(r.width>=1&&r.height>=1);}
 for(int x=-200;x<=200;x+=7)for(int y=-150;y<=150;y+=9){
  r=sl_clamp({double(x),double(y),80,40},{-100,-80,200,160});
  assert(r.x>=-100&&r.y>=-80&&r.x+r.width<=100&&r.y+r.height<=80);
 }
 std::cout<<"PASS: normalization, negative origin, fractional pixels, clipping, resize, toolbar and 1,972 boundary cases\n";
}
