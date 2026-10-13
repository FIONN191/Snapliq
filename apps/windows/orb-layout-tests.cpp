#include "orb-layout.h"
#include <cstdlib>
#include <iostream>

int main(){
 using namespace orb_layout;
 int checks=0;
 auto check=[&](bool value,const char* message){++checks;if(!value){std::cerr<<message<<'\n';std::exit(1);}};
 const Rect primary{0,0,1920,1040};
 auto p=place(410,330,48,96,primary,false);
 check(p.x==410&&p.y==330&&p.size==48,"free position must not redock");
 p=place(10,330,48,96,primary,true);check(p.x==8&&p.y==330,"left snap");
 p=place(1830,330,48,96,primary,true);check(p.x==1864&&p.y==330,"right snap");
 p=place(410,20,48,96,primary,true);check(p.x==410&&p.y==8,"top snap");
 p=place(410,960,48,96,primary,true);check(p.x==410&&p.y==984,"bottom snap");
 p=place(-1800,-600,64,144,{-1920,-1080,0,0},false);
 check(p.x==-1800&&p.y==-600&&p.size==96,"negative monitor origin and mixed DPI");
 p=place(-1800,-600,64,144,primary,false);
 check(p.x==12&&p.y==12&&p.size==96,"removed monitor relocates into remaining work area");
 p=place(100,100,1,96,primary,false);check(p.size==32,"minimum diameter");
 p=place(100,100,999,192,primary,false);check(p.size==192,"maximum diameter and 200 percent DPI");
 p=place(100,100,96,192,{0,0,30,20},false);
 check(p.x>=0&&p.y>=0&&p.x+p.size<=30&&p.y+p.size<=20,"tiny work area must not invert clamp bounds");
 p=place(410,330,48,96,primary,false);check(edgeOf(p,48,96,primary)==-1,"free position must not be marked docked");
 for(int edge=0;edge<4;++edge){
  p=place(410,330,48,96,primary,true,edge);check(edgeOf(p,48,96,primary)==edge,"persist actual docked edge");
  p=place(p.x,p.y,48,96,{0,0,2560,1400},true,edge);check(edgeOf(p,48,96,{0,0,2560,1400})==edge,"retain docked edge on resolution change");
 }
 // The physical work area can stay unchanged when Windows changes scaling.
 // Reusing only the old top-left after 200% -> 100% would leave an interior orb.
 p=place(410,330,48,192,primary,true,1);
 p=place(p.x,p.y,48,96,primary,true,1);
 check(p.x==1864&&p.y==330&&p.size==48,"DPI decrease preserves right-edge anchoring");
 p=place(410,330,48,192,primary,true,3);
 p=place(p.x,p.y,48,96,primary,true,3);
 check(p.x==410&&p.y==984&&p.size==48,"DPI decrease preserves bottom-edge anchoring");
 p=place(410,330,48,192,primary,false);
 p=place(p.x,p.y,48,96,primary,false);
 check(p.x==410&&p.y==330&&p.size==48,"DPI decrease leaves a free or locked position free");
 for(unsigned dpi:{96u,120u,144u,192u,240u})for(int size:{32,48,64,96})
  for(int x:{-3000,-1920,-1,0,1900,3000})for(int y:{-2000,-1080,0,1000,2000})for(bool snap:{false,true}){
   const Rect work{-1920,-1080,0,0};p=place(x,y,size,dpi,work,snap);
   check(p.x>=work.left&&p.y>=work.top&&p.x+p.size<=work.right&&p.y+p.size<=work.bottom,"orb bounds leave monitor");
   const auto again=place(p.x,p.y,size,dpi,work,snap);
   check(p.x==again.x&&p.y==again.y&&p.size==again.size,"placement must be stable");
  }
 std::cout<<checks<<" Windows orb placement checks passed\n";
}
