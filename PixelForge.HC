// PixelForge - native TempleOS/HolyC pixel editor
// Launch with: #include "C:/Home/PixelForge.HC"

#define PF_MAX_DIM 256
#define PF_HISTORY 8
#define PF_TOOL_PENCIL 0
#define PF_TOOL_ERASER 1
#define PF_TOOL_LINE 2
#define PF_TOOL_RECT 3
#define PF_TOOL_CIRCLE 4
#define PF_TOOL_BUCKET 5
#define PF_TOOL_PICKER 6
#define PF_TOOL_SPRAY 7

class PFGHeader {
  U8 magic[4];
  U16 version;
  U16 width;
  U16 height;
  U8 colors[16];
};

CDC *pf_img;
I64 pf_w=64,pf_h=64,pf_tool=PF_TOOL_PENCIL,pf_fg=15,pf_bg=0;
I64 pf_brush=1,pf_spray=4,pf_zoom=4,pf_x=160,pf_y=66;
I64 pf_ax,pf_ay,pf_lastx,pf_lasty,pf_mx,pf_my,pf_sx,pf_sy,pf_mouse_x,pf_mouse_y,pf_drag=FALSE,pf_pan=FALSE,pf_grid=TRUE,pf_fill=FALSE,pf_round=FALSE;
I64 pf_hist_pos=0,pf_hist_count=0;
Bool pf_new_ok=FALSE;
Bool pf_dirty=FALSE;
U8 *pf_filename=NULL;
U8 *pf_history[PF_HISTORY];
U8 *pf_msg="Ready";

U0 PFHistoryPush() {
  I64 i,n=pf_w*pf_h;
  U8 *p;
  if (pf_hist_count && pf_hist_pos<pf_hist_count-1) {
    for (i=pf_hist_pos+1;i<pf_hist_count;i++) Free(pf_history[i]);
    pf_hist_count=pf_hist_pos+1;
  }
  if (pf_hist_count==PF_HISTORY) {
    Free(pf_history[0]);
    for (i=1;i<PF_HISTORY;i++) pf_history[i-1]=pf_history[i];
    pf_hist_count--;
    if (pf_hist_pos) pf_hist_pos--;
  }
  p=MAlloc(n);
  if (!p) { pf_msg="Undo memory full"; return; }
  for (i=0;i<n;i++) p[i]=GrPeek(pf_img,i%pf_w,i/pf_w);
  pf_history[pf_hist_count++]=p;
  pf_hist_pos=pf_hist_count-1;
}

U0 PFRestore(I64 idx) {
  I64 x,y;
  if (idx<0 || idx>=pf_hist_count) return;
  pf_hist_pos=idx;
  for (y=0;y<pf_h;y++) for (x=0;x<pf_w;x++) {
    pf_img->color=pf_history[idx][y*pf_w+x]; GrPlot(pf_img,x,y);
  }
}

U0 PFNew(I64 w,I64 h) {
  I64 i,z;
  CDC *next;
  pf_new_ok=FALSE;
  if (w<1 || h<1 || w>PF_MAX_DIM || h>PF_MAX_DIM) { pf_msg="Size must be 1..256"; return; }
  next=DCNew(w,h);
  if (!next || !next->body) { if(next) DCDel(next); pf_msg="Canvas allocation failed"; return; }
  if (pf_img) DCDel(pf_img);
  for (i=0;i<pf_hist_count;i++) Free(pf_history[i]);
  pf_hist_count=pf_hist_pos=0; pf_w=w; pf_h=h;
  pf_img=next;
  pf_img->color=pf_bg; GrRect(pf_img,0,0,w,h);
  z=Min(4,300/Max(w,h)); if(z<1)z=1;
  pf_zoom=z; pf_x=160; pf_y=66;
  pf_new_ok=TRUE;
  pf_dirty=FALSE; Free(pf_filename); pf_filename=NULL;
  PFHistoryPush(); pf_msg="New canvas";
}

U0 PFNewDialog() {
  I64 w,h;
  w=PopUpGetI64("Canvas width (1..256)",64,1,256);
  h=PopUpGetI64("Canvas height (1..256)",64,1,256);
  if(w>0 && h>0 && pf_dirty && !PopUpNoYes("Discard unsaved changes?")) return;
  PFNew(w,h);
}

