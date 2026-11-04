(()=>{'use strict';
const $=i=>document.getElementById(i),canvas=$('game'),ctx=canvas.getContext('2d');
// دنیای بازی = مختصات خود تصویر زمین (1086x1448)
const K=1.27,PR=52.5,BR=25.5,STEP=1/240,RC=70,LMAX=210,NB=36;let DEPTH=112,KY=0;
// وزن و اصطکاک مهره‌ها (توپ دست‌نخورده است): HV = چند برابر سنگین‌تر در برخورد با توپ، PF1/PF2 = اصطکاک مهره‌ها
const HV=8,PF1=430,PF2=1.0,PV0=520,EPP=.62,PCAP=190; // PV0: speed (x K) where piece friction reaches full strength; below it pieces glide softly (measured from reference video) // HV: piece heaviness vs ball (higher = ball pushes pieces less), PF1/PF2: piece friction, EPP: piece-piece bounce, PCAP: max speed a passive piece gets from a ball hit
// دروازه‌ها: [عرض, ارتفاع, مرکز پایه چپ, مرکز پایه راست] (نسبت به عرض تصویر)
const GS={"white":[840,307,0.0491,0.9522],"wood":[840,306,0.0474,0.9519],"ice":[840,305,0.0535,0.9429],"black":[840,235,0.0521,0.9527],"rope":[840,246,0.0493,0.9528],"gold":[840,237,0.0431,0.9521],"red":[840,233,0.0502,0.9509],"blue":[840,236,0.0452,0.9526]};
// هر زمین: L/R = کنارخط‌ها، T/B = خط دروازه‌ها، cs = خط وسط، g = نصف عرض دهانهٔ دروازه، gs = تصویر دروازه
const FIELDS=[{"id":"forest","name":"Forest","W":1086,"H":1448,"L":195,"R":890,"T":127,"B":1311,"cs":702,"g":130,"gs":"wood"},{"id":"ice","name":"Ice","W":1086,"H":1448,"L":190,"R":895,"T":134,"B":1308,"cs":700,"g":132,"gs":"ice"},{"id":"ocean","name":"Ocean","W":1086,"H":1448,"L":191,"R":897,"T":108,"B":1313,"cs":701,"g":132,"gs":"blue"},{"id":"street","name":"Street","W":1086,"H":1448,"L":182,"R":902,"T":157,"B":1313,"cs":706,"g":134,"gs":"gold"},{"id":"streetarena","name":"Street Arena","W":1086,"H":1448,"L":194,"R":888,"T":117,"B":1309,"cs":702,"g":130,"gs":"rope"},{"id":"lava","name":"Lava","W":1086,"H":1448,"L":200,"R":884,"T":127,"B":1305,"cs":699,"g":128,"gs":"black"},{"id":"stadium","name":"Stadium","W":1086,"H":1448,"L":196,"R":888,"T":115,"B":1311,"cs":701,"g":129,"gs":"white"},{"id":"checker","name":"Checker","W":1086,"H":1448,"L":193,"R":890,"T":102,"B":1353,"cs":704,"g":130,"gs":"red"},{"id":"futsal","name":"Futsal","W":1086,"H":1448,"L":190,"R":895,"T":104,"B":1318,"cs":697,"g":132,"gs":"gold"},{"id":"arena","name":"Arena","W":1086,"H":1448,"L":199,"R":884,"T":118,"B":1313,"cs":694,"g":128,"gs":"red"},{"id":"arena2","name":"Grand Arena","W":1086,"H":1448,"L":164,"R":921,"T":135,"B":1302,"cs":703,"g":134,"gs":"gold"},{"id":"desert","name":"Desert","W":1086,"H":1448,"L":163,"R":920,"T":84,"B":1315,"cs":694,"g":134,"gs":"black"},{"id":"grove","name":"Grove","W":1086,"H":1448,"L":172,"R":918,"T":108,"B":1320,"cs":695,"g":134,"gs":"rope"},{"id":"pool","name":"Pool","W":1086,"H":1448,"L":160,"R":925,"T":98,"B":1312,"cs":697,"g":134,"gs":"white"},{"id":"neon","name":"Neon Tech","W":1024,"H":1536,"L":141,"R":883,"T":131,"B":1385,"cs":745,"g":139,"gs":"black"},{"id":"royal","name":"Royal","W":1024,"H":1536,"L":148,"R":877,"T":147,"B":1350,"cs":730,"g":136,"gs":"gold"},{"id":"mahogany","name":"Mahogany","W":1024,"H":1536,"L":97,"R":925,"T":90,"B":1393,"cs":729,"g":155,"gs":"wood"},{"id":"leather","name":"Leather","W":1024,"H":1536,"L":99,"R":925,"T":99,"B":1405,"cs":730,"g":154,"gs":"gold"},{"id":"aqua","name":"Aquarium","W":1024,"H":1536,"L":122,"R":905,"T":122,"B":1390,"cs":742,"g":146,"gs":"blue"},{"id":"asphalt","name":"Asphalt","W":1024,"H":1536,"L":97,"R":925,"T":113,"B":1417,"cs":742,"g":155,"gs":"rope"},{"id":"court","name":"Court","W":1024,"H":1536,"L":118,"R":907,"T":115,"B":1377,"cs":715,"g":148,"gs":"white"},{"id":"cyberbox","name":"Cyber Box","W":1024,"H":1536,"L":118,"R":906,"T":108,"B":1378,"cs":706,"g":147,"gs":"black"},{"id":"realmadrid","name":"Real Madrid","W":1086,"H":1448,"L":195,"R":889,"T":100,"B":1330,"cs":722,"g":130,"gs":"black"},{"id":"psg","name":"Paris SG","W":1086,"H":1448,"L":204,"R":881,"T":115,"B":1296,"cs":666,"g":130,"gs":"red"},{"id":"acmilan","name":"AC Milan","W":1086,"H":1448,"L":195,"R":889,"T":100,"B":1330,"cs":722,"g":130,"gs":"white"},{"id":"barcelona","name":"FC Barcelona","W":1086,"H":1448,"L":194,"R":889,"T":101,"B":1329,"cs":721,"g":130,"gs":"gold"},{"id":"persepolis","name":"Persepolis","W":1152,"H":1536,"L":207,"R":943,"T":135,"B":1410,"cs":770,"g":130,"gs":"white"},{"id":"esteghlal","name":"Esteghlal","W":1086,"H":1448,"L":195,"R":890,"T":100,"B":1322,"cs":690,"g":130,"gs":"gold"},{"id":"mancity","name":"Man City","W":1086,"H":1448,"L":195,"R":889,"T":102,"B":1329,"cs":719,"g":130,"gs":"red"}];
// اندازهٔ زمین: ضریب بزرگ‌نمایی دنیای بازی (۱ = اندازهٔ قبلی). مهره‌ها و توپ همان اندازه می‌مانند، پس جا بیشتر می‌شود.
const FS=1.12;FIELDS.forEach(f=>{for(const k of['W','H','L','R','T','B','cs'])f[k]=Math.round(f[k]*FS);f.g=Math.round(f.g*1.04)});
const SET={lim:5,snd:1,vib:1,mus:1,fld:0,ball:0};
let C={mode:'local',names:['',''],mirror:false,ai:-1,aiLvl:1,tt:0};
const EV={};const E={on(n,f){(EV[n]=EV[n]||[]).push(f);return E},emit(n,d){(EV[n]||[]).forEach(f=>{try{f(d)}catch(e){console.error(e)}})}};
if(!FIELDS[SET.fld])SET.fld=0;if(!(SET.ball>=0&&SET.ball<NB))SET.ball=0;




let F,Fw,Fh,CX,CY,GOALS,GG;
function geo(){const f=FIELDS[SET.fld];F={l:f.L+4,r:f.R-4,t:f.T+4,b:f.B-4};Fw=F.r-F.l;Fh=F.b-F.t;CX=(F.l+F.r)/2;CY=(F.t+F.b)/2;KY=f.cs;
 const gi=GS[f.gs],gw=2*f.g/(gi[3]-gi[2]);GG={w:gw,h:gw*gi[1]/gi[0],x:CX-f.g-gi[2]*gw};DEPTH=Math.max(106,Math.round(GG.h*.95));
 GOALS=[{team:0,y:F.t,x1:CX-f.g,x2:CX+f.g,d:-1},{team:1,y:F.b,x1:CX-f.g,x2:CX+f.g,d:1}]}geo();
const IMG={},SPR={};let s=1,ox=0,oy=0,Sx=1,Rx=0,Ry=0,bodies=[],ball=null,score=[0,0],turn=0,kick=0,phase='aim',drag=null,pause=0,idle=0,trail=[],shake=[0,0],flash=0,last=0,acc=0,bg=null,shots=0,menuOpen=true,inMatch=false,parts=[],tt=0,freeze=0,slow=0,cam=0,rings=[],lastPow=0;
const ok=n=>IMG[n]&&IMG[n].naturalWidth>0,mkc=(w,h)=>{const c=document.createElement('canvas');c.width=w;c.height=h;return c};
function load(n,src){if(!IMG[n]){const im=new Image();im.onload=()=>build();im.src=src;IMG[n]=im}return IMG[n]}
const fsrc=i=>'assets/fields/'+FIELDS[i].id+'.webp',tsrc=i=>'assets/fields/t_'+FIELDS[i].id+'.webp';
function rr(c,x,y,w,h,r){c.beginPath();c.moveTo(x+r,y);c.arcTo(x+w,y,x+w,y+h,r);c.arcTo(x+w,y+h,x,y+h,r);c.arcTo(x,y+h,x,y,r);c.arcTo(x,y,x+w,y,r);c.closePath()}
// ---------- تیم‌ها و ترکیب‌ها ----------
const CATS=[["club", "Clubs", ["Real Madrid", "Barcelona", "Manchester City", "Manchester United", "Liverpool", "Arsenal", "Chelsea", "Bayern Munich", "Borussia Dortmund", "Paris Saint-Germain", "Inter Milan", "AC Milan", "Juventus", "Atletico Madrid", "Ajax", "Benfica", "Porto", "Boca Juniors", "River Plate", "Flamengo", "Al Nassr", "Al Hilal", "Roma", "Besiktas", "Tottenham", "Marseille", "Napoli", "Sporting CP", "Sevilla", "Valencia", "PSV", "Celtic", "Bayer Leverkusen", "RB Leipzig", "Lyon", "Galatasaray", "Fenerbahce", "Shakhtar Donetsk", "Inter Miami", "Newcastle United", "Aston Villa", "West Ham United", "Everton", "Villarreal", "Fiorentina", "Corinthians", "Lazio", "Wolfsburg", "Persepolis", "Esteghlal"]], ["nat", "National", ["Argentina", "Brazil", "France", "Germany", "Portugal", "Spain", "Italy", "England", "Netherlands", "Belgium", "Uruguay", "Sweden", "Poland", "Denmark", "Croatia", "Switzerland", "Mexico", "USA", "Japan", "South Korea", "Australia", "Senegal", "Morocco", "Tunisia", "Egypt", "Iceland", "Iran", "Qatar", "Saudi Arabia", "Colombia", "Canada", "Turkey"]], ["vip", "VIP", ["Nova Blue", "Aurum Crest", "Emerald Core", "Specter Wings", "Infernal Edge", "Timber Blaze", "Chrome Vortex", "Crimson Pulse", "Thunder Gold", "Jade Marble", "Kakero Noir", "Kakero Frost"]], ["car", "Cars", ["Lamborghini", "Ferrari", "Rolls-Royce", "Mercedes-Benz", "BMW", "Porsche", "Maserati", "Aston Martin", "Bentley", "Bugatti", "Lexus", "Cadillac", "McLaren", "Tesla"]], ["lux", "Luxury", ["Louis Vuitton", "Chanel", "Gucci", "Hermes", "Prada", "Dior", "Versace", "Rolex", "Cartier", "Fendi", "Valentino", "Burberry", "Saint Laurent", "Swarovski"]], ["spt", "Sports", ["Nike", "Adidas", "Puma", "Under Armour", "New Balance", "Reebok", "Jordan", "Asics", "Wilson", "Speedo", "Converse", "Vans", "NBA", "Umbro"]]];
const TEAMS=[];for(const[k,,l]of CATS)l.forEach((n,i)=>TEAMS.push({id:k+i,cat:k,name:n,src:'assets/teams/'+k+String(i).padStart(2,'0')+'.webp',crop:[0,0,256,256]}));
const catOf=id=>Math.max(0,CATS.findIndex(c=>c[0]===T(id).cat));
const VIP_PRICES=[260,275,290,255,300,265,280,270,0,295,285,250],VIP_FREE='vip8';
const isVip=id=>T(id).cat==='vip';const vipPrice=id=>VIP_PRICES[+String(id).slice(3)]||0;
const T=id=>TEAMS.find(t=>t.id===id)||TEAMS[0];let sel=['club0','club1'];

const ct=t=>C.mirror?1-t:t,nm=t=>C.names[ct(t)]||T(sel[ct(t)]).name;
const FORMS=[['1-2-2','Balanced',[[.09,1],[.22,2],[.36,2]]],['2-2-1','Cautious',[[.10,2],[.24,2],[.37,1]]],['3-1-1','Wall',[[.10,3],[.25,1],[.37,1]]],['2-1-2','Diamond',[[.10,2],[.24,1],[.37,2]]],['1-3-1','Midfield',[[.09,1],[.23,3],[.37,1]]],['1-1-3','Attack',[[.09,1],[.22,1],[.36,3]]]];
let form=[0,0];
const slots=fi=>{const o=[];for(const[ny,c]of FORMS[fi][2])for(let i=0;i<c;i++)o.push([c===1?.5:c===2?.27+.46*i:.17+.33*i,ny]);return o};
// ---------- صدا و لرزش ----------
let AC=null,sT=0;
function tone(f,d,ty,v,f2){if(!SET.snd)return;try{AC=AC||new(window.AudioContext||window.webkitAudioContext)();const o=AC.createOscillator(),g=AC.createGain(),t=AC.currentTime;o.type=ty;o.frequency.setValueAtTime(f,t);if(f2)o.frequency.exponentialRampToValueAtTime(f2,t+d);g.gain.setValueAtTime(v,t);g.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(g);g.connect(AC.destination);o.start(t);o.stop(t+d)}catch(e){}}
// صداهای واقعی (از پوشهٔ sound): انتخاب، برخورد توپ/مهره، برخورد مهره/مهره، گزارشگر گل + موزیک منو
const SFXF={ui:['select.wav',1.7],hitb:['hit_ball.wav',1],hitp:['hit_piece.mp3',1],goal:['goal.wav',2.4],post:['ballHitsThePost.mp3',1.2],ann:['goalAnnounce.mp3',1.3],crowd:['crowd-03.mp3',.8],roar:['goalHappened-01.mp3',.9],whs:['startWistle.mp3',1],fin:['gameIsFinishedWistle.mp3',1],hb1:['BallHit-01.mp3',1],hb2:['BallHit-02.mp3',1],hb3:['BallHit-03.mp3',1]},SND={},sTs={};
function loadSnd(){try{AC=AC||new(window.AudioContext||window.webkitAudioContext)();for(const k in SFXF)fetch('assets/sfx/'+SFXF[k][0]).then(r=>r.arrayBuffer()).then(b=>new Promise((ok,no)=>AC.decodeAudioData(b,ok,no))).then(buf=>{SND[k]=buf}).catch(()=>{})}catch(e){}}
function play(k,vol,rate){const b=SND[k];if(!b||!SET.snd||!AC)return false;try{if(AC.state==='suspended')AC.resume();const o=AC.createBufferSource(),g=AC.createGain();o.buffer=b;o.playbackRate.value=rate||1;g.gain.value=vol;o.connect(g);g.connect(AC.destination);o.start();return true}catch(e){return false}}
function sfx(k,v){const n=performance.now();v=Math.min(1,v||1);if(k!=='goal'&&n-(sTs[k]||0)<45)return;sTs[k]=n;
 if(k==='hitb'){if(!play(['hb1','hb2','hb3','hitb'][Math.random()*4|0],(.35+.65*v)*SFXF.hitb[1],.93+.16*v))tone(430+v*220,.055,'triangle',.08+.26*v,230)}
 else if(k==='hitp'){if(!play('hitp',(.3+.7*v)*SFXF.hitp[1],.94+.14*v))tone(380+v*200,.055,'triangle',.08+.22*v,210)}
 else if(k==='wall'){tone(260+v*60,.06,'triangle',.06+.16*v,150);tone(780,.018,'sine',.04,500)}
 else if(k==='post'){if(!play('post',SFXF.post[1]*(.5+.5*v)))tone(640,.07,'triangle',.2,360)}
 else if(k==='whs')play('whs',SFXF.whs[1]);else if(k==='fin')play('fin',SFXF.fin[1]);
 else if(k==='ui'){if(!play('ui',SFXF.ui[1],1))tone(720,.03,'triangle',.07,480)}
 else if(k==='goal'){const ok=play('goal',SFXF.goal[1],1);play('roar',SFXF.roar[1]);setTimeout(()=>play('ann',SFXF.ann[1]),700);[523,659,784,1046].forEach((f,i)=>setTimeout(()=>{tone(f,.22,'sine',ok?.1:.2,f*.99);tone(f*2.01,.05,'triangle',ok?.04:.08)},(ok?160:0)+i*110))}}
const music=new Audio('assets/sfx/music.mp3');music.loop=true;music.preload='auto';music.volume=0;let mfade=0;const MVOL=.4;
const CROWD=['crowd-02.mp3','crowd-03.mp3'].map(f=>{const a=new Audio('assets/sfx/'+f);a.preload='auto';a.volume=.32;return a});let ci=0,cOn=false;
CROWD.forEach((a,i)=>a.addEventListener('ended',()=>{if(!cOn)return;ci=(i+1)%CROWD.length;const n=CROWD[ci];n.currentTime=0;n.volume=.32;const p=n.play();if(p&&p.catch)p.catch(()=>{})}));
function crowdSync(){const want=!!SET.snd&&inMatch&&!document.hidden;if(want===cOn)return;cOn=want;if(want){const a=CROWD[ci];a.volume=.32;const p=a.play();if(p&&p.catch)p.catch(()=>{})}else CROWD.forEach(a=>a.pause())}
function musicSync(){crowdSync();const want=!!SET.snd&&SET.mus!==0&&menuOpen&&!document.hidden;if(want===!music.paused)return;clearInterval(mfade);
 if(want){music.volume=Math.min(music.volume,.01);const p=music.play();if(p&&p.catch)p.catch(()=>{});mfade=setInterval(()=>{music.volume=Math.min(MVOL,music.volume+.04);if(music.volume>=MVOL)clearInterval(mfade)},60)}
 else{mfade=setInterval(()=>{music.volume=Math.max(0,music.volume-.08);if(music.volume<=0){music.pause();clearInterval(mfade)}},50)}}
const vib=n=>{if(SET.vib&&navigator.vibrate)try{navigator.vibrate(n)}catch(e){}};
// ---------- تصاویر ----------
function img(id){return load(id,T(id).src)}
function ui(){for(const t of[0,1]){$('i'+t).src=T(sel[ct(t)]).src;$('n'+t).textContent=nm(t)}stat()}
function shrink(n,c,w,h,flip){if(!ok(n))return null;let src=IMG[n],sx=c[0],sy=c[1],sw=c[2]-c[0],sh=c[3]-c[1];
 while(sw/2>w&&sh/2>h){const t=mkc(Math.round(sw/2),Math.round(sh/2)),x=t.getContext('2d');x.imageSmoothingQuality='high';x.drawImage(src,sx,sy,sw,sh,0,0,t.width,t.height);src=t;sx=sy=0;sw=t.width;sh=t.height}
 const o=mkc(w,h),x=o.getContext('2d');x.imageSmoothingQuality='high';if(flip){x.translate(0,h);x.scale(1,-1)}x.drawImage(src,sx,sy,sw,sh,0,0,w,h);return o}
function build(){const W=innerWidth,H=innerHeight,d=Math.min(devicePixelRatio||1,1.75),f=FIELDS[SET.fld];if(W<50||H<50)return;
 s=Math.min(W/(f.R-f.L+56*FS),(H-250)/((f.B-f.T)+2*GG.h+48))*1.14*1.02;ox=W/2-CX*s;oy=H/2-CY*s;canvas.width=Math.round(W*d);canvas.height=Math.round(H*d);Sx=s*d;Rx=ox*d;Ry=oy*d;
 const px=v=>Math.max(2,Math.round(v*Sx)),fi=load('f'+SET.fld,fsrc(SET.fld));bg=$('bgc');bg.width=canvas.width;bg.height=canvas.height;const b=bg.getContext('2d');b.setTransform(1,0,0,1,0,0);b.imageSmoothingQuality='high';b.fillStyle='#03060d';b.fillRect(0,0,bg.width,bg.height);
 if(ok('f'+SET.fld)){const c=Math.max(bg.width/f.W,bg.height/f.H);try{b.filter='blur(8px)'}catch(e){}b.drawImage(fi,(bg.width-f.W*c)/2,(bg.height-f.H*c)/2,f.W*c,f.H*c);try{b.filter='none'}catch(e){}b.fillStyle='rgba(0,0,0,.5)';b.fillRect(0,0,bg.width,bg.height);
  const t=mkc(bg.width,bg.height),x=t.getContext('2d');x.imageSmoothingQuality='high';x.drawImage(fi,Rx-0,Ry-0,f.W*Sx,f.H*Sx);x.globalCompositeOperation='destination-in';
  const gv=x.createLinearGradient(0,Ry,0,Ry+f.H*Sx);gv.addColorStop(0,'rgba(0,0,0,0)');gv.addColorStop(.07,'#000');gv.addColorStop(.93,'#000');gv.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=gv;x.fillRect(0,0,t.width,t.height);
  const gh=x.createLinearGradient(Rx,0,Rx+f.W*Sx,0);gh.addColorStop(0,'rgba(0,0,0,0)');gh.addColorStop(.04,'#000');gh.addColorStop(.96,'#000');gh.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=gh;x.fillRect(0,0,t.width,t.height);b.drawImage(t,0,0)}
 for(const q of[0,1]){const t=T(sel[ct(q)]);SPR['s'+q]=shrink(t.id,t.crop,px(PR*2),px(PR*2));{const sp=SPR['s'+q];if(sp){const c=mkc(sp.width,sp.height),x=c.getContext('2d');x.drawImage(sp,0,0);x.globalCompositeOperation='source-atop';x.fillStyle='rgba(6,8,24,.66)';x.fillRect(0,0,c.width,c.height);SPR['d'+q]=c}}}SPR.ball=shrink('ball'+SET.ball,[0,0,400,400],px(BR*2),px(BR*2));
 {const N=Math.max(40,Math.min(96,px(BR*2)));SPR.bn=N;SPR.bc=mkc(N,N);SPR.bx=SPR.bc.getContext('2d');SPR.bd=SPR.bx.createImageData(N,N);SPR.bg=buildSphere(N);
  SPR.hx=0;SPR.hy=0;SPR.hz=0;{const Lx=-.42,Ly=-.55,Lz=.72,l=Math.hypot(Lx,Ly,Lz);let a=Lx/l,b=Ly/l,c=Lz/l+1;const m=Math.hypot(a,b,c);SPR.hx=a/m;SPR.hy=b/m;SPR.hz=c/m}
  SPR.bt=ok('ball'+SET.ball)?ballTex(IMG['ball'+SET.ball]):null;SPR.bv=-1}
 {const hs=Math.max(48,px(BR*5)),mh=(c,a)=>{const h=mkc(hs,hs),x=h.getContext('2d'),g=x.createRadialGradient(hs/2,hs/2,hs*.058,hs/2,hs/2,hs/2);g.addColorStop(0,'rgba('+c+','+a+')');g.addColorStop(.4,'rgba(100,130,160,.15)');g.addColorStop(1,'rgba(40,50,65,0)');x.fillStyle=g;x.fillRect(0,0,hs,hs);return h};SPR.h0=mh('80,155,255',.26);SPR.h1=mh('255,170,70',.4)}
 SPR.goal=GOALS.map(g=>shrink('goal_'+f.gs,[0,0,GS[f.gs][0],GS[f.gs][1]],px(GG.w),px(GG.h),g.d>0));
 const sd=px(PR*2.6),sc=mkc(sd,sd),x=sc.getContext('2d'),gr=x.createRadialGradient(sd/2,sd/2,sd*.18,sd/2,sd/2,sd/2);gr.addColorStop(0,'rgba(0,0,0,.6)');gr.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=gr;x.fillRect(0,0,sd,sd);SPR.shadow=sc}
const gsrc=i=>'assets/goals/'+FIELDS[i].gs+'.webp',lg=i=>load('goal_'+FIELDS[i].gs,gsrc(i));
function loadAll(){lg(SET.fld);load('ball'+SET.ball,'assets/balls/b'+SET.ball+'.png');load('f'+SET.fld,fsrc(SET.fld));img(sel[0]);img(sel[1])}
// ---------- منطق بازی ----------
const mk=(x,y,team,r,m)=>({x,y,vx:0,vy:0,r,m,im:1/m,team,spin:0,ang:0,R:[1,0,0,0,1,0,0,0,1],rv:0,sq:0});
function reset(k){bodies=[];trail=[];parts=[];rings=[];freeze=0;slow=0;cam=0;
 for(let cm=0;cm<2;cm++)slots(form[cm]).forEach(([nx,ny],i)=>{let x=F.l+PR+10+nx*(Fw-2*(PR+10)),y=cm?F.t+ny*Fh:F.b-ny*Fh;if(C.mirror){x=2*CX-x;y=2*CY-y}const b=mk(x,y,ct(cm),PR,5);b.cid=cm*20+i;b.boost=0;bodies.push(b)});
 ball=mk(CX,C.mirror?2*CY-KY:KY,2,BR,1.5);ball.cid=99;bodies.push(ball);turn=k;phase='aim';drag=null;pause=0;idle=0;shots=0;tleft=C.tt;remote=false;aiT=0;aiPlan=null;stat()}
function stat(){$('t0').classList.toggle('on',phase==='aim'&&!turn);$('t1').classList.toggle('on',phase==='aim'&&!!turn);const tm=$('tmr');if(tm)tm.classList.toggle('on',phase==='aim'&&C.tt>0)}
let gtt=0;function goalFx(n){const e=$('goalfx');if(!e){toast('GOAL! '+n,1);return}e.querySelector('small').textContent=n||'';e.classList.remove('show');void e.offsetWidth;e.classList.add('show');clearTimeout(gtt);gtt=setTimeout(()=>e.classList.remove('show'),1900)}
function toast(t,big){const e=$('toast');e.className='toast'+(big?' g':'');e.textContent=t;void e.offsetWidth;e.classList.add('show');clearTimeout(tt);tt=setTimeout(()=>e.classList.remove('show'),big?1500:1200)}
function burst(x,y,n,sp,cols,life,k){if(parts.length>360)return;for(let i=0;i<n;i++){const a=Math.random()*7,v=sp*(.3+Math.random());parts.push({x,y,vx:Math.cos(a)*v,vy:Math.sin(a)*v,l:life*(.6+Math.random()*.6),m:life,c:cols[i%cols.length],r:2+Math.random()*3.5,k:k||0,g:0,rot:Math.random()*6})}}
function wallFx(x,y,vs){/* collision sparks disabled: keep ball unobstructed */}
function spawn(x,y,vx,vy,l,r,c,k,g){if(parts.length>360)return;parts.push({x,y,vx,vy,l,m:l,r,c,k:k||0,g:g||0,rot:Math.random()*6})}
function scored(t,fromRemote){const ng=shots<=1;
 if(!fromRemote&&C.mode==='online')E.emit('goal',{team:ct(t),nogoal:ng});
 if(ng){phase='goal';pause=1.4;kick=turn;toast('No goal');stat();return}
 score[t]++;$('s'+(t+1)).textContent=score[t];pause=1.8;flash=1;shake[t]=.6;phase='goal';kick=1-t;goalFx(nm(t));stat();
 const bc=(TR[SET.ball%TR.length]||TR[0]).c;burst(ball.x,GOALS[t].y,70,700,['#ffd23a','#fff',bc[0],bc[1]],1.3);burst(ball.x,GOALS[t].y,46,520,bc.concat(['#fff']),1.6,1);sfx('goal');vib([60,40,120]);slow=1.1;cam=1.4;rings.push({x:ball.x,y:GOALS[t].y,r:20,l:.7,m:.7,w:1});for(let w=0;w<3;w++)setTimeout(()=>{if(inMatch){const cc=['#ffd23a','#ff4a7a','#3bd0ff','#7bff5a','#fff'];burst(F.l+Math.random()*(F.r-F.l),GOALS[t].y+(GOALS[t].d<0?60:-60),26,420,cc,1.4,3);burst(F.l+Math.random()*(F.r-F.l),GOALS[t].y,18,300,cc,1.2,1)}},250+w*300);E.emit('scored',{team:ct(t),score:[score[ct(0)],score[ct(1)]],mine:t===0})}
function walls(b){if(b!==ball&&b.gout){const g=b.gout,dq=g.d*(b.y-g.y);if(dq>-b.r*1.05){b.vy=-g.d*270*K;b.vx*=.6}else{b.vy=0;b.vx*=.2;b.gout=null}}
 const bl=b===ball,r=b.r,vs=Math.hypot(b.vx,b.vy),eN=vn=>bl?.84-.22*Math.min(1,Math.max(0,(vn-270*K)/(1350*K))):.82,e=eN(vs); // ball wall bounce from reference video: ~.72 slow, ~.42 fast (uses the normal speed)
 if(b.x-r<F.l){b.x=F.l+r;if(b.vx<0){if(bl&&vs>200){sfx('wall',vs/1800);wallFx(F.l,b.y,vs)}b.vx*=-eN(-b.vx);b.spin+=b.vy/r*.05}}
 if(b.x+r>F.r){b.x=F.r-r;if(b.vx>0){if(bl&&vs>200){sfx('wall',vs/1800);wallFx(F.r,b.y,vs)}b.vx*=-eN(b.vx);b.spin-=b.vy/r*.05}}
  for(const g of GOALS){const dp=g.d*(b.y-g.y);if(dp<=-r)continue;
  // توپ: وسط دهانه باشد؛ مهره: کل بدنه داخل دهانه باشد (یا از خط گذشته باشد) تا گیر نکند
  const lo=g.x1+(bl?0:r),hi=g.x2-(bl?0:r),inside=bl?(b.x>g.x1&&b.x<g.x2):(dp>0||(b.x>=lo&&b.x<=hi));
  if(inside){const gl=phase==='goal'&&bl,eb=gl?.2:eN(Math.abs(b.vy)),back=g.y+g.d*DEPTH;
   if(!bl&&dp>r*.3&&vs<150*K&&!b.gout)b.gout=g;
   if(dp+r>DEPTH){b.y=back-g.d*r;b.vy=-g.d*Math.abs(b.vy)*eb;if(gl)b.vx*=.6}
   if(dp>(bl?r*.6:0)){const ee=gl?.3:eN(Math.abs(b.vx));if(b.x<g.x1+r){b.x=g.x1+r;if(b.vx<0)b.vx*=-ee}if(b.x>g.x2-r){b.x=g.x2-r;if(b.vx>0)b.vx*=-ee}}
  }else{if(bl&&vs>200){sfx('wall',vs/1800);wallFx(b.x,g.y,vs)}b.y=g.y-g.d*r;if(g.d*b.vy>0)b.vy=-g.d*Math.abs(b.vy)*eN(Math.abs(b.vy));b.spin+=g.d*b.vx/r*.05}}
 for(const[cx,cy,sx,sy]of[[F.l+RC,F.t+RC,1,1],[F.r-RC,F.t+RC,-1,1],[F.l+RC,F.b-RC,1,-1],[F.r-RC,F.b-RC,-1,-1]]){
  if((b.x-cx)*sx<0&&(b.y-cy)*sy<0){const dx=b.x-cx,dy=b.y-cy,d=Math.hypot(dx,dy),lim=RC-r;if(d>lim&&d>0){const nx=dx/d,ny=dy/d,vn=b.vx*nx+b.vy*ny;b.x=cx+nx*lim;b.y=cy+ny*lim;if(vn>0){const ec=eN(vn);b.vx-=(1+ec)*vn*nx;b.vy-=(1+ec)*vn*ny}}}}}
function post(b,px,py){const dx=b.x-px,dy=b.y-py,d=Math.hypot(dx,dy),m=b.r+5;if(d>=m||!d)return;const nx=dx/d,ny=dy/d,vn=b.vx*nx+b.vy*ny;b.x=px+nx*m;b.y=py+ny*m;if(vn<0){const kp=b===ball?1.7-.16*Math.min(1,-vn/(2000*K)):1.7;b.vx-=kp*vn*nx;b.vy-=kp*vn*ny;if(b===ball){sfx('post',-vn/1800);if(-vn>900*K){toast('Post!');cam=Math.max(cam,.18)}}tone(1500,.03,'sine',.05,900)}}
function hit(a,b){let dx=b.x-a.x,dy=b.y-a.y,d=Math.hypot(dx,dy);const m=a.r+b.r;if(d>=m)return;if(d<1e-4){dx=1;dy=0;d=1}
 const nx=dx/d,ny=dy/d,sm=a.im+b.im,isB=a===ball||b===ball;
 // برخورد مهره با توپ: توپ دقیقاً مثل قبل واکنش می‌گیرد ولی مهره فقط 1/HV از ضربه را می‌گیرد (یعنی سنگین‌تر است)
 let ka=isB&&a!==ball?1/HV:1,kb=isB&&b!==ball?1/HV:1;if(!isB){const sa=Math.hypot(a.vx,a.vy),sb=Math.hypot(b.vx,b.vy);if(sa>sb)kb=.85;else ka=.85}let wa=a.im/sm*ka,wb=b.im/sm*kb;if(isB){if(a===ball)wa=1-wb;else wb=1-wa}
 const pen=Math.max(m-d-.3,0)*.9;a.x-=nx*pen*wa;a.y-=ny*pen*wa;b.x+=nx*pen*wb;b.y+=ny*pen*wb;
 const vn=(b.vx-a.vx)*nx+(b.vy-a.vy)*ny;if(vn>=0)return;
 const e=vn<-40*K?(isB?.74-.12*Math.min(1,Math.max(0,(-vn-500*K)/(1200*K))):EPP):0,j=-(1+e)*vn/sm,pa=isB?(a===ball?b:a):null,pre=pa?Math.hypot(pa.vx,pa.vy):0;
 a.vx-=j*nx*a.im*ka;a.vy-=j*ny*a.im*ka;b.vx+=j*nx*b.im*kb;b.vy+=j*ny*b.im*kb;
 if(pa&&pre<260*K){const ps=Math.hypot(pa.vx,pa.vy),cp=PCAP*K;if(ps>cp){pa.vx*=cp/ps;pa.vy*=cp/ps}}
 if(vn<-120*K){sfx(isB?'hitb':'hitp',-vn/1900);if(vn<-420*K){const q=Math.min(1,-vn/(1500*K));if(!isB){a.sq=Math.max(a.sq||0,q);b.sq=Math.max(b.sq||0,q);/* piece collision spark removed */}vib(12)}}
 if(isB){ball.spin+=(ball===b?1:-1)*(-ny*(b.vx-a.vx)+nx*(b.vy-a.vy))/ball.r*.3;ball.spin=Math.max(-34,Math.min(34,ball.spin));
  const pw=Math.min(1,-vn/(1700*K));if(pw>.2){const o=ball===b?a:b,px=ball.x-nx*(ball===b?1:-1)*ball.r*.0,sg=ball===b?-1:1;
   ball.sq=Math.max(ball.sq,pw);cam=Math.max(cam,pw*.9);if(o.sq!==undefined)o.sq=Math.max(o.sq||0,pw);if(pw>.75&&freeze<=0)freeze=.04;
   /* ball impact sparks/rings removed for visibility */
   if(!SND.hitb){tone(200+pw*70,.09,'triangle',.14+.26*pw,110);tone(1000+pw*500,.025,'sine',.06+.06*pw,650)}vib(pw>.7?[18,14,30]:16)}}}

// ---------- توپ سه‌بعدی: غلتیدن واقعی ----------
const _M=new Float64Array(9);
function rot(R,wx,wy,wz,dt){const w=Math.hypot(wx,wy,wz),th=w*dt;if(th<1e-7)return;
 const nx=wx/w,ny=wy/w,nz=wz/w,c=Math.cos(th),sn=Math.sin(th),C=1-c,M=_M;
 M[0]=c+nx*nx*C;M[1]=nx*ny*C-nz*sn;M[2]=nx*nz*C+ny*sn;M[3]=ny*nx*C+nz*sn;M[4]=c+ny*ny*C;M[5]=ny*nz*C-nx*sn;M[6]=nz*nx*C-ny*sn;M[7]=nz*ny*C+nx*sn;M[8]=c+nz*nz*C;
 for(let q=0;q<3;q++){const a=R[q],b=R[3+q],d=R[6+q];R[q]=M[0]*a+M[1]*b+M[2]*d;R[3+q]=M[3]*a+M[4]*b+M[5]*d;R[6+q]=M[6]*a+M[7]*b+M[8]*d}}
const TS=256;
function ballTex(im){const c=mkc(TS,TS),x=c.getContext('2d');x.imageSmoothingQuality='high';x.fillStyle='#10161f';x.fillRect(0,0,TS,TS);if(im)x.drawImage(im,0,0,TS,TS);const o=x.getImageData(0,0,TS,TS),d=o.data;
 {const bc=mkc(TS,TS),bx=bc.getContext('2d'),sm=mkc(10,10),sx=sm.getContext('2d');sx.imageSmoothingQuality='high';sx.drawImage(c,0,0,10,10);bx.imageSmoothingEnabled=true;bx.imageSmoothingQuality='high';bx.drawImage(sm,0,0,TS,TS);const bd=bx.getImageData(0,0,TS,TS).data;let m=0,n=0;for(let i=0;i<d.length;i+=4){const px=((i>>2)%TS)/TS-.5,py=((i>>2)/TS|0)/TS-.5;if(px*px+py*py<.2){m+=bd[i]*.3+bd[i+1]*.59+bd[i+2]*.11;n++}}m=(m/n)||128;
  for(let i=0;i<d.length;i+=4){const L=bd[i]*.3+bd[i+1]*.59+bd[i+2]*.11,f=Math.max(.75,Math.min(1.5,Math.pow(m/Math.max(24,L),.6)));d[i]=Math.min(255,d[i]*f);d[i+1]=Math.min(255,d[i+1]*f);d[i+2]=Math.min(255,d[i+2]*f)}}
 return d}
function buildSphere(N){const g=new Float32Array(N*N*6),h=N/2,Lx=-.42,Ly=-.55,Lz=.72,ll=Math.hypot(Lx,Ly,Lz),lx=Lx/ll,ly=Ly/ll,lz=Lz/ll;
 let hx=lx,hy=ly,hz=lz+1;const hl=Math.hypot(hx,hy,hz);hx/=hl;hy/=hl;hz/=hl;
 for(let j=0;j<N;j++)for(let i=0;i<N;i++){const px=(i+.5-h)/h,py=(j+.5-h)/h,d2=px*px+py*py,o=(j*N+i)*6,d=Math.sqrt(d2),cov=Math.max(0,Math.min(1,(1-d)*h*1.1+.5));
  if(cov<=0){g[o+4]=0;continue}const z=Math.sqrt(Math.max(0,1-Math.min(d2,1))),dif=Math.max(0,px*lx+py*ly+z*lz);
  const fr=Math.pow(1-z,2.4),wrap=Math.max(0,(px*lx+py*ly+z*lz)*.5+.5),lit=.50+.58*wrap*wrap+.14*dif-.30*fr;   // نور نرم‌تر با لبهٔ تاریک‌تر برای حجم
  const back=Math.pow(1-z,3)*Math.max(0,-(px*lx+py*ly))*.9;                                                       // نور لبهٔ سرد از پشت
  g[o]=px;g[o+1]=py;g[o+2]=z;g[o+3]=lit;g[o+4]=cov;g[o+5]=back}
 return g}
function spec(px,py,z){return 0}
const _sm=[0,0,0];
function samp(T,R,px,py,pz,k){let qx=R[0]*px+R[3]*py+R[6]*pz,qy=R[1]*px+R[4]*py+R[7]*pz;
 let u=TS/2+qx*k-.5,v=TS/2+qy*k-.5;if(u<0)u=0;else if(u>TS-1.01)u=TS-1.01;if(v<0)v=0;else if(v>TS-1.01)v=TS-1.01;
 const u0=u|0,v0=v|0,fu=u-u0,fv=v-v0,a=(v0*TS+u0)*4,b=a+4,c=a+TS*4,e=c+4,w1=(1-fu)*(1-fv),w2=fu*(1-fv),w3=(1-fu)*fv,w4=fu*fv;
 _sm[0]=T[a]*w1+T[b]*w2+T[c]*w3+T[e]*w4;_sm[1]=T[a+1]*w1+T[b+1]*w2+T[c+1]*w3+T[e+1]*w4;_sm[2]=T[a+2]*w1+T[b+2]*w2+T[c+2]*w3+T[e+2]*w4}
const _Rm=new Float64Array(9);
function renderBall(){if(!ball||!SPR.bt||!SPR.bd)return;const N=SPR.bn,g=SPR.bg,d=SPR.bd.data,T=SPR.bt,R=ball.R,k=.93*.5*TS;
 // کم‌رنگ‌کردن حرکتی (motion blur): نمونه‌برداری از چرخش قبلی و میانی، فقط وقتی توپ سریع می‌چرخد
 const Rp=SPR.Rp||(SPR.Rp=new Float64Array(R));let dm=0;for(let i=0;i<9;i++)dm+=Math.abs(R[i]-Rp[i]);
 const taps=dm>.16?3:dm>.035?2:1;for(let i=0;i<9;i++)_Rm[i]=(R[i]+Rp[i])*.5;
 for(let j=0;j<N;j++)for(let i=0;i<N;i++){const o=(j*N+i)*6,q=(j*N+i)*4,cov=g[o+4];if(cov<=0){d[q+3]=0;continue}
  const px=g[o],py=g[o+1],pz=g[o+2],lit=g[o+3],back=g[o+5];
  samp(T,R,px,py,pz,k);let r=_sm[0],gg=_sm[1],bb=_sm[2];
  if(taps>1){samp(T,_Rm,px,py,pz,k);const w=taps===3?.34:.45;r=r*(1-w)+_sm[0]*w;gg=gg*(1-w)+_sm[1]*w;bb=bb*(1-w)+_sm[2]*w;
   if(taps===3){samp(T,Rp,px,py,pz,k);r=r*.7+_sm[0]*.3;gg=gg*.7+_sm[1]*.3;bb=bb*.7+_sm[2]*.3}}
  const sd=px*SPR.hx+py*SPR.hy+pz*SPR.hz,hl=pz>0?Math.pow(Math.max(0,sd),46)*150+Math.pow(Math.max(0,sd),7)*20:0;   // برق تیز + درخشش نرم
  r=r*lit+hl+back*70;gg=gg*lit+hl+back*105;bb=bb*lit+hl+back*150;d[q]=r>255?255:r;d[q+1]=gg>255?255:gg;d[q+2]=bb>255?255:bb;d[q+3]=cov*255}
 Rp.set(R);SPR.bx.putImageData(SPR.bd,0,0);SPR.bv=ball.rv}
function sim(dt){
 for(const b of bodies){b.x+=b.vx*dt;b.y+=b.vy*dt;const sp=Math.hypot(b.vx,b.vy),bl=b===ball;
  if(sp>0){
   if(bl){const f=610*K*Math.min(1,sp/(480*K))+sp*.035,ns=sp-f*dt;
    if(ns<12*K){b.vx=b.vy=0}else{
     const m=Math.max(-34,Math.min(34,b.spin))*.034*dt,cs=Math.cos(m),sn=Math.sin(m),vx=b.vx*cs-b.vy*sn,vy=b.vx*sn+b.vy*cs,k=Math.min(ns,2500*K)/sp;b.vx=vx*k;b.vy=vy*k}}
   else{const fb=b.boost>0?.35:1;if(b.boost>0)b.boost-=dt;const ns=sp-(PF1*K*Math.min(1,sp/(PV0*K))+sp*PF2)*fb*dt;if(ns<14*K){b.vx=b.vy=0}else{const k=Math.min(ns,2800*K)/sp;b.vx*=k;b.vy*=k}}}
  if(bl){const sp2=Math.hypot(b.vx,b.vy);b.spin*=1-(sp2>0?1.05:3.2)*dt;if(Math.abs(b.spin)<.02)b.spin=0;b.sq*=1-9*dt;
   const roll=.95/b.r,wx=-b.vy*roll,wy=b.vx*roll,wz=b.spin*.55;if(sp2>0||wz){rot(b.R,wx,wy,wz,dt);b.rv++}b.ang+=b.spin*dt}
  else{b.spin*=1-2.6*dt;b.ang+=b.spin*dt}
  walls(b)}
 for(let i=0;i<2;i++)for(let a=0;a<bodies.length;a++)for(let c=a+1;c<bodies.length;c++)hit(bodies[a],bodies[c]);
 if(ball)for(const g of GOALS){post(ball,g.x1,g.y);post(ball,g.x2,g.y)}for(const b of bodies)walls(b);
 if(phase==='move'&&!remote)for(const g of GOALS)if(ball.x>g.x1&&ball.x<g.x2&&(g.d<0?ball.y<g.y-ball.r*.8:ball.y>g.y+ball.r*.8))scored(g.team)}
// ---------- رسم ----------
const RING=['#3b9bff','#ff5b5b'];
function sprite(b){const sp=b===ball?SPR.ball:b.team?SPR.s1:SPR.s0;
 if(!sp){ctx.fillStyle=b===ball?'#fff':RING[b.team];ctx.beginPath();ctx.arc(b.x,b.y,b.r,0,7);ctx.fill();return}
 ctx.save();
 let drawY=b.y;
 if(b===ball){
  const sv=Math.hypot(b.vx,b.vy),fast=Math.min(1,sv/(1700*K));
  if(SPR.bt&&SPR.bv!==b.rv)renderBall();
  {const R=b.r*(2.15+fast*.5),hot=fast>.55;ctx.globalAlpha=hot?(.18+.22*fast)/.4:1;ctx.drawImage(hot?SPR.h1:SPR.h0,b.x-R,drawY-R,R*2,R*2);ctx.globalAlpha=1}
  // سایهٔ نرم زیر توپ (فاصلهٔ آن با سرعت کمی بیشتر می‌شود)
  const so=b.r*(.55+.25*fast);ctx.globalAlpha=.8;ctx.fillStyle='rgba(8,14,24,.42)';ctx.beginPath();ctx.ellipse(b.x+so*.35,b.y+so,b.r*.86,b.r*.34,0,0,Math.PI*2);ctx.fill();ctx.globalAlpha=1;
  ctx.translate(b.x,b.y);
  if(sv>40){const a=Math.atan2(b.vy,b.vx),st=Math.min(.16,fast*.12)+b.sq*.12,sq=b.sq*.1;ctx.rotate(a);ctx.scale(1+st-sq,1-st*.55+sq);ctx.rotate(-a)}
  if(SPR.bt)ctx.drawImage(SPR.bc,-b.r,-b.r,b.r*2,b.r*2);else{ctx.rotate(b.ang);ctx.drawImage(sp,-b.r,-b.r,b.r*2,b.r*2)}
  ctx.restore();return}
 {const ph=(b.cid||0)*1.7;drawY+=Math.sin(performance.now()/1000*1.6+ph)*1.6*(b.vx||b.vy?0:1)}
 ctx.translate(b.x,drawY);
 const vip=T(sel[ct(b.team)]).cat==='vip';
 const isActive=phase==='aim'&&!menuOpen&&b.team===turn;
 {const sv=Math.hypot(b.vx,b.vy);if(sv>60||b.sq>.02){const a=Math.atan2(b.vy,b.vx),st=Math.min(.1,sv/(1800*K)*.1)+(b.sq||0)*.1,sq=(b.sq||0)*.14;ctx.rotate(a);ctx.scale(1+st-sq,1-st*.6+sq);ctx.rotate(-a)}}
 if(vip&&isActive)ctx.rotate(performance.now()/1450);
 {const sd=b.team?SPR.d1:SPR.d0;if(sd)for(let k=4;k>=1;k--)ctx.drawImage(sd,-b.r,-b.r+b.r*.052*k,b.r*2,b.r*2)}ctx.drawImage(sp,-b.r,-b.r,b.r*2,b.r*2);
 if(vip&&isActive){const glow=ctx.createRadialGradient(-b.r*.28,-b.r*.36,b.r*.04,0,0,b.r*.96);glow.addColorStop(0,'rgba(255,255,255,.62)');glow.addColorStop(.34,'rgba(255,255,255,.20)');glow.addColorStop(1,'rgba(255,255,255,0)');ctx.globalCompositeOperation='screen';ctx.fillStyle=glow;ctx.beginPath();ctx.arc(0,0,b.r*.96,0,Math.PI*2);ctx.fill()}
 ctx.restore()}
function aim(){if(!drag)return;const{b,s:p0,c}=drag,dx=p0.x-c.x,dy=p0.y-c.y,l=Math.hypot(dx,dy);if(l<18)return;const p=Math.min(l,LMAX)/LMAX,ux=dx/l,uy=dy/l;let t=1200;
 for(const o of bodies){if(o===b)continue;const R=b.r+o.r,qx=o.x-b.x,qy=o.y-b.y,u=qx*ux+qy*uy;if(u<=0)continue;const D=u*u-(qx*qx+qy*qy-R*R);if(D>=0){const h=u-Math.sqrt(D);if(h>0&&h<t)t=h}}
 if(ux<0)t=Math.min(t,(F.l+b.r-b.x)/ux);if(ux>0)t=Math.min(t,(F.r-b.r-b.x)/ux);if(uy<0)t=Math.min(t,(F.t+b.r-b.y)/uy);if(uy>0)t=Math.min(t,(F.b-b.r-b.y)/uy);t=Math.max(t,0);
 const now=performance.now(),hue=135-135*p,col='hsl('+hue+',95%,58%)',col2='hsl('+(hue+35)+',100%,76%)',sx=b.x+ux*b.r,sy=b.y+uy*b.r,ex=b.x+ux*t,ey=b.y+uy*t,tm=b.team?'255,110,110':'90,175,255';
 ctx.save();ctx.lineCap='round';ctx.lineJoin='round';
 // نوار کشش (کش) از نقطهٔ شروع تا انگشت
 ctx.strokeStyle='rgba('+tm+',.35)';ctx.lineWidth=3;ctx.setLineDash([2,9]);ctx.beginPath();ctx.moveTo(p0.x,p0.y);ctx.lineTo(c.x,c.y);ctx.stroke();ctx.setLineDash([]);
 ctx.fillStyle='rgba('+tm+',.55)';ctx.beginPath();ctx.arc(c.x,c.y,9+p*4,0,7);ctx.fill();ctx.strokeStyle='#fff';ctx.lineWidth=2;ctx.beginPath();ctx.arc(c.x,c.y,9+p*4,0,7);ctx.stroke();
 ctx.globalCompositeOperation='lighter';
 // خط پیش‌بینی با گرادیان و درخشش
 const g=ctx.createLinearGradient(sx,sy,ex,ey);g.addColorStop(0,col);g.addColorStop(1,'rgba(255,255,255,.2)');
 ctx.strokeStyle=g;ctx.globalAlpha=.16;ctx.lineWidth=16;ctx.beginPath();ctx.moveTo(sx,sy);ctx.lineTo(ex,ey);ctx.stroke();
 ctx.globalAlpha=.85;ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(sx,sy);ctx.lineTo(ex,ey);ctx.stroke();
 // شورون‌های متحرک روی مسیر
 const step=44,off=(now/12)%step;
 for(let d=b.r+14+off;d<t-b.r*.5;d+=step){const x=b.x+ux*d,y=b.y+uy*d,a=Math.max(0,1-d/t*.75);ctx.globalAlpha=a;ctx.strokeStyle=col2;ctx.lineWidth=4;ctx.beginPath();ctx.moveTo(x-uy*9-ux*8,y+ux*9-uy*8);ctx.lineTo(x+ux*5,y+uy*5);ctx.lineTo(x+uy*9-ux*8,y-ux*9-uy*8);ctx.stroke()}
 // پیش‌نمایش برگشت از دیوار
 {let rx=ux,ry=uy,hit=false;const eps=2;if(ex<=F.l+b.r+eps&&ux<0){rx=-ux;hit=true}else if(ex>=F.r-b.r-eps&&ux>0){rx=-ux;hit=true}else if(ey<=F.t+b.r+eps&&uy<0){ry=-uy;hit=true}else if(ey>=F.b-b.r-eps&&uy>0){ry=-uy;hit=true}
  if(hit){const gg=ctx.createLinearGradient(ex,ey,ex+rx*170,ey+ry*170);gg.addColorStop(0,'rgba(255,255,255,.55)');gg.addColorStop(1,'rgba(255,255,255,0)');ctx.globalAlpha=1;ctx.strokeStyle=gg;ctx.lineWidth=3;ctx.setLineDash([8,10]);ctx.lineDashOffset=-now/30;ctx.beginPath();ctx.moveTo(ex,ey);ctx.lineTo(ex+rx*170,ey+ry*170);ctx.stroke();ctx.setLineDash([])}}
 // نقطهٔ برخورد: حلقهٔ ضربانی + نشانه‌گیر
 {const pu=.5+.5*Math.sin(now/140),R=b.r*(1+.12*pu);ctx.globalAlpha=.9;ctx.strokeStyle=col2;ctx.lineWidth=3.5;ctx.beginPath();ctx.arc(ex,ey,R,0,7);ctx.stroke();
  ctx.globalAlpha=.5+.4*pu;ctx.lineWidth=2.5;for(let k=0;k<4;k++){const a=k*1.5708+now/700,ca=Math.cos(a),sa=Math.sin(a);ctx.beginPath();ctx.moveTo(ex+ca*(R+4),ey+sa*(R+4));ctx.lineTo(ex+ca*(R+13),ey+sa*(R+13));ctx.stroke()}
  ctx.globalAlpha=.25;ctx.fillStyle=col;ctx.beginPath();ctx.arc(ex,ey,R*.55,0,7);ctx.fill()}
 // حلقهٔ قدرت: ۳۰ قطعه
 {const N=30,r0=b.r+13,r1=b.r+20;ctx.lineWidth=4;for(let k=0;k<N;k++){const a0=-1.5708+k/N*6.2832+.03,lit=k/N<p;ctx.globalAlpha=lit?1:.18;ctx.strokeStyle=lit?'hsl('+(135-135*(k/N))+',95%,58%)':'#fff';ctx.beginPath();ctx.arc(b.x,b.y,r1,a0,a0+6.2832/N-.07);ctx.stroke()}}
 // فلش اصلی نئونی: شفت مخروطی + سر تیز + دم دوگانه
 {const base=b.r+30,Lh=34+p*92,hl=24+p*16,sw=3.5+p*5,hw=14+p*9,tipx=b.x+ux*(base+Lh),tipy=b.y+uy*(base+Lh),nx=-uy,ny=ux,bx=b.x+ux*base,by=b.y+uy*base,jx=b.x+ux*(base+Lh-hl),jy=b.y+uy*(base+Lh-hl);
  const fg=ctx.createLinearGradient(bx,by,tipx,tipy);fg.addColorStop(0,'rgba(255,255,255,.15)');fg.addColorStop(.55,col);fg.addColorStop(1,'#fff');
  ctx.globalAlpha=1;ctx.shadowColor=col;ctx.shadowBlur=22;ctx.fillStyle=fg;
  ctx.beginPath();ctx.moveTo(bx+nx*sw*.3,by+ny*sw*.3);ctx.lineTo(jx+nx*sw,jy+ny*sw);ctx.lineTo(jx+nx*hw,jy+ny*hw);ctx.lineTo(tipx,tipy);ctx.lineTo(jx-nx*hw,jy-ny*hw);ctx.lineTo(jx-nx*sw,jy-ny*sw);ctx.lineTo(bx-nx*sw*.3,by-ny*sw*.3);ctx.closePath();ctx.fill();
  ctx.shadowBlur=0;ctx.strokeStyle='rgba(255,255,255,.9)';ctx.lineWidth=1.8;ctx.stroke();
  // دو شورونِ دنبالهٔ فلش که با قدرت بیشتر میشن
  const n=1+(p>.35)+(p>.7);ctx.lineWidth=3.5;for(let k=1;k<=n;k++){const d=base-k*13,x=b.x+ux*d,y=b.y+uy*d;ctx.globalAlpha=.75/k;ctx.strokeStyle=col2;ctx.beginPath();ctx.moveTo(x-uy*(10+p*5)-ux*7,y+ux*(10+p*5)-uy*7);ctx.lineTo(x+ux*2,y+uy*2);ctx.lineTo(x+uy*(10+p*5)-ux*7,y-ux*(10+p*5)-uy*7);ctx.stroke()}
  // درصد قدرت
  ctx.globalAlpha=1;ctx.fillStyle='#fff';ctx.font='900 17px system-ui,sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';ctx.shadowColor=col;ctx.shadowBlur=10;ctx.fillText(Math.round(p*100)+'%',b.x-ux*(b.r+44)+nx*0,b.y-uy*(b.r+44)-(uy>.5?-4:0));ctx.shadowBlur=0}
 ctx.restore()}
function draw(){const W=canvas.width,H=canvas.height,now=performance.now();ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,W,H);
  const cs=cam*cam*9,cx=(Math.random()-.5)*cs,cy=(Math.random()-.5)*cs;ctx.setTransform(Sx,0,0,Sx,Rx+cx*Sx,Ry+cy*Sx);
 drawTrail(now);
 {ctx.save();ctx.globalCompositeOperation='lighter';ctx.lineCap='round';for(const b of bodies){if(b===ball||!b.tr||b.tr.length<3)continue;const T=b.tr,n=T.length,rgb=b.team?'255,90,90':'70,160,255',q=Math.min(1,T[n-1].v/(1500*K));for(let i=1;i<n;i++){const f=i/n;ctx.strokeStyle='rgba('+rgb+','+(f*.5*(.4+.6*q))+')';ctx.lineWidth=b.r*1.7*f;ctx.beginPath();ctx.moveTo(T[i-1].x,T[i-1].y);ctx.lineTo(T[i].x,T[i].y);ctx.stroke()}for(let i=1;i<n;i++){const f=i/n;ctx.strokeStyle='rgba(255,255,255,'+(f*.35*q)+')';ctx.lineWidth=b.r*.35*f;ctx.beginPath();ctx.moveTo(T[i-1].x,T[i-1].y);ctx.lineTo(T[i].x,T[i].y);ctx.stroke()}}ctx.restore()}
 if(SPR.shadow)for(const b of bodies){const w=b.r*2.6;ctx.drawImage(SPR.shadow,b.x-w/2+5,b.y-w/2+11,w,w)}
 for(const b of bodies)if(b!==ball)sprite(b);if(ball)sprite(ball);
 GOALS.forEach((g,i)=>{const sp=SPR.goal&&SPR.goal[i];if(!sp)return;const gx=GG.x+Math.sin(now/25)*8*shake[g.team];const gy=g.d<0?g.y-GG.h-2:g.y+2;ctx.drawImage(sp,gx,gy,GG.w,GG.h)});
 drawParts();
 if(rings.length){ctx.save();ctx.globalCompositeOperation='lighter';for(const r of rings){const t=1-r.l/r.m;ctx.globalAlpha=(1-t)*.8*r.w;ctx.strokeStyle='#fff';ctx.lineWidth=6*(1-t)+1;ctx.beginPath();ctx.arc(r.x,r.y,r.r*(1+t*3.2*(.6+r.w)),0,7);ctx.stroke()}ctx.restore()}
 aim();
 if(flash>0){ctx.setTransform(1,0,0,1,0,0);ctx.fillStyle='rgba(255,230,140,'+flash*.35+')';ctx.fillRect(0,0,W,H)}}
// ---------- حلقهٔ اصلی ----------
function end(){sfx('fin');phase='over';stat();E.emit('end',{score:[score[ct(0)],score[ct(1)]],local:score.slice()})}
function restart(k){score=[0,0];$('s1').textContent=$('s2').textContent='0';reset(ct(k||0))}
let fr=0;const busy=()=>phase!=='aim'||drag||parts.length||rings.length||trail.length||flash>.01||cam>.01||shake[0]>0||shake[1]>0||C.tt>0;
let mleft=0,sd=false,aiT=0,aiPlan=null,tleft=0,remote=false,fxAcc=0,fxAcc2=0,menuHold=false;
const canCtl=()=>!menuOpen&&phase==='aim'&&!remote&&turn!==C.ai&&!(C.mode==='online'&&turn!==0);
function launch(b,vx,vy,fromRemote){b.vx=vx;b.vy=vy;b.boost=.22;if(b.team!==turn)turn=b.team;phase='move';idle=0;shots++;remote=!!fromRemote;drag=null;stat();
 tone(330,.05,'triangle',.12,190);cam=Math.max(cam,.18)}
function fire(b,dx,dy,l){const p=Math.min(l,LMAX)/LMAX;let v=(260+1085*Math.pow(p,.8))*K*1.32;if(T(sel[ct(b.team)]).cat==='vip')v*=1.16;const vx=dx/l*v,vy=dy/l*v;launch(b,vx,vy,false);
 const sg=C.mirror?-1:1;E.emit('shot',{cid:b.cid,vx:vx*sg,vy:vy*sg,team:ct(b.team)})}
function finishTurn(emitSnap){turn=1-turn;phase='aim';tleft=C.tt;remote=false;aiT=0;aiPlan=null;stat();
 if(emitSnap&&C.mode==='online')E.emit('settled',{snap:snapshot()});E.emit('turn',{turn:ct(turn),mine:turn===0})}
function skipTurn(){if(phase!=='aim')return;drag=null;aiPlan=null;toast('Time up');finishTurn(false)}
function snapshot(){const m=C.mirror,f=(x,y)=>m?[2*CX-x,2*CY-y]:[x,y];return{b:bodies.map(b=>{const p=f(b.x,b.y);return[b.cid,+p[0].toFixed(1),+p[1].toFixed(1)]}),sc:[score[ct(0)],score[ct(1)]],tn:ct(turn)}}
function applySnapshot(s){if(!s||!s.b)return;const m=C.mirror;for(const[cid,x,y]of s.b){const b=bodies.find(o=>o.cid===cid);if(!b)continue;b.x=m?2*CX-x:x;b.y=m?2*CY-y:y;b.vx=b.vy=0}}
// ---------- turn timer + AI ----------
function mclk(){const e=$('mclk');if(!e)return;if(!(C.mt>0)){e.textContent='';return}if(sd){e.textContent='GOLDEN';e.classList.add('sd');return}e.classList.remove('sd');const t=Math.max(0,Math.ceil(mleft));e.textContent=Math.floor(t/60)+':'+String(t%60).padStart(2,'0');e.classList.toggle('low',t<=30)}
function timeCheck(){if(!(C.mt>0)||sd||mleft>0)return;if(score[0]!==score[1]){end()}else{sd=true;mclk();toast('Golden goal!');sfx('whs')}}
function tick(dt){
 if(phase==='aim')timeCheck();
 if(C.tt>0){tleft-=dt;const tm=$('tmr');if(tm){tm.style.setProperty('--p',Math.max(0,tleft/C.tt).toFixed(3));tm.firstElementChild.textContent=Math.max(0,Math.ceil(tleft));tm.classList.toggle('low',tleft<5)}
  if(tleft<=0){if(C.mode==='online'){if(turn===0){E.emit('timeout',{team:ct(0)});skipTurn()}else if(tleft<-4)skipTurn()}else skipTurn();return}}
 if(turn===C.ai)aiTick(dt)}
function aiTick(dt){if(phase!=='aim')return;
 if(!aiPlan){aiT+=dt;if(aiT<.7+Math.random()*.7)return;aiPlan=aiDecide();if(!aiPlan)return;aiPlan.t=0;drag={b:aiPlan.b,s:{x:aiPlan.b.x,y:aiPlan.b.y},c:{x:aiPlan.b.x,y:aiPlan.b.y},ai:true};return}
 aiPlan.t+=dt;const k=Math.min(1,aiPlan.t/.75),e=k*k*(3-2*k);drag.c={x:aiPlan.b.x-aiPlan.dx*aiPlan.l*e,y:aiPlan.b.y-aiPlan.dy*aiPlan.l*e};
 if(k>=1){const p=aiPlan;drag=null;aiPlan=null;fire(p.b,p.dx*p.l,p.dy*p.l,p.l)}}
function segDist(px,py,ax,ay,bx,by){const vx=bx-ax,vy=by-ay,l2=vx*vx+vy*vy||1;let t=((px-ax)*vx+(py-ay)*vy)/l2;t=Math.max(0,Math.min(1,t));return Math.hypot(px-(ax+vx*t),py-(ay+vy*t))}
function gauss(){return(Math.random()+Math.random()+Math.random()-1.5)*1.15}
function aiDecide(){const me=turn,mine=bodies.filter(b=>b.team===me&&b!==ball),tg=GOALS[me],og=GOALS[1-me],lvl=C.aiLvl|0,sg=[.14,.06,.016][lvl],gw=(tg.x2-tg.x1)/2,cands=[];
 const clear=(p,x,y,skip)=>{for(const o of bodies){if(o===p||o===ball||o===skip)continue;if(segDist(o.x,o.y,p.x,p.y,x,y)<p.r+o.r-6)return false}return true};
 for(const p of mine){
  for(const ox of[-.55,0,.55]){const Tx=CX+ox*gw,Ty=tg.y;let ux=Tx-ball.x,uy=Ty-ball.y;const ul=Math.hypot(ux,uy)||1;ux/=ul;uy/=ul;
   const cx=ball.x-ux*(p.r+ball.r+1),cy=ball.y-uy*(p.r+ball.r+1);let vx=cx-p.x,vy=cy-p.y;const dist=Math.hypot(vx,vy);if(dist<8)continue;vx/=dist;vy/=dist;
   const al=vx*ux+vy*uy;if(al<.2)continue;if(!clear(p,cx,cy))continue;
   let blk=0;for(const o of bodies){if(o.team===me||o===ball)continue;if(segDist(o.x,o.y,ball.x,ball.y,Tx,Ty)<ball.r+o.r+6)blk++}
   cands.push({p,dx:vx,dy:vy,sc:100*al-dist*.03-blk*28+(Math.abs(ball.y-Ty)<420?25:0),dist,atk:1})}
  let vx=ball.x-p.x,vy=ball.y-p.y;const dist=Math.hypot(vx,vy);if(dist>8){vx/=dist;vy/=dist;if(clear(p,ball.x,ball.y)){const toOwn=(vy*(og.y-ball.y)>0)?Math.abs(vy):0;cands.push({p,dx:vx,dy:vy,sc:10-dist*.04-toOwn*55,dist,atk:0})}}}
 if(!cands.length){const p=mine.slice().sort((a,b)=>Math.hypot(a.x-ball.x,a.y-ball.y)-Math.hypot(b.x-ball.x,b.y-ball.y))[0];if(!p)return null;let vx=ball.x-p.x,vy=ball.y-p.y;const d=Math.hypot(vx,vy)||1;cands.push({p,dx:vx/d,dy:vy/d,sc:0,dist:d,atk:0})}
 cands.sort((a,b)=>b.sc-a.sc);const pool=cands.slice(0,[4,2,1][lvl]),c=pool[Math.floor(Math.random()*pool.length)];
 const ang=Math.atan2(c.dy,c.dx)+gauss()*sg;let pw=lvl===2?Math.min(1,.66+c.dist/1000):Math.min(1,.5+c.dist/1100);if(lvl===0)pw*=.7+Math.random()*.3;if(c.atk&&lvl>0)pw=Math.max(pw,.78);
 return{b:c.p,dx:Math.cos(ang),dy:Math.sin(ang),l:Math.max(.3,pw)*LMAX}}
// ---------- visuals: per-ball light trail + per-pitch accents ----------
const TR=[{k:'bolt',c:['#19b4ff','#8fe6ff','#ffffff']},{k:'prism',c:['#ff7bd5','#7bd7ff','#ffffff']},{k:'wave',c:['#2fe0d0','#9ff7ef','#ffffff']},{k:'star',c:['#5cb6ff','#bfe3ff','#ffffff']},
 {k:'smoke',c:['#e8ecf2','#9aa3b0','#ffffff']},{k:'rainbow',c:['#ff5b5b','#ffd23a','#5bff8a','#5bd0ff','#c05bff']},{k:'neon',c:['#4dff2a','#b6ff9a','#ffffff']},{k:'yin',c:['#ffffff','#9b5cff','#000000']},
 {k:'fire',c:['#ff8a1f','#ffd24a','#fff3c4']},{k:'blade',c:['#ff2b3a','#ff8a92','#ffffff']},{k:'ghost',c:['#dbe7ff','#8fb0ff','#ffffff']},{k:'ember',c:['#ff6a1f','#ffb347','#fff0c8']},{k:'plasma',c:['#2f8bff','#7fc6ff','#ffffff']},
 {k:'ghost',c:['#d9915b','#f2c9a0','#fff4e6']},{k:'star',c:['#2f7bff','#8fd0ff','#ffffff']},{k:'wave',c:['#9b5cff','#e0b8ff','#ffffff']},{k:'fire',c:['#e0a82e','#ffe08a','#fff7d6']},{k:'bolt',c:['#2f6bff','#7fb4ff','#ffffff']},
 {k:'neon',c:['#2f8bff','#e8b84a','#ffffff']},{k:'prism',c:['#1fd6a0','#3b9bff','#ffffff']},{k:'blade',c:['#ff2b3a','#ff8a92','#ffffff']},{k:'plasma',c:['#18d8c0','#9ff5e6','#ffffff']},{k:'ember',c:['#2f5bff','#ffc83a','#fff3c4']},
 {k:'yin',c:['#ffffff','#e0a82e','#000000']},{k:'smoke',c:['#ff4a4a','#9aa3b0','#ffffff']},{k:'star',c:['#e0a82e','#fff0b0','#ffffff']},
 {k:'plasma',c:['#2f8bff','#c0c8d8','#ffffff']},{k:'ghost',c:['#9b5cff','#ffffff','#ffffff']},{k:'neon',c:['#4dff2a','#c0c8d8','#ffffff']},{k:'blade',c:['#e8b84a','#2f6bff','#ffffff']},{k:'fire',c:['#ff2b3a','#ff8a92','#ffffff']},{k:'ember',c:['#ff8a1f','#ffd24a','#ffffff']},{k:'wave',c:['#3b9bff','#2fe08a','#ffffff']},{k:'prism',c:['#ff4a7a','#9b5cff','#ffffff']},{k:'bolt',c:['#2f6bff','#ffffff','#ffffff']},{k:'star',c:['#ffd56b','#ffffff','#ffffff']}];
const TRN=['Bolt','Prism','Wave','Starlight','Smoke','Rainbow','Neon','Yin','Fire','Blade','Ghost','Ember','Plasma','Copper Ghost','Stardust','Twilight','Gold Flame','Thunder','Cobalt Neon','Aurora','Crimson Blade','Teal Storm','Royal Ember','Gold Yin','Red Smoke','Gilded Star','Noir Chrome','Violet Strike','Emerald Edge','Royal Blue Gold','Crimson Noir','Blaze Orange','Aqua Wave','Sunset Pro','Elite Cobalt','Crown Luxury'];
const BALLN=['Bolt','Prism','Wave','Starlight','Classic','Rainbow','Neon','Yin','Fire','Blade','Ghost','Ember','Plasma','Noir Copper','Space Modern','Purple Sky','Black Lux','Electron','Cobalt Gold','Aurora','Crimson','Teal Storm','Royal Gold','Gold Rush','Classic Red','Luxury','Noir Chrome','Violet Strike','Emerald Edge','Royal Blue Gold','Crimson Noir','Blaze Orange','Aqua Wave','Sunset Pro','Elite Cobalt','Crown Luxury'];
const ballName=i=>BALLN[i]+' Ball';
const FA={forest:{k:2,c:['#6fd36b','#b8f5a0','#2e8b3a'],g:130},ice:{k:1,c:['#e8fbff','#9fe8ff','#ffffff'],g:30},ocean:{k:4,c:['#bff3ff','#5cd0ff','#ffffff'],g:-140},street:{k:5,c:['#ff2bd6','#ffe14a','#2bf0ff'],g:0},
 streetarena:{k:5,c:['#ffb02b','#ff3b6b','#ffffff'],g:0},lava:{k:0,c:['#ff5a1f','#ffb347','#ffe08a'],g:-220},stadium:{k:1,c:['#ffd86b','#ffffff','#ffe9a8'],g:0},checker:{k:3,c:['#ffffff','#9aa3b0','#ff4040'],g:0},
 futsal:{k:5,c:['#ffcf8a','#ffffff','#ffa14a'],g:0},arena:{k:5,c:['#7fb8ff','#ffffff','#3b7bff'],g:0},arena2:{k:1,c:['#c79bff','#ffffff','#7b4bff'],g:0},desert:{k:0,c:['#e8c689','#c99a54','#fff0c8'],g:60},
 grove:{k:0,c:['#d8ff6a','#ffffa0','#9cf06a'],g:-30},pool:{k:0,c:['#9fe9ff','#e6fbff','#4cc7ff'],g:380},
 neon:{k:5,c:['#7dff3a','#d6ff9a','#ffffff'],g:0},royal:{k:1,c:['#ffd86b','#fff3c4','#ff9a3a'],g:0},mahogany:{k:1,c:['#ffcf8a','#fff0c8','#d9923a'],g:-20},leather:{k:0,c:['#d9a066','#ffd9a0','#8a5a2a'],g:-30},
 aqua:{k:4,c:['#bff3ff','#5cd0ff','#ffffff'],g:-150},asphalt:{k:5,c:['#ffe14a','#ffffff','#ffb02b'],g:0},court:{k:5,c:['#ffffff','#ffcf8a','#4aa8ff'],g:0},cyberbox:{k:5,c:['#ff3b3b','#3b8bff','#ffffff'],g:0},realmadrid:{k:1,c:['#ffffff','#ffd86b','#3b6bff'],g:0},psg:{k:5,c:['#ff2b3a','#3b6bff','#ffffff'],g:0},acmilan:{k:5,c:['#ff2b3a','#ffffff','#111111'],g:0},barcelona:{k:5,c:['#ff2b5a','#3b6bff','#ffd86b'],g:0},persepolis:{k:5,c:['#ff2b3a','#ffd86b','#ffffff'],g:0},esteghlal:{k:1,c:['#3b8bff','#ffffff','#ffd86b'],g:0},mancity:{k:1,c:['#7fd0ff','#ffffff','#3b8bff'],g:0}};
const bcol=()=>(TR[SET.ball%TR.length]||TR[0]).c;
const hsl=(h,l)=>'hsl('+(((h%360)+360)%360|0)+',100%,'+(l||60)+'%)';
function fx(dt){if(ball){ball.vz=0;ball.hz=0}for(const b of bodies)if(b!==ball){const sp=Math.hypot(b.vx,b.vy);b.tr=b.tr||[];if(sp>140*K)b.tr.push({x:b.x,y:b.y,v:sp});else if(b.tr.length)b.tr.shift();if(b.tr.length>14)b.tr.shift();if(sp>420*K&&Math.random()<dt*34&&parts.length<300){const ux=b.vx/sp,uy=b.vy/sp,o=(Math.random()-.5)*b.r*1.6;spawn(b.x-ux*b.r*.8-uy*o,b.y-uy*b.r*.8+ux*o,-ux*260,-uy*260,.22,2.2,b.team?'#ff9a9a':'#9fd0ff',5)}}
for(const b of bodies)if(b!==ball&&b.sq)b.sq=b.sq>.02?b.sq-dt*5:0;if(ball&&phase!=='over'){const sp=Math.hypot(ball.vx,ball.vy);if(sp>350*K)trail.push({x:ball.x,y:ball.y,a:1,h:sp>1250*K,v:sp});
 if(sp>300*K&&!menuOpen){const f=Math.min(1,sp/(2300*K)),st=TR[SET.ball%TR.length]||TR[0],c=st.c,fa=FA[FIELDS[SET.fld].id]||FA.stadium,bx=ball.x,by=ball.y,ux=ball.vx/sp,uy=ball.vy/sp,R=()=>Math.random();
  fxAcc+=dt*(26+70*f);while(fxAcc>=1){fxAcc--;const o=(R()-.5)*BR*1.4,px=bx-ux*BR*.6-uy*o,py=by-uy*BR*.6+ux*o,sx=(R()-.5)*260-ux*120,sy=(R()-.5)*260-uy*120;
   switch(st.k){case'bolt':spawn(px,py,sx*1.6,sy*1.6,.28,2.2,R()<.5?c[1]:c[2],5);break;case'prism':spawn(px,py,sx*.4,sy*.4,.5,4+R()*3,hsl(R()*360,65),0);break;
    case'wave':spawn(px,py,sx*.3,sy*.3-40,.6,3+R()*3,c[R()<.5?0:1],4,-60);break;case'star':spawn(px,py,sx*.4,sy*.4,.7,5+R()*6,R()<.4?c[2]:c[1],1);break;
    case'smoke':break;case'rainbow':spawn(px,py,sx*.5,sy*.5,.6,3+R()*3,hsl(R()*360,62),3,60);break;case'neon':spawn(px,py,sx*.5,sy*.5,.45,3+R()*3,R()<.5?c[0]:c[1],3);break;
    case'yin':spawn(px,py,sx*.4,sy*.4,.55,3+R()*4,R()<.5?'#ffffff':'#a066ff',0);break;case'fire':spawn(px,py,sx*.35,sy*.35-90,.55,6+R()*7,c[R()<.5?0:1],2,-260);break;
    case'blade':spawn(px,py,-ux*600+sx*.2,-uy*600+sy*.2,.22,2.2,c[R()<.5?0:1],5);break;case'ghost':if(R()<.3)spawn(px,py,sx*.2,sy*.2,.7,4,c[1],1);break;
    case'ember':spawn(px,py,sx*.5,sy*.5-60,.8,2.5+R()*2.5,c[R()<.5?0:1],0,-150);break;case'plasma':{const a=R()*6.28;spawn(px+Math.cos(a)*12,py+Math.sin(a)*12,Math.cos(a)*90+sx*.2,Math.sin(a)*90+sy*.2,.45,3+R()*3,c[R()<.5?0:1],0)}break}}
  fxAcc2+=dt*(14+44*f);while(fxAcc2>=1){fxAcc2--;const o=(R()-.5)*BR*2.4,px=bx-ux*BR-uy*o,py=by-uy*BR+ux*o;spawn(px,py,(R()-.5)*150,(R()-.5)*150,.55+R()*.5,(fa.k===0?2.2:4)+R()*4,fa.c[(R()*fa.c.length)|0],fa.k,fa.g)}}}}
function drawParts(){if(!parts.length)return;ctx.save();ctx.globalCompositeOperation='lighter';
 for(const p of parts){const a=Math.max(0,p.l/p.m);ctx.globalAlpha=a;ctx.fillStyle=ctx.strokeStyle=p.c;const r=p.r*(p.k===4?1:(.5+.5*a));
  switch(p.k||0){
   case 1:{ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.rot);ctx.beginPath();const q=r*1.8;ctx.moveTo(0,-q);ctx.quadraticCurveTo(0,0,q,0);ctx.quadraticCurveTo(0,0,0,q);ctx.quadraticCurveTo(0,0,-q,0);ctx.quadraticCurveTo(0,0,0,-q);ctx.fill();ctx.restore();break}
   case 2:{ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.rot);ctx.beginPath();ctx.ellipse(0,0,r*1.5,r*.7,0,0,7);ctx.fill();ctx.restore();break}
   case 3:{ctx.save();ctx.translate(p.x,p.y);ctx.rotate(p.rot);ctx.fillRect(-r,-r,r*2,r*2);ctx.restore();break}
   case 4:ctx.lineWidth=1.8;ctx.beginPath();ctx.arc(p.x,p.y,r*(1.4-a*.4),0,7);ctx.stroke();break;
   case 5:{const l=Math.hypot(p.vx,p.vy)||1,k=Math.min(26,l*.07);ctx.lineWidth=Math.max(1,r*.8);ctx.lineCap='round';ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(p.x-p.vx/l*k,p.y-p.vy/l*k);ctx.stroke();break}
   default:ctx.beginPath();ctx.arc(p.x,p.y,r,0,7);ctx.fill()}}
 ctx.restore()}
