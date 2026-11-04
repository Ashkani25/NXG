
(()=>{'use strict';
const $=i=>document.getElementById(i),canvas=$('game'),ctx=canvas.getContext('2d');
// دنیای بازی = مختصات خود تصویر زمین (1086x1448)
const VW=1086,VH=1448,K=1.27,DEPTH=112,PR=43.5,BR=24,STEP=1/240,RC=70,LMAX=210,GD=124;
const FIELDS=[{id:'stadium',name:'Stadium',L:157,R:930,cy:708,h:596,g:128},{id:'desert',name:'Desert',L:163,R:920,cy:693,h:600,g:132},{id:'forest',name:'Forest',L:177,R:915,cy:694,h:595,g:132},{id:'ocean',name:'Ocean',L:162,R:925,cy:696,h:595,g:132},{id:'ice',name:'Ice',L:178,R:910,cy:695,h:590,g:132}];
const SET={lim:5,snd:1,vib:1,fld:0,ball:0};try{Object.assign(SET,JSON.parse(localStorage.getItem('nexora_set'))||{})}catch(e){}
if(!FIELDS[SET.fld])SET.fld=0;if(!(SET.ball>=0&&SET.ball<4))SET.ball=0;
const store=(k,v)=>{try{localStorage.setItem(k,JSON.stringify(v))}catch(e){}};
const MATCH_KEY='nexora_match_v1';
function saveMatch(){try{if(!inMatch||!bodies.length)return;localStorage.setItem(MATCH_KEY,JSON.stringify({score,turn,phase:phase==='move'?'aim':phase,sel,form,field:SET.fld,ballType:SET.ball,lim:SET.lim,bodies:bodies.map(b=>({x:b.x,y:b.y,vx:0,vy:0,r:b.r,m:b.m,team:b.team,spin:b.spin||0,ang:b.ang||0})),savedAt:Date.now()}))}catch(e){}}
function loadMatch(){try{const v=JSON.parse(localStorage.getItem(MATCH_KEY)||'null');if(!v||!Array.isArray(v.bodies)||v.field!==SET.fld||v.ballType!==SET.ball)return false;score=Array.isArray(v.score)?v.score:[0,0];turn=v.turn||0;sel=v.sel||sel;form=v.form||form;SET.lim=v.lim||SET.lim;geo();bodies=v.bodies.map(b=>mk(b.x,b.y,b.team,b.r,b.m));bodies.forEach((b,i)=>{b.spin=v.bodies[i].spin||0;b.ang=v.bodies[i].ang||0});ball=bodies.find(b=>b.team===2)||null;if(!ball)return false;phase='aim';drag=null;pause=0;inMatch=true;$('s1').textContent=score[0];$('s2').textContent=score[1];$('over').classList.remove('show');ui();build();stat();return true}catch(e){return false}}
let F,Fw,Fh,CX,CY,GOALS;
function geo(){const f=FIELDS[SET.fld];F={l:f.L+12,r:f.R-12,t:f.cy-f.h+6,b:f.cy+f.h-6};Fw=F.r-F.l;Fh=F.b-F.t;CX=(F.l+F.r)/2;CY=(F.t+F.b)/2;
 GOALS=[{team:0,y:F.t,x1:CX-f.g,x2:CX+f.g,d:-1},{team:1,y:F.b,x1:CX-f.g,x2:CX+f.g,d:1}]}geo();
const IMG={},SPR={};let s=1,ox=0,oy=0,Sx=1,Rx=0,Ry=0,bodies=[],ball=null,score=[0,0],turn=0,kick=0,phase='aim',drag=null,pause=0,idle=0,trail=[],shake=[0,0],flash=0,last=0,acc=0,bg=null,shots=0,menuOpen=true,inMatch=false,parts=[],tt=0;
const ok=n=>IMG[n]&&IMG[n].naturalWidth>0,mkc=(w,h)=>{const c=document.createElement('canvas');c.width=w;c.height=h;return c};
function load(n,src){if(!IMG[n]){const im=new Image();im.onload=()=>build();im.src=src;IMG[n]=im}return IMG[n]}
const fsrc=i=>'assets/fields/'+FIELDS[i].id+'.jpg';
function rr(c,x,y,w,h,r){c.beginPath();c.moveTo(x+r,y);c.arcTo(x+w,y,x+w,y+h,r);c.arcTo(x+w,y+h,x,y+h,r);c.arcTo(x,y+h,x,y,r);c.arcTo(x,y,x+w,y,r);c.closePath()}
// ---------- تیم‌ها و ترکیب‌ها ----------
const CL=[['real','Real Madrid'],['barca','FC Barcelona'],['mancity','Manchester City'],['manutd','Manchester United'],['liverpool','Liverpool'],['arsenal','Arsenal'],['chelsea','Chelsea'],['bayern','Bayern Munich'],['dortmund','Borussia Dortmund'],['psg','Paris Saint-Germain'],['inter','Inter Milan'],['milan','AC Milan'],['juve','Juventus'],['atletico','Atletico Madrid'],['ajax','Ajax'],['benfica','Benfica'],['porto','FC Porto'],['boca','Boca Juniors'],['river','River Plate'],['flamengo','Flamengo']];
const TEAMS=[{id:'blue',name:'Blue',src:'assets/blue.png',crop:[39,19,1201,1223]},{id:'silver',name:'Silver',src:'assets/silver.png',crop:[39,19,1201,1223]},...CL.map(([id,name])=>({id,name,src:'assets/teams/'+id+'.png',crop:[0,0,256,256]}))];
const T=id=>TEAMS.find(t=>t.id===id);let sel=['blue','silver'];
try{const v=JSON.parse(localStorage.getItem('nexora_teams'));if(Array.isArray(v)&&v.length===2&&T(v[0])&&T(v[1])&&v[0]!==v[1])sel=v}catch(e){}
const nm=t=>T(sel[t]).name;
const FORMS=[['1-2-2','Balanced',[[.09,1],[.22,2],[.36,2]]],['2-2-1','Cautious',[[.10,2],[.24,2],[.37,1]]],['3-1-1','Wall',[[.10,3],[.25,1],[.37,1]]],['2-1-2','Diamond',[[.10,2],[.24,1],[.37,2]]],['1-3-1','Midfield',[[.09,1],[.23,3],[.37,1]]],['1-1-3','Attack',[[.09,1],[.22,1],[.36,3]]]];
let form=[0,0];try{const v=JSON.parse(localStorage.getItem('nexora_form'));if(Array.isArray(v)&&v.length===2&&FORMS[v[0]]&&FORMS[v[1]])form=v}catch(e){}
const slots=fi=>{const o=[];for(const[ny,c]of FORMS[fi][2])for(let i=0;i<c;i++)o.push([c===1?.5:c===2?.27+.46*i:.17+.33*i,ny]);return o};
// ---------- صدا و لرزش ----------
let AC=null,sT=0;
function tone(f,d,ty,v,f2){if(!SET.snd)return;try{AC=AC||new(window.AudioContext||window.webkitAudioContext)();const o=AC.createOscillator(),g=AC.createGain(),t=AC.currentTime;o.type=ty;o.frequency.setValueAtTime(f,t);if(f2)o.frequency.exponentialRampToValueAtTime(f2,t+d);g.gain.setValueAtTime(v,t);g.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(g);g.connect(AC.destination);o.start(t);o.stop(t+d)}catch(e){}}
function sfx(k,v){const n=performance.now();if(k!=='goal'&&n-sT<40)return;sT=n;v=Math.min(1,v||1);
 if(k==='hit')tone(170+v*130,.09,'triangle',.05+.2*v,80);else if(k==='wall')tone(120,.07,'sine',.04+.1*v,70);else if(k==='ui')tone(560,.05,'square',.04,420);
 else if(k==='goal'){[523,659,784,1046].forEach((f,i)=>setTimeout(()=>tone(f,.28,'triangle',.16),i*110))}}
const vib=n=>{if(SET.vib&&navigator.vibrate)try{navigator.vibrate(n)}catch(e){}};
// ---------- تصاویر ----------
function img(id){return load(id,T(id).src)}
function ui(){for(const t of[0,1]){$('i'+t).src=$('mi'+t).src=T(sel[t]).src;$('n'+t).textContent=nm(t)}$('mib').src=$('mball').src='assets/balls/b'+SET.ball+'.png';$('menu').style.setProperty('--bgi','url('+fsrc(SET.fld)+')');stat()}
function shrink(n,c,w,h,flip){if(!ok(n))return null;let src=IMG[n],sx=c[0],sy=c[1],sw=c[2]-c[0],sh=c[3]-c[1];
 while(sw/2>w&&sh/2>h){const t=mkc(Math.round(sw/2),Math.round(sh/2)),x=t.getContext('2d');x.imageSmoothingQuality='high';x.drawImage(src,sx,sy,sw,sh,0,0,t.width,t.height);src=t;sx=sy=0;sw=t.width;sh=t.height}
 const o=mkc(w,h),x=o.getContext('2d');x.imageSmoothingQuality='high';if(flip){x.translate(0,h);x.scale(1,-1)}x.drawImage(src,sx,sy,sw,sh,0,0,w,h);return o}
function build(){const W=innerWidth,H=innerHeight,d=Math.min(devicePixelRatio||1,2.5),f=FIELDS[SET.fld];if(W<50||H<50)return;
 s=Math.min(W/(f.R-f.L+56),(H-230)/(2*f.h+2*GD+48))*1.14;ox=W/2-CX*s;oy=H/2-CY*s;canvas.width=Math.round(W*d);canvas.height=Math.round(H*d);Sx=s*d;Rx=ox*d;Ry=oy*d;
 const px=v=>Math.max(2,Math.round(v*Sx)),fi=load('f'+SET.fld,fsrc(SET.fld));bg=mkc(canvas.width,canvas.height);const b=bg.getContext('2d');b.imageSmoothingQuality='high';b.fillStyle='#03060d';b.fillRect(0,0,bg.width,bg.height);
 if(ok('f'+SET.fld)){const c=Math.max(bg.width/VW,bg.height/VH);try{b.filter='blur(8px)'}catch(e){}b.drawImage(fi,(bg.width-VW*c)/2,(bg.height-VH*c)/2,VW*c,VH*c);try{b.filter='none'}catch(e){}b.fillStyle='rgba(0,0,0,.5)';b.fillRect(0,0,bg.width,bg.height);
  const t=mkc(bg.width,bg.height),x=t.getContext('2d');x.imageSmoothingQuality='high';x.drawImage(fi,Rx-0,Ry-0,VW*Sx,VH*Sx);x.globalCompositeOperation='destination-in';
  const gv=x.createLinearGradient(0,Ry,0,Ry+VH*Sx);gv.addColorStop(0,'rgba(0,0,0,0)');gv.addColorStop(.07,'#000');gv.addColorStop(.93,'#000');gv.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=gv;x.fillRect(0,0,t.width,t.height);
  const gh=x.createLinearGradient(Rx,0,Rx+VW*Sx,0);gh.addColorStop(0,'rgba(0,0,0,0)');gh.addColorStop(.04,'#000');gh.addColorStop(.96,'#000');gh.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=gh;x.fillRect(0,0,t.width,t.height);b.drawImage(t,0,0)}
 for(const q of[0,1]){const t=T(sel[q]);SPR['s'+q]=shrink(t.id,t.crop,px(PR*2),px(PR*2))}SPR.ball=shrink('ball'+SET.ball,[0,0,400,400],px(BR*2),px(BR*2));
 SPR.goal=GOALS.map(g=>shrink('goal',[5,44,840,356],px(g.x2-g.x1+18),px(GD),g.d>0));
 const sd=px(PR*2.6),sc=mkc(sd,sd),x=sc.getContext('2d'),gr=x.createRadialGradient(sd/2,sd/2,sd*.18,sd/2,sd/2,sd/2);gr.addColorStop(0,'rgba(0,0,0,.6)');gr.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=gr;x.fillRect(0,0,sd,sd);SPR.shadow=sc}
function loadAll(){load('goal','assets/goal.png');for(let i=0;i<4;i++)load('ball'+i,'assets/balls/b'+i+'.png');load('f'+SET.fld,fsrc(SET.fld));img(sel[0]);img(sel[1])}
// ---------- منطق بازی ----------
const mk=(x,y,team,r,m)=>({x,y,vx:0,vy:0,r,m,im:1/m,team,spin:0,ang:0});
function reset(k){bodies=[];trail=[];parts=[];
 for(const t of[0,1])for(const[nx,ny]of slots(form[t]))bodies.push(mk(F.l+PR+10+nx*(Fw-2*(PR+10)),t?F.t+ny*Fh:F.b-ny*Fh,t,PR,5));
 ball=mk(CX,CY,2,BR,1.2);bodies.push(ball);turn=k;phase='aim';drag=null;pause=0;idle=0;shots=0;stat()}
function stat(){$('status').textContent=phase==='aim'?nm(turn)+"'s turn":phase==='move'?'In play':phase==='goal'?'Goal!':'Full time';
 $('t0').classList.toggle('on',phase==='aim'&&!turn);$('t1').classList.toggle('on',phase==='aim'&&!!turn)}
function toast(t,big){const e=$('toast');e.className='toast'+(big?' g':'');e.textContent=t;void e.offsetWidth;e.classList.add('show');clearTimeout(tt);tt=setTimeout(()=>e.classList.remove('show'),big?1500:1200)}
function burst(x,y,n,sp,cols,life){for(let i=0;i<n;i++){const a=Math.random()*7,v=sp*(.3+Math.random());parts.push({x,y,vx:Math.cos(a)*v,vy:Math.sin(a)*v,l:life*(.6+Math.random()*.6),m:life,c:cols[i%cols.length],r:2+Math.random()*3.5})}}
function scored(t){if(shots<=1){phase='goal';pause=1.4;kick=turn;toast('No goal');stat();return}
 score[t]++;$('s'+(t+1)).textContent=score[t];saveMatch();pause=1.8;flash=1;shake[t]=.6;phase='goal';kick=1-t;toast('Goal! '+nm(t),1);stat();
 burst(ball.x,GOALS[t].y,110,700,['#ffd23a','#fff','#ff6a1f','#3b9bff','#ff5b5b'],1.3);sfx('goal');vib([60,40,120])}
function walls(b){const bl=b===ball,e=bl?.94:.88,r=b.r,vs=Math.hypot(b.vx,b.vy);
 if(b.x-r<F.l){b.x=F.l+r;if(b.vx<0){if(bl&&vs>200)sfx('wall',vs/1800);b.vx*=-e;b.spin+=b.vy/r*.05}}
 if(b.x+r>F.r){b.x=F.r-r;if(b.vx>0){if(bl&&vs>200)sfx('wall',vs/1800);b.vx*=-e;b.spin-=b.vy/r*.05}}
 for(const g of GOALS){if(g.d<0?b.y-r>=g.y:b.y+r<=g.y)continue;
  if(b.x>g.x1&&b.x<g.x2){const back=g.y+g.d*DEPTH;if(g.d<0?b.y-r<back:b.y+r>back){b.y=back-g.d*r;b.vy=-g.d*Math.abs(b.vy)*.2;b.vx*=.6}
   if(g.d<0?b.y<g.y-r*.6:b.y>g.y+r*.6){if(b.x<g.x1+r){b.x=g.x1+r;b.vx=Math.abs(b.vx)*.3}if(b.x>g.x2-r){b.x=g.x2-r;b.vx=-Math.abs(b.vx)*.3}}
  }else{if(bl&&vs>200)sfx('wall',vs/1800);b.y=g.y-g.d*r;b.vy=-g.d*Math.abs(b.vy)*e;b.spin+=g.d*b.vx/r*.05}}
 for(const[cx,cy,sx,sy]of[[F.l+RC,F.t+RC,1,1],[F.r-RC,F.t+RC,-1,1],[F.l+RC,F.b-RC,1,-1],[F.r-RC,F.b-RC,-1,-1]]){
  if((b.x-cx)*sx<0&&(b.y-cy)*sy<0){const dx=b.x-cx,dy=b.y-cy,d=Math.hypot(dx,dy),lim=RC-r;if(d>lim&&d>0){const nx=dx/d,ny=dy/d,vn=b.vx*nx+b.vy*ny;b.x=cx+nx*lim;b.y=cy+ny*lim;if(vn>0){b.vx-=(1+e)*vn*nx;b.vy-=(1+e)*vn*ny}}}}}
function post(b,px,py){const dx=b.x-px,dy=b.y-py,d=Math.hypot(dx,dy),m=b.r+5;if(d>=m||!d)return;const nx=dx/d,ny=dy/d,vn=b.vx*nx+b.vy*ny;b.x=px+nx*m;b.y=py+ny*m;if(vn<0){b.vx-=1.7*vn*nx;b.vy-=1.7*vn*ny;if(b===ball)tone(900,.1,'sine',.12,600)}}
function hit(a,b){let dx=b.x-a.x,dy=b.y-a.y,d=Math.hypot(dx,dy);const m=a.r+b.r;if(d>=m)return;if(d<1e-4){dx=1;dy=0;d=1}
 const nx=dx/d,ny=dy/d,sm=a.im+b.im,c=Math.max(m-d-.3,0)*.9/sm;a.x-=nx*c*a.im;a.y-=ny*c*a.im;b.x+=nx*c*b.im;b.y+=ny*c*b.im;
 const vn=(b.vx-a.vx)*nx+(b.vy-a.vy)*ny;if(vn>=0)return;
 const isB=a===ball||b===ball,e=vn<-40*K?(isB?.86:.58):0,j=-(1+e)*vn/sm;
 a.vx-=j*nx*a.im;a.vy-=j*ny*a.im;b.vx+=j*nx*b.im;b.vy+=j*ny*b.im;
 if(vn<-120*K){sfx('hit',-vn/1900);if(vn<-420*K){burst(a.x+nx*a.r,a.y+ny*a.r,4,260,['#fff','#9fe0ff'],.28);vib(12)}}
 if(isB)ball.spin+=(ball===b?1:-1)*(-ny*(b.vx-a.vx)+nx*(b.vy-a.vy))/ball.r*.12}
function sim(dt){
 for(const b of bodies){b.x+=b.vx*dt;b.y+=b.vy*dt;const sp=Math.hypot(b.vx,b.vy),bl=b===ball;
  if(sp>0){const ns=sp-((bl?380:900)*K+sp*(bl?.55:.9))*dt;
   if(ns<(bl?8:14)*K){b.vx=b.vy=0}else{const k=Math.min(ns,2300*K)/sp;b.vx*=k;b.vy*=k}}
  b.spin*=1-1.6*dt;b.ang+=b.spin*dt+(b.vx+b.vy*.6)*dt/b.r*.3;walls(b)}
 for(let i=0;i<2;i++)for(let a=0;a<bodies.length;a++)for(let c=a+1;c<bodies.length;c++)hit(bodies[a],bodies[c]);
 for(const g of GOALS)for(const b of bodies){post(b,g.x1,g.y);post(b,g.x2,g.y)}for(const b of bodies)walls(b);
 if(phase==='move')for(const g of GOALS)if(ball.x>g.x1&&ball.x<g.x2&&(g.d<0?ball.y<g.y-ball.r*.8:ball.y>g.y+ball.r*.8))scored(g.team)}
// ---------- رسم ----------
const RING=['#3b9bff','#ff5b5b'];
function sprite(b){const sp=b===ball?SPR.ball:b.team?SPR.s1:SPR.s0;
 if(!sp){ctx.fillStyle=b===ball?'#fff':RING[b.team];ctx.beginPath();ctx.arc(b.x,b.y,b.r,0,7);ctx.fill();return}
 ctx.save();
 let drawY=b.y;
 if(b===ball){
  const now=performance.now(),bob=Math.sin(now/240)*2.2;
  drawY+=bob;
  const halo=ctx.createRadialGradient(b.x,drawY, b.r*.25,b.x,drawY,b.r*2.15);
  halo.addColorStop(0,'rgba(80,155,255,.28)');halo.addColorStop(.38,'rgba(100,130,160,.18)');halo.addColorStop(.72,'rgba(95,105,120,.09)');halo.addColorStop(1,'rgba(40,50,65,0)');
  ctx.fillStyle=halo;ctx.beginPath();ctx.arc(b.x,drawY,b.r*2.15,0,Math.PI*2);ctx.fill();
  ctx.globalAlpha=.75;ctx.fillStyle='rgba(20,30,45,.28)';ctx.beginPath();ctx.ellipse(b.x, b.y+b.r*.82,b.r*.78,b.r*.28,0,0,Math.PI*2);ctx.fill();ctx.globalAlpha=1;
 }
 ctx.translate(b.x,drawY);if(b===ball)ctx.rotate(b.ang);ctx.drawImage(sp,-b.r,-b.r,b.r*2,b.r*2);ctx.restore()}
function aim(){if(!drag)return;const{b,s:p0,c}=drag,dx=p0.x-c.x,dy=p0.y-c.y,l=Math.hypot(dx,dy);if(l<18)return;const p=Math.min(l,LMAX)/LMAX,ux=dx/l,uy=dy/l;let t=1200;
 for(const o of bodies){if(o===b)continue;const R=b.r+o.r,qx=o.x-b.x,qy=o.y-b.y,u=qx*ux+qy*uy;if(u<=0)continue;const D=u*u-(qx*qx+qy*qy-R*R);if(D>=0){const h=u-Math.sqrt(D);if(h>0&&h<t)t=h}}
 if(ux<0)t=Math.min(t,(F.l+b.r-b.x)/ux);if(ux>0)t=Math.min(t,(F.r-b.r-b.x)/ux);if(uy<0)t=Math.min(t,(F.t+b.r-b.y)/uy);if(uy>0)t=Math.min(t,(F.b-b.r-b.y)/uy);t=Math.max(t,0);
 const col='hsl('+(120-120*p)+',95%,58%)';ctx.save();ctx.lineCap='round';
 ctx.strokeStyle='rgba(255,255,255,.3)';ctx.lineWidth=4;ctx.beginPath();ctx.moveTo(p0.x,p0.y);ctx.lineTo(c.x,c.y);ctx.stroke();
 ctx.setLineDash([10,14]);ctx.strokeStyle='rgba(255,255,255,.85)';ctx.lineWidth=5;ctx.beginPath();ctx.moveTo(b.x+ux*b.r,b.y+uy*b.r);ctx.lineTo(b.x+ux*t,b.y+uy*t);ctx.stroke();
 ctx.setLineDash([]);ctx.beginPath();ctx.arc(b.x+ux*t,b.y+uy*t,b.r,0,7);ctx.stroke();
 ctx.strokeStyle=col;ctx.lineWidth=8;ctx.beginPath();ctx.arc(b.x,b.y,b.r+12,-1.5708,-1.5708+p*6.2832);ctx.stroke();
 const L=54+p*110,hx=b.x+ux*(b.r+L),hy=b.y+uy*(b.r+L);ctx.strokeStyle=ctx.fillStyle=col;ctx.lineWidth=8+p*6;
 ctx.beginPath();ctx.moveTo(b.x+ux*(b.r+16),b.y+uy*(b.r+16));ctx.lineTo(hx,hy);ctx.stroke();
 ctx.beginPath();ctx.moveTo(hx+ux*30,hy+uy*30);ctx.lineTo(hx-uy*19,hy+ux*19);ctx.lineTo(hx+uy*19,hy-ux*19);ctx.closePath();ctx.fill();ctx.restore()}
function draw(){const W=canvas.width,H=canvas.height,now=performance.now();ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,W,H);
 if(bg)ctx.drawImage(bg,0,0);else{ctx.fillStyle='#103a18';ctx.fillRect(0,0,W,H)}
 ctx.setTransform(Sx,0,0,Sx,Rx,Ry);
 if(trail.length>1){ctx.save();ctx.globalCompositeOperation='lighter';ctx.lineCap=ctx.lineJoin='round';
  for(const[w,al,c]of[[2.1,.16,'#3aa8ff'],[1.1,.4,'#9fe0ff'],[.4,.95,'#ffffff']])for(let i=1;i<trail.length;i++){const p=trail[i-1],q=trail[i];ctx.globalAlpha=al*q.a;ctx.strokeStyle=c;ctx.lineWidth=BR*w*q.a+1;ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(q.x,q.y);ctx.stroke()}ctx.restore()}
 if(phase==='aim'&&!menuOpen){const k=.5+.5*Math.sin(now/260),c=turn?'255,110,110':'80,170,255';
  for(const b of bodies)if(b.team===turn){ctx.lineWidth=13;ctx.strokeStyle='rgba('+c+','+(.12+.14*k)+')';ctx.beginPath();ctx.arc(b.x,b.y,b.r+11,0,7);ctx.stroke();ctx.lineWidth=4;ctx.strokeStyle='rgba('+c+','+(.5+.5*k)+')';ctx.beginPath();ctx.arc(b.x,b.y,b.r+11,0,7);ctx.stroke()}}
 if(SPR.shadow)for(const b of bodies){const w=b.r*2.6;ctx.drawImage(SPR.shadow,b.x-w/2+5,b.y-w/2+11,w,w)}
 for(const b of bodies)if(b!==ball)sprite(b);if(ball)sprite(ball);
 GOALS.forEach((g,i)=>{const sp=SPR.goal&&SPR.goal[i];if(!sp)return;const gw=g.x2-g.x1+18;const gx=g.x1-9+Math.sin(now/25)*8*shake[g.team];const gy=g.d<0?g.y-GD-2:g.y+2;ctx.drawImage(sp,gx,gy,gw,GD)});
 if(parts.length){ctx.save();ctx.globalCompositeOperation='lighter';for(const p of parts){ctx.globalAlpha=Math.max(0,p.l/p.m);ctx.fillStyle=p.c;ctx.beginPath();ctx.arc(p.x,p.y,p.r,0,7);ctx.fill()}ctx.restore()}
 aim();
 if(flash>0){ctx.setTransform(1,0,0,1,0,0);ctx.fillStyle='rgba(255,230,140,'+flash*.35+')';ctx.fillRect(0,0,W,H)}}
// ---------- حلقهٔ اصلی ----------
function end(){phase='over';stat();$('ovt').textContent=nm(score[0]>score[1]?0:1)+' wins! 🏆';$('over').classList.add('show')}
function restart(){score=[0,0];$('s1').textContent=$('s2').textContent='0';$('over').classList.remove('show');reset(0);saveMatch()}
function loop(t){const dt=Math.min((t-last)/1000||.016,.05);last=t;
 if(!menuOpen){acc+=dt;let n=0;
  if(phase!=='over'){while(acc>=STEP&&n++<14){sim(STEP);acc-=STEP}if(n>14)acc=0}
  if(phase==='move'){idle=bodies.some(b=>b.vx||b.vy)?0:idle+dt;if(idle>.25){turn=1-turn;phase='aim';stat();saveMatch()}}
  else if(phase==='goal'){pause-=dt;if(pause<=0){if(score[0]>=SET.lim||score[1]>=SET.lim)end();else reset(kick)}}
  if(ball&&Math.hypot(ball.vx,ball.vy)>350*K)trail.push({x:ball.x,y:ball.y,a:1})}
 flash=Math.max(0,flash-dt*2);shake[0]=Math.max(0,shake[0]-dt);shake[1]=Math.max(0,shake[1]-dt);
 for(const p of trail)p.a-=dt*3;trail=trail.filter(p=>p.a>0);
 for(const p of parts){p.x+=p.vx*dt;p.y+=p.vy*dt;p.vx*=.97;p.vy*=.97;p.l-=dt}parts=parts.filter(p=>p.l>0);
 draw();requestAnimationFrame(loop)}
// ---------- ورودی لمسی ----------
const pt=e=>({x:(e.clientX-ox)/s,y:(e.clientY-oy)/s});
const inUI=e=>e.target.closest&&e.target.closest('button,.scr,.over');
document.addEventListener('pointerdown',e=>{if(AC&&AC.state==='suspended')AC.resume();if(menuOpen||phase!=='aim'||inUI(e))return;const p=pt(e);let f=null,bd=1e9;
 for(const b of bodies)if(b.team===turn){const d=Math.hypot(p.x-b.x,p.y-b.y);if(d<b.r+30&&d<bd){f=b;bd=d}}
 if(!f)return;drag={b:f,s:p,c:p};e.preventDefault()});
document.addEventListener('pointermove',e=>{if(drag){drag.c=pt(e);e.preventDefault()}});
document.addEventListener('pointerup',e=>{if(!drag)return;const{b,s:p0,c}=drag,dx=p0.x-c.x,dy=p0.y-c.y,l=Math.hypot(dx,dy);drag=null;
 if(l>18){const v=(150+1350*Math.min(l,LMAX)/LMAX)*K;b.vx=dx/l*v;b.vy=dy/l*v;phase='move';idle=0;shots++;stat();tone(260,.08,'sawtooth',.08,120)}e.preventDefault()});
document.addEventListener('pointercancel',()=>{drag=null});
// ---------- منو و صفحه‌ها ----------
function show(id){for(const e of document.querySelectorAll('.scr'))e.classList.toggle('show',e.id===id);menuOpen=!!id;
 if(id==='menu'){const sm=(()=>{try{return !!localStorage.getItem(MATCH_KEY)}catch(e){return false}})();$('mcont').style.display=(inMatch||sm)&&phase!=='over'?'':'none';$('mplay').firstChild.textContent=inMatch?'▶ New match':'▶ Play'}sfx('ui')}
let tab=0,ftab=0;
function renderShop(){$('tab0').classList.toggle('on',tab===0);$('tab1').classList.toggle('on',tab===1);$('tab0').textContent='Team 1: '+nm(0);$('tab1').textContent='Team 2: '+nm(1);const g=$('grid');g.innerHTML='';
 for(const t of TEAMS){const c=document.createElement('button');c.className='card'+(sel[tab]===t.id?' sel':'')+(sel[1-tab]===t.id?' tk':'');c.innerHTML='<img src="'+t.src+'" alt=""><span>'+t.name+'</span>';
  c.onclick=()=>{if(sel[1-tab]===t.id)return;sel[tab]=t.id;img(t.id);store('nexora_teams',sel);ui();renderShop();build();sfx('ui')};g.appendChild(c)}}
function renderForms(){$('ftab0').classList.toggle('on',ftab===0);$('ftab1').classList.toggle('on',ftab===1);$('ftab0').textContent='Team 1: '+nm(0);$('ftab1').textContent='Team 2: '+nm(1);const g=$('fgrid');g.innerHTML='';
 FORMS.forEach((f,i)=>{const c=document.createElement('button'),cv=document.createElement('canvas');cv.width=120;cv.height=100;c.className='card'+(form[ftab]===i?' sel':'');
  const x=cv.getContext('2d');x.fillStyle='#237a2f';rr(x,2,2,116,96,10);x.fill();x.strokeStyle='rgba(255,255,255,.75)';x.lineWidth=2;rr(x,2,2,116,96,10);x.stroke();
  x.beginPath();x.moveTo(2,2);x.lineTo(118,2);x.stroke();x.beginPath();x.arc(60,2,16,0,3.1416);x.stroke();x.strokeRect(34,66,52,32);
  for(const[nx,ny]of slots(i)){x.fillStyle=RING[ftab];x.beginPath();x.arc(14+nx*92,92-ny/.5*80,8,0,7);x.fill();x.strokeStyle='#fff';x.lineWidth=2;x.stroke()}
  c.appendChild(cv);c.insertAdjacentHTML('beforeend','<b>'+f[0]+'</b><span>'+f[1]+'</span>');
  c.onclick=()=>{form[ftab]=i;store('nexora_form',form);renderForms();sfx('ui')};g.appendChild(c)})}
function applyField(){geo();SPR.goal=null;load('f'+SET.fld,fsrc(SET.fld));ui();build();reset(turn)}
function renderFields(){const g=$('fldgrid'),bl=$('ballgrid');g.innerHTML=bl.innerHTML='';
 FIELDS.forEach((f,i)=>{const c=document.createElement('button');c.className='card'+(SET.fld===i?' sel':'');c.innerHTML='<img class="f" src="'+fsrc(i)+'" alt=""><b>'+f.name+'</b>';
  c.onclick=()=>{if(SET.fld===i)return;SET.fld=i;store('nexora_set',SET);if(inMatch){score=[0,0];$('s1').textContent=$('s2').textContent='0';$('over').classList.remove('show')}applyField();renderFields();sfx('ui')};g.appendChild(c)});
 for(let i=0;i<4;i++){const c=document.createElement('button');c.className='card'+(SET.ball===i?' sel':'');c.innerHTML='<img src="assets/balls/b'+i+'.png" alt="">';
  c.onclick=()=>{SET.ball=i;store('nexora_set',SET);ui();build();renderFields();sfx('ui')};bl.appendChild(c)}}
function renderSets(){for(const b of document.querySelectorAll('[data-lim]'))b.classList.toggle('on',+b.dataset.lim===SET.lim);
 $('setsnd').textContent=SET.snd?'On':'Off';$('setsnd').classList.toggle('on',!!SET.snd);$('setvib').textContent=SET.vib?'On':'Off';$('setvib').classList.toggle('on',!!SET.vib);$('bsnd').textContent=SET.snd?'🔊':'🔇'}
$('mplay').onclick=()=>{restart();inMatch=true;show(null)};$('mcont').onclick=()=>{if(!loadMatch()){inMatch=true}show(null)};
$('mteam').onclick=()=>{renderShop();show('teams')};$('mform').onclick=()=>{renderForms();show('forms')};$('mfield').onclick=()=>{renderFields();show('fields')};$('mset').onclick=()=>{renderSets();show('sets')};
for(const b of document.querySelectorAll('[data-back]'))b.onclick=()=>show('menu');
$('tab0').onclick=()=>{tab=0;renderShop()};$('tab1').onclick=()=>{tab=1;renderShop()};$('ftab0').onclick=()=>{ftab=0;renderForms()};$('ftab1').onclick=()=>{ftab=1;renderForms()};
for(const b of document.querySelectorAll('[data-lim]'))b.onclick=()=>{SET.lim=+b.dataset.lim;store('nexora_set',SET);renderSets();sfx('ui')};
$('setsnd').onclick=$('bsnd').onclick=()=>{SET.snd=SET.snd?0:1;store('nexora_set',SET);renderSets();sfx('ui')};
$('setvib').onclick=()=>{SET.vib=SET.vib?0:1;store('nexora_set',SET);renderSets();vib(30)};
$('bmenu').onclick=()=>show('menu');$('reset').onclick=()=>{restart();inMatch=true;sfx('ui')};$('again').onclick=()=>{restart();inMatch=true};$('ovm').onclick=()=>show('menu');
window.addEventListener('resize',build);window.addEventListener('pagehide',saveMatch);document.addEventListener('visibilitychange',()=>{if(document.hidden)saveMatch()});
loadAll();ui();renderSets();show('menu');
Promise.all(Object.values(IMG).map(im=>new Promise(r=>{if(im.complete)r();else{im.onload=im.onerror=r}}))).then(()=>{build();reset(0);requestAnimationFrame(loop)});
})();