U0 PFSave(U8 *name) {
  I64 x,y,k=0,n=pf_w*pf_h;
  U8 *buf,*copy;
  PFGHeader *hd;
  if (!name || !*name) return;
  buf=MAlloc(sizeof(PFGHeader)+n);
  if (!buf) { pf_msg="Save: out of memory"; return; }
  hd=buf; hd->magic[0]='P'; hd->magic[1]='F'; hd->magic[2]='G'; hd->magic[3]='1';
  hd->version=1; hd->width=pf_w; hd->height=pf_h;
  for (x=0;x<16;x++) hd->colors[x]=x;
  for (y=0;y<pf_h;y++) for (x=0;x<pf_w;x++) buf[sizeof(PFGHeader)+k++]=GrPeek(pf_img,x,y);
  if (FileWrite(name,buf,sizeof(PFGHeader)+n)==sizeof(PFGHeader)+n) {
    copy=StrNew(name); Free(pf_filename); pf_filename=copy; pf_dirty=FALSE; pf_msg="Saved .pfg";
  }
  else pf_msg="Save failed";
  Free(buf);
}

U0 PFOpen(U8 *name) {
  I64 size,x,y,k=0,n;
  U8 *buf;
  PFGHeader *hd;
  if (!name || !*name) return;
  buf=FileRead(name,&size);
  if (!buf) { pf_msg="Open failed"; return; }
  if (size<sizeof(PFGHeader)) { Free(buf); pf_msg="Invalid .pfg"; return; }
  hd=buf; n=hd->width*hd->height;
  if (hd->magic[0]!='P' || hd->magic[1]!='F' || hd->magic[2]!='G' || hd->magic[3]!='1' ||
      hd->version!=1 || hd->width<1 || hd->height<1 || hd->width>PF_MAX_DIM ||
      hd->height>PF_MAX_DIM || size!=sizeof(PFGHeader)+n) {
    Free(buf); pf_msg="Invalid or unsupported .pfg"; return;
  }
  for(x=0;x<16;x++) if(hd->colors[x]>15) { Free(buf); pf_msg="Invalid palette table"; return; }
  if(pf_dirty && !PopUpNoYes("Discard unsaved changes?")) { Free(buf); return; }
  PFNew(hd->width,hd->height);
  if (!pf_new_ok) { Free(buf); return; }
  for (y=0;y<pf_h;y++) for (x=0;x<pf_w;x++) {
    pf_img->color=buf[sizeof(PFGHeader)+k++]&15; GrPlot(pf_img,x,y);
  }
  PFHistoryPush(); Free(pf_filename); pf_filename=StrNew(name); pf_dirty=FALSE;
  Free(buf); pf_msg="Opened .pfg";
}

U0 PFOpenDialog() {
  U8 *name=PopUpGetStr("Open .pfg path:");
  if(name) { while(StrLen(name) && (name[StrLen(name)-1]=='\n' || name[StrLen(name)-1]=='\r')) name[StrLen(name)-1]=0; PFOpen(name); Free(name); }
}

U0 PFSaveDialog() {
  U8 *name=PopUpGetStr("Save .pfg path:");
  if(name) { while(StrLen(name) && (name[StrLen(name)-1]=='\n' || name[StrLen(name)-1]=='\r')) name[StrLen(name)-1]=0; PFSave(name); Free(name); }
}

U0 PFSaveCurrent() {
  if(pf_filename) PFSave(pf_filename); else PFSaveDialog();
}

U0 PFExportDialog() {
  I64 size;
  U8 *name=PopUpGetStr("Export TempleOS GR file path:"),*out,*data;
  if(name) {
    while(StrLen(name) && (name[StrLen(name)-1]=='\n' || name[StrLen(name)-1]=='\r')) name[StrLen(name)-1]=0;
    out=ExtDft(name,"GR.Z"); data=DCSave(pf_img,&size,DCSF_COMPRESSED);
    if(out && data && FileWrite(out,data,size)==size) pf_msg="Exported GR.Z";
    else pf_msg="GR export failed";
    Free(data); Free(out); Free(name);
  }
}