function drawTrail(now){const n=trail.length;if(n<2)return;const st=TR[SET.ball%TR.length]||TR[0],c=st.c,BW=BR,fa=FA[FIELDS[SET.fld].id]||FA.stadium;
 ctx.save();ctx.globalCompositeOperation='lighter';ctx.lineCap=ctx.lineJoin='round';
 const seg=(i,w,al,col,ox,oy)=>{const p=trail[i-1],q=trail[i];ctx.globalAlpha=Math.max(0,Math.min(1,al*q.a));ctx.strokeStyle=col;ctx.lineWidth=Math.max(.6,w*q.a);ctx.beginPath();ctx.moveTo(p.x+(ox||0),p.y+(oy||0));ctx.lineTo(q.x+(ox||0),q.y+(oy||0));ctx.stroke()};
 const nrm=i=>{const p=trail[Math.max(0,i-1)],q=trail[Math.min(n-1,i)];const dx=q.x-p.x,dy=q.y-p.y,l=Math.hypot(dx,dy)||1;return[-dy/l,dx/l]};
 const base=(w0,a0)=>{for(let i=1;i<n;i++){seg(i,BW*2.2*w0,.14*a0,c[0]);seg(i,BW*1.1*w0,.42*a0,c[1]);seg(i,BW*.4*w0,.95*a0,c[2]||'#fff')}};
 switch(st.k){
  case'bolt':{base(.55,.8);for(const[w,col,al]of[[4.2,c[1],.55],[1.7,c[2],.95]]){ctx.lineWidth=w;ctx.strokeStyle=col;ctx.globalAlpha=al;ctx.beginPath();let m=0;for(let i=0;i<n;i++){const q=trail[i];if(q.a<.12)continue;const[nx,ny]=nrm(i),a=(Math.sin(i*91.7+now*.07+w)*BW*1.1)*q.a;if(!m++)ctx.moveTo(q.x+nx*a,q.y+ny*a);else ctx.lineTo(q.x+nx*a,q.y+ny*a)}ctx.stroke()}break}
  case'prism':for(let i=1;i<n;i++){seg(i,BW*1.9,.4,hsl(i*14+now*.25,58));seg(i,BW*.9,.7,hsl(i*14+now*.25+40,70));seg(i,BW*.32,.95,'#fff')}break;
  case'wave':base(.4,.7);for(let i=1;i<n;i++){const[nx,ny]=nrm(i),o=Math.sin(i*.55+now*.02)*BW*1.0*trail[i].a;seg(i,BW*.55,.85,c[0],nx*o,ny*o);seg(i,BW*.55,.85,c[1],-nx*o,-ny*o)}break;
  case'star':base(.7,.9);break;
  case'smoke':{ctx.globalCompositeOperation='source-over';ctx.fillStyle=c[1];for(let i=0;i<n;i+=2){const q=trail[i],g=1-q.a;ctx.globalAlpha=q.a*.2;ctx.beginPath();ctx.arc(q.x+Math.sin(i*3.1)*g*14,q.y+Math.cos(i*2.7)*g*14,BW*(.9+g*2.4),0,7);ctx.fill()}ctx.globalCompositeOperation='lighter';for(let i=1;i<n;i++)seg(i,BW*.45,.7,c[2]);break}
  case'rainbow':for(let b=0;b<6;b++)for(let i=1;i<n;i++){const[nx,ny]=nrm(i),o=(b-2.5)*BW*.34*trail[i].a;seg(i,BW*.42,.8,hsl(b*60,60),nx*o,ny*o)}break;
  case'neon':for(let i=1;i<n;i++){seg(i,BW*1.9,.2,c[0]);seg(i,BW*.75,.9,c[1]);seg(i,BW*.24,1,c[2])}break;
  case'yin':for(let i=1;i<n;i++){const[nx,ny]=nrm(i),o=Math.sin(i*.42+now*.016)*BW*.85*trail[i].a;seg(i,BW*.7,.9,c[0],nx*o,ny*o);seg(i,BW*.7,.85,c[1],-nx*o,-ny*o);seg(i,BW*1.8,.1,c[1])}break;
  case'fire':for(let i=1;i<n;i++){seg(i,BW*2.2,.22,c[0]);seg(i,BW*1.2,.55,c[1]);seg(i,BW*.45,.95,c[2])}break;
  case'blade':{ctx.globalAlpha=.75;ctx.fillStyle=c[0];ctx.beginPath();let first=true;const R=[];for(let i=0;i<n;i++){const[nx,ny]=nrm(i),w=BW*1.5*Math.pow(i/(n-1),1.3)*trail[i].a;if(first){ctx.moveTo(trail[i].x+nx*w,trail[i].y+ny*w);first=false}else ctx.lineTo(trail[i].x+nx*w,trail[i].y+ny*w);R.push([trail[i].x-nx*w,trail[i].y-ny*w])}for(let i=n-1;i>=0;i--)ctx.lineTo(R[i][0],R[i][1]);ctx.closePath();ctx.fill();for(let i=1;i<n;i++)seg(i,BW*.3,.95,c[2]);break}
  case'ghost':for(let i=1;i<n;i++)seg(i,BW*.5,.5,c[1]);for(let i=0;i<n;i+=4){const q=trail[i];ctx.globalAlpha=q.a*.4;ctx.strokeStyle=c[1];ctx.fillStyle=c[0];ctx.lineWidth=3;ctx.beginPath();ctx.arc(q.x,q.y,BR*(.6+.4*q.a),0,7);ctx.stroke();ctx.globalAlpha=q.a*.08;ctx.fill()}break;
  case'ember':for(let i=1;i<n;i++){seg(i,BW*1.2,.2,c[0]);seg(i,BW*.55,.6,c[1]);seg(i,BW*.2,1,c[2])}break;
  case'plasma':for(let i=1;i<n;i++){const k=1+.3*Math.sin(now*.03+i*.35),[nx,ny]=nrm(i),o=Math.sin(i*.5-now*.025)*BW*.5*trail[i].a;seg(i,BW*2.8*k,.2,c[0]);seg(i,BW*1.4*k,.5,c[1]);seg(i,BW*.45,1,c[2]);seg(i,BW*.3,.7,c[1],nx*o,ny*o)}break}
 for(let i=1;i<n;i++)seg(i,BW*.8,.2,fa.c[0]); // pitch-tinted undertone
 const last=trail[n-1];if(last&&last.v>1800*K){const ux=ball.vx/last.v,uy=ball.vy/last.v;ctx.lineWidth=2;ctx.strokeStyle=c[1];for(let k=-1;k<=1;k+=1){ctx.globalAlpha=.35;ctx.beginPath();ctx.moveTo(ball.x-ux*BR*1.4-uy*k*BR*.9,ball.y-uy*BR*1.4+ux*k*BR*.9);ctx.lineTo(ball.x-ux*BR*7-uy*k*BR*.9,ball.y-uy*BR*7+ux*k*BR*.9);ctx.stroke()}}
 ctx.restore()}