U0 PFBrush(I64 x,I64 y,I64 c) {
  I64 a,b,r=(pf_brush-1)/2;
  pf_img->color=c;
  for (b=-r;b<=r;b++) for (a=-r;a<=r;a++)
    if ((!pf_round || a*a+b*b<=r*r) && x+a>=0 && y+b>=0 && x+a<pf_w && y+b<pf_h) GrPlot(pf_img,x+a,y+b);
}

I64 PFFloodFill(I64 sx,I64 sy) {
  I64 head=0,tail=0,n=pf_w*pf_h,idx,x,y,old,count=0;
  I64 *queue=MAlloc(n*sizeof(I64));
  if(!queue) { pf_msg="Fill: not enough memory"; return -1; }
  old=GrPeek(pf_img,sx,sy);
  if(old==pf_fg) { Free(queue); return 0; }
  PFHistoryPush();
  pf_img->color=pf_fg; GrPlot(pf_img,sx,sy); queue[tail++]=sy*pf_w+sx;
  while(head<tail) {
    idx=queue[head++]; x=idx%pf_w; y=idx/pf_w; count++;
    if(x>0 && GrPeek(pf_img,x-1,y)==old) { GrPlot(pf_img,x-1,y); queue[tail++]=idx-1; }
    if(x+1<pf_w && GrPeek(pf_img,x+1,y)==old) { GrPlot(pf_img,x+1,y); queue[tail++]=idx+1; }
    if(y>0 && GrPeek(pf_img,x,y-1)==old) { GrPlot(pf_img,x,y-1); queue[tail++]=idx-pf_w; }
    if(y+1<pf_h && GrPeek(pf_img,x,y+1)==old) { GrPlot(pf_img,x,y+1); queue[tail++]=idx+pf_w; }
  }
  Free(queue); return count;
}

U0 PFStroke(I64 x1,I64 y1,I64 x2,I64 y2,I64 c) {
  pf_img->color=c; pf_img->thick=pf_brush;
  GrLine(pf_img,x1,y1,x2,y2); pf_img->thick=1;
}

U0 PFShape(I64 x1,I64 y1,I64 x2,I64 y2,I64 c) {
  I64 l=Min(x1,x2),t=Min(y1,y2),w=AbsI64(x2-x1)+1,h=AbsI64(y2-y1)+1,r=Min(w,h)/2;
  pf_img->color=c; pf_img->thick=pf_brush;
  if (pf_tool==PF_TOOL_LINE) PFStroke(x1,y1,x2,y2,c);
  else if (pf_tool==PF_TOOL_RECT) {
    if (pf_fill) GrRect(pf_img,l,t,w,h);
    else { GrLine(pf_img,l,t,l+w-1,t); GrLine(pf_img,l,t+h-1,l+w-1,t+h-1);
      GrLine(pf_img,l,t,l,t+h-1); GrLine(pf_img,l+w-1,t,l+w-1,t+h-1); }
  } else if (pf_tool==PF_TOOL_CIRCLE) {
    if (pf_fill) GrFillCircle(pf_img,x1,y1,0,2*r+1);
    else GrCircle(pf_img,x1,y1,r);
  }
  pf_img->thick=1;
}

U0 PFDrawCanvas() {
  I64 x,y,c;
  GrRect(gr.dc,pf_x-2,pf_y-2,pf_w*pf_zoom+4,pf_h*pf_zoom+4);
  if (pf_zoom==1) { gr.dc->color=ROP_EQU; GrBlot(gr.dc,pf_x,pf_y,pf_img); }
  else for (y=0;y<pf_h;y++) for (x=0;x<pf_w;x++) {
    c=GrPeek(pf_img,x,y); gr.dc->color=c;
    GrRect(gr.dc,pf_x+x*pf_zoom,pf_y+y*pf_zoom,pf_zoom,pf_zoom);
  }
  if (pf_grid && pf_zoom>=4) {
    gr.dc->color=8;
    for (x=0;x<=pf_w;x++) GrLine(gr.dc,pf_x+x*pf_zoom,pf_y,pf_x+x*pf_zoom,pf_y+pf_h*pf_zoom-1);
    for (y=0;y<=pf_h;y++) GrLine(gr.dc,pf_x,pf_y+y*pf_zoom,pf_x+pf_w*pf_zoom-1,pf_y+y*pf_zoom);
  }
}

U0 PFButton(I64 x,I64 y,U8 *s) {
  gr.dc->color=7; GrRect(gr.dc,x,y,66,15); gr.dc->color=0; GrPrint(gr.dc,x+3,y+3,"%s",s);
}

U0 PFRender() {
  I64 i,x,y,c;
  gr.dc->color=1; GrRect(gr.dc,0,0,640,480);
  gr.dc->color=15; GrPrint(gr.dc,8,5,"PixelForge%s  |  File  Edit  Image  View  Help",pf_dirty?" *":"");
  PFButton(8,30,"New"); PFButton(78,30,"Open"); PFButton(8,48,"Save"); PFButton(78,48,"Save As");
  PFButton(8,72,"Undo"); PFButton(78,72,"Redo");
  PFButton(8,252,"Clear"); PFButton(8,270,"Export GR"); PFButton(78,288,"Fill");
  PFButton(8,102,"Pencil"); PFButton(8,120,"Eraser"); PFButton(8,138,"Line"); PFButton(8,156,"Rect");
  PFButton(8,174,"Circle"); PFButton(8,192,"Bucket"); PFButton(8,210,"Picker"); PFButton(8,228,"Spray");
  gr.dc->color=15; GrPrint(gr.dc,480,34,"Palette");
  for (i=0;i<16;i++) { x=480+(i%4)*28; y=50+(i/4)*24; gr.dc->color=i; GrRect(gr.dc,x,y,22,18); }
  gr.dc->color=15; GrPrint(gr.dc,480,158,"FG:%d BG:%d",pf_fg,pf_bg);
  PFButton(480,174,"Swap"); PFButton(480,194,"Brush -"); PFButton(550,194,"Brush +");
  PFButton(480,214,pf_round?"Round":"Square"); PFButton(480,234,"Grid"); PFButton(550,234,"Fill");
  PFButton(480,254,"Zoom -"); PFButton(550,254,"Zoom +");
  PFButton(480,274,"Radius -"); PFButton(550,274,"Radius +");
  PFDrawCanvas();
  if(pf_mouse_x>=pf_x && pf_mouse_y>=pf_y && pf_mouse_x<pf_x+pf_w*pf_zoom && pf_mouse_y<pf_y+pf_h*pf_zoom && pf_tool!=PF_TOOL_BUCKET && pf_tool!=PF_TOOL_PICKER) {
    gr.dc->color=15;
    if(pf_round) GrCircle(gr.dc,pf_mouse_x,pf_mouse_y,Max(1,pf_brush*pf_zoom/2));
    else GrBorder(gr.dc,pf_mouse_x-pf_brush*pf_zoom/2,pf_mouse_y-pf_brush*pf_zoom/2,
      pf_mouse_x+pf_brush*pf_zoom/2,pf_mouse_y+pf_brush*pf_zoom/2);
  }
  if(pf_drag && (pf_tool==PF_TOOL_LINE || pf_tool==PF_TOOL_RECT || pf_tool==PF_TOOL_CIRCLE)) {
    gr.dc->color=pf_fg; gr.dc->thick=pf_brush;
    if(pf_tool==PF_TOOL_LINE) GrLine(gr.dc,pf_x+pf_ax*pf_zoom,pf_y+pf_ay*pf_zoom,pf_x+pf_mx*pf_zoom,pf_y+pf_my*pf_zoom);
    else if(pf_tool==PF_TOOL_RECT) GrBorder(gr.dc,pf_x+Min(pf_ax,pf_mx)*pf_zoom,pf_y+Min(pf_ay,pf_my)*pf_zoom,
      pf_x+(Max(pf_ax,pf_mx)+1)*pf_zoom-1,pf_y+(Max(pf_ay,pf_my)+1)*pf_zoom-1);
    else GrCircle(gr.dc,pf_x+pf_ax*pf_zoom,pf_y+pf_ay*pf_zoom,
      Max(1,Min(AbsI64(pf_mx-pf_ax)+1,AbsI64(pf_my-pf_ay)+1)/2*pf_zoom));
    gr.dc->thick=1;
  }
  gr.dc->color=15;
  if(pf_mouse_x>=pf_x && pf_mouse_y>=pf_y && pf_mouse_x<pf_x+pf_w*pf_zoom && pf_mouse_y<pf_y+pf_h*pf_zoom)
    GrPrint(gr.dc,8,420,"X:%d Y:%d | %dx%d | FG:%d BG:%d",(pf_mouse_x-pf_x)/pf_zoom,(pf_mouse_y-pf_y)/pf_zoom,pf_w,pf_h,pf_fg,pf_bg);
  else GrPrint(gr.dc,8,420,"X:- Y:- | %dx%d | FG:%d BG:%d",pf_w,pf_h,pf_fg,pf_bg);
  GrPrint(gr.dc,8,438,"%s | %dx%d B%d S%d Z%d | %s",pf_msg,pf_w,pf_h,pf_brush,pf_spray,pf_zoom,
    pf_tool==0?"Pencil":pf_tool==1?"Eraser":pf_tool==2?"Line":pf_tool==3?"Rectangle":pf_tool==4?"Circle":pf_tool==5?"Bucket":pf_tool==6?"Eyedropper":"Spray");
}