function loop(t){const dt=Math.min((t-last)/1000||.016,.05);last=t;
 if(!menuOpen&&bodies.length){if(C.mt>0&&!sd&&phase!=='over'&&mleft>0){mleft=Math.max(0,mleft-dt);mclk()}let ts=1;if(freeze>0){freeze-=dt;ts=0}else if(slow>0){slow-=dt;ts=.32+.68*Math.pow(1-Math.max(0,slow)/1.1,2)}acc+=dt*ts;let n=0;
  if(phase!=='over'){while(acc>=STEP&&n++<14){sim(STEP);acc-=STEP}if(n>14)acc=0}
  if(phase==='move'){idle=bodies.some(b=>b.vx||b.vy)?0:idle+dt;if(idle>.25){if(!remote)finishTurn(true);else if(idle>3)finishTurn(false)}}
  else if(phase==='aim')tick(dt);
  else if(phase==='goal'){pause-=dt;if(pause<=0){if(C.mt>0){if(sd||(mleft<=0&&score[0]!==score[1]))end();else{if(mleft<=0)sd=true;mclk();reset(kick)}}else if(score[0]>=SET.lim||score[1]>=SET.lim)end();else reset(kick)}}
  fx(dt)}
 flash=Math.max(0,flash-dt*2);cam=Math.max(0,cam-dt*3.2);for(const r of rings)r.l-=dt;rings=rings.filter(r=>r.l>0);shake[0]=Math.max(0,shake[0]-dt);shake[1]=Math.max(0,shake[1]-dt);
 {let k=0;for(let i=0;i<trail.length;i++){const p=trail[i];p.a-=dt*3;if(p.a>0)trail[k++]=p}trail.length=k}
 {let k=0;for(let i=0;i<parts.length;i++){const p=parts[i];p.x+=p.vx*dt;p.y+=p.vy*dt;p.vx*=.97;p.vy=p.vy*.97+(p.g||0)*dt;p.rot+=dt*4;p.l-=dt;if(p.l>0)parts[k++]=p}parts.length=k}
 if(!menuOpen&&(busy()||(fr++&1)))draw();requestAnimationFrame(loop)}