I64 PFMapX(I64 x) { return (x-pf_x)/pf_zoom; }
I64 PFMapY(I64 y) { return (y-pf_y)/pf_zoom; }
Bool PFInside(I64 x,I64 y) { return x>=pf_x && y>=pf_y && x<pf_x+pf_w*pf_zoom && y<pf_y+pf_h*pf_zoom; }

U0 PFClick(I64 x,I64 y,Bool right) {
  I64 i,px,py,tx;
  if (y>=50 && y<146 && x>=480 && x<592) {
    i=((y-50)/24)*4+(x-480)/28;
    if (i>=0 && i<16) { if (right) pf_bg=i; else pf_fg=i; }
    return;
  }
  if(right && !PFInside(x,y)) return;
  if (x<145) {
    if (y>=30 && y<45 && x<74) { PFNewDialog(); return; }
    if (y>=30 && y<45 && x>=78) { PFOpenDialog(); return; }
    if (y>=48 && y<63 && x<74) { PFSaveCurrent(); return; }
    if (y>=48 && y<63 && x>=78) { PFSaveDialog(); return; }
    if (y>=72 && y<87 && x<74) { PFRestore(pf_hist_pos-1); return; }
    if (y>=72 && y<87 && x>=78) { PFRestore(pf_hist_pos+1); return; }
    if (y>=252 && y<267 && x<74) { PFHistoryPush(); pf_img->color=pf_bg; GrRect(pf_img,0,0,pf_w,pf_h); pf_dirty=TRUE; pf_msg="Canvas cleared"; return; }
    if (y>=270 && y<285 && x<74) { PFExportDialog(); return; }
    if (y>=102 && y<246) { pf_tool=(y-102)/18; return; }
  }
  if (x>=480 && y>=174 && y<294) {
    if (y<192) { tx=pf_fg; pf_fg=pf_bg; pf_bg=tx; }
    else if (y<212) pf_brush=Max(1,pf_brush-1);
    else if (y<232) pf_round=!pf_round;
    else if (y<252) { if(x<550) pf_grid=!pf_grid; else pf_fill=!pf_fill; }
    else if (y<272) { pf_zoom+=x<550?-1:1; if(pf_zoom<1)pf_zoom=1; if(pf_zoom>8)pf_zoom=8; }
    else pf_spray=Max(1,Min(16,pf_spray+(x<550?-1:1)));
    return;
  }
  if (x>=78 && x<145 && y>=288 && y<303) {
    PFHistoryPush(); pf_img->color=pf_fg; GrRect(pf_img,0,0,pf_w,pf_h); pf_dirty=TRUE; pf_msg="Canvas filled"; return;
  }
  if (!PFInside(x,y)) return;
  px=PFMapX(x); py=PFMapY(y);
  if (px<0 || py<0 || px>=pf_w || py>=pf_h) return;
  if (right) { pf_pan=TRUE; pf_sx=x; pf_sy=y; return; }
  if (pf_tool==PF_TOOL_PICKER) { pf_fg=GrPeek(pf_img,px,py); return; }
  if (pf_tool==PF_TOOL_BUCKET) {
    I64 changed;
    changed=PFFloodFill(px,py); if(changed>0)pf_dirty=TRUE; return;
  }
  if (pf_tool==PF_TOOL_PENCIL || pf_tool==PF_TOOL_ERASER || pf_tool==PF_TOOL_SPRAY) {
    if (!pf_drag) PFHistoryPush();
    pf_drag=TRUE;
    if (pf_tool==PF_TOOL_SPRAY) { for(i=0;i<pf_spray*3;i++) PFBrush(px+RandI64()%(pf_spray*2+1)-pf_spray,py+RandI64()%(pf_spray*2+1)-pf_spray,pf_fg); }
    else PFBrush(px,py,pf_tool==PF_TOOL_ERASER?pf_bg:pf_fg);
    pf_dirty=TRUE;
    pf_lastx=px; pf_lasty=py;
    return;
  }
  pf_ax=px; pf_ay=py; pf_mx=px; pf_my=py; pf_drag=TRUE;
}

U0 PixelForge() {
  I64 msg,a,b;
  pf_zoom=4; pf_x=160; pf_y=66; PFNew(64,64);
  if(!pf_new_ok) { Print("PixelForge: cannot allocate initial canvas\n"); return; }
  while (TRUE) {
    PFRender();
    msg=GetMsg(&a,&b,1<<MSG_MS_L_DOWN|1<<MSG_MS_R_DOWN|1<<MSG_MS_R_UP|1<<MSG_MS_MOVE|1<<MSG_MS_L_UP|1<<MSG_KEY_DOWN);
    if (msg==MSG_KEY_DOWN) {
      if (a==CH_ESC) { if(!pf_dirty || PopUpNoYes("Discard unsaved changes and exit?")) break; }
      if (a=='z' || a=='Z') { PFRestore(pf_hist_pos-1); pf_dirty=TRUE; }
      if (a=='y' || a=='Y') { PFRestore(pf_hist_pos+1); pf_dirty=TRUE; }
      if (a=='s' || a=='S') PFSaveCurrent();
      if (a=='o' || a=='O') PFOpenDialog();
      if (a=='n' || a=='N') PFNewDialog();
      if (a=='g' || a=='G') pf_grid=!pf_grid;
      if (a=='f' || a=='F') pf_fill=!pf_fill;
      if (a>='1' && a<='8') pf_tool=a-'1';
      if (a=='h') pf_x-=16;
      if (a=='l') pf_x+=16;
      if (a=='k') pf_y-=16;
      if (a=='j') pf_y+=16;
    } else if (msg==MSG_MS_L_DOWN) { pf_drag=FALSE; PFClick(a,b,FALSE); }
    else if (msg==MSG_MS_R_DOWN) PFClick(a,b,TRUE);
    else if (msg==MSG_MS_R_UP) pf_pan=FALSE;
    else if (msg==MSG_MS_MOVE) {
      pf_mouse_x=a; pf_mouse_y=b;
      if(pf_pan) { pf_x+=a-pf_sx; pf_y+=b-pf_sy; pf_sx=a; pf_sy=b; }
      else if(pf_drag && PFInside(a,b)) {
        if(pf_tool==PF_TOOL_PENCIL || pf_tool==PF_TOOL_ERASER) {
          PFStroke(pf_lastx,pf_lasty,PFMapX(a),PFMapY(b),pf_tool==PF_TOOL_ERASER?pf_bg:pf_fg);
          pf_lastx=PFMapX(a); pf_lasty=PFMapY(b);
        } else if(pf_tool==PF_TOOL_SPRAY) {
          I64 i,px=PFMapX(a),py=PFMapY(b);
          for(i=0;i<pf_spray*3;i++) PFBrush(px+RandI64()%(pf_spray*2+1)-pf_spray,py+RandI64()%(pf_spray*2+1)-pf_spray,pf_fg);
        } else { pf_mx=PFMapX(a); pf_my=PFMapY(b); }
      }
    } else if (msg==MSG_MS_L_UP) {
      if (pf_drag && (pf_tool==PF_TOOL_LINE || pf_tool==PF_TOOL_RECT || pf_tool==PF_TOOL_CIRCLE)) {
        if (PFInside(a,b)) { PFHistoryPush(); PFShape(pf_ax,pf_ay,PFMapX(a),PFMapY(b),pf_fg); pf_dirty=TRUE; }
      }
      pf_drag=FALSE;
    }
  }
  if (pf_img) DCDel(pf_img);
  Free(pf_filename);
  while (pf_hist_count) Free(pf_history[--pf_hist_count]);
}

PixelForge;