// ---------- public API ----------
function startMatch(cfg){setTimeout(()=>sfx('whs'),250);C={mode:cfg.mode||'local',names:cfg.names||['',''],mirror:!!cfg.mirror,ai:cfg.ai?1:-1,aiLvl:cfg.aiLvl==null?1:cfg.aiLvl,tt:cfg.turnTime||0,mt:cfg.matchTime|0};mleft=C.mt;sd=false;
 sel=cfg.teams.slice();form=(cfg.form||[0,0]).slice();SET.fld=cfg.field|0;SET.ball=cfg.ball|0;SET.lim=cfg.matchTime>0?9999:(cfg.limit||5);
 geo();SPR.goal=null;loadAll();ui();build();score=[0,0];$('s1').textContent=$('s2').textContent='0';$('toast').classList.remove('show');
 reset(ct(cfg.first||0));inMatch=true;menuOpen=false;musicSync();draw()}
function setMenuOpen(v){menuOpen=!!v;musicSync();if(!menuOpen){build();draw()}}
function preview(i,j){SET.fld=i;SET.ball=j}
window.NexoraGame={SET,FIELDS,TEAMS,CATS,FORMS,NB,TR,TRN,ballName,FA,T,catOf,slots,startMatch,setMenuOpen,musicSync,sfx,vib,toast,loadSnd,E,VIP_PRICES,VIP_FREE,isVip,vipPrice,
 restart:k=>{restart(k);$('toast').classList.remove('show')},stop(){inMatch=false;phase='over';bodies=[];menuOpen=true;musicSync()},
 remoteShot(m){const b=bodies.find(o=>o.cid===m.cid);if(!b)return;const sg=C.mirror?-1:1;launch(b,m.vx*sg,m.vy*sg,true)},
 remoteSettled(m){if(phase!=='move'&&phase!=='aim')return;applySnapshot(m.snap);finishTurn(false)},
 remoteGoal(m){if(phase==='move'||phase==='aim')scored(ct(m.team),true)},
 remoteTimeout(){skipTurn()},syncClock(sec){if(C.mt>0&&!sd&&Math.abs(mleft-sec)>1.2){mleft=Math.max(0,sec);mclk()}},snapshot,applySnapshot,
 get active(){return inMatch&&phase!=='over'},get phase(){return phase},get score(){return score.slice()},get turn(){return turn},get shots(){return shots},
 bodies:()=>bodies,resize:()=>build(),toScreen:(x,y)=>({x:x*s+ox,y:y*s+oy}),debugSet:o=>{if(o.ball)ball&&Object.assign(ball,o.ball)}};

// ---------- ورودی لمسی ----------
const pt=e=>({x:(e.clientX-ox)/s,y:(e.clientY-oy)/s});
const inUI=e=>e.target.closest&&e.target.closest('button,.scr,.over');
document.addEventListener('pointerdown',e=>{if(AC&&AC.state==='suspended')AC.resume();if(!canCtl()||inUI(e))return;const p=pt(e);let f=null,bd=1e9;
 for(const b of bodies)if(b.team===turn&&b!==ball){const d=Math.hypot(p.x-b.x,p.y-b.y);if(d<b.r+30&&d<bd){f=b;bd=d}}
 if(!f)return;drag={b:f,s:p,c:p};e.preventDefault()});
document.addEventListener('pointermove',e=>{if(drag){drag.c=pt(e);e.preventDefault()}});
document.addEventListener('pointerup',e=>{if(!drag||drag.ai)return;const{b,s:p0,c}=drag,dx=p0.x-c.x,dy=p0.y-c.y,l=Math.hypot(dx,dy);drag=null;
 if(l>18)fire(b,dx,dy,l);e.preventDefault()});
document.addEventListener('pointercancel',()=>{drag=null});
requestAnimationFrame(loop);
})();
