import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
// right half described once, mirrored for the left so the mark is symmetric
const half=[
  ['C',133,62, 148,86, 150,116],   // centre tongue, right edge, down to a deep notch
  ['C',160,98, 176,86, 172,54],    // side tongue rises and its tip bends back in toward the centre
  ['C',202,78, 216,118, 208,156],  // outer edge bellies out, then S-curves down
  ['C',198,196, 166,222, 128,222], // base
];
const mir=x=>256-x;
function flamePath(){
  let d='M128 28';
  for(const [,a,b,c,e,x,y] of half) d+=` C${a} ${b} ${c} ${e} ${x} ${y}`;
  // walk back up the left side: reverse the segments and mirror
  const pts=[[128,28],...half.map(s=>[s[5],s[6]])];
  for(let i=half.length-1;i>=0;i--){
    const s=half[i], [px,py]=pts[i];
    d+=` C${mir(s[3])} ${s[4]} ${mir(s[1])} ${s[2]} ${mir(px)} ${py}`;
  }
  return d+' Z';
}
const OUT=flamePath();
// inner tongue cut out of the base (negative space), symmetric
const INNER='M128 108 C129 142 150 160 150 184 C150 200 140 208 128 208 C116 208 106 200 106 184 C106 160 127 142 128 108 Z';
const solid=`fill="${W}" stroke="${W}" stroke-width="6" stroke-linejoin="round"`;
const cut=`fill="${K}" stroke="${K}" stroke-width="4" stroke-linejoin="round"`;
const line=w=>`fill="none" stroke="${W}" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const set={
 'atla-b':{tile:['#FFB340','#F2421B'],layers:[{kind:'white',y:[34,220],mask:`<path d="${OUT}" ${solid}/><path d="${INNER}" ${cut}/>`}]},
 'atla-c':{tile:['#FF8A3D','#D9261C'],layers:[{kind:'white',y:[34,220],mask:`<path d="${OUT}" ${line(12)}/><path d="${INNER}" fill="#fff" stroke="#fff" stroke-width="4" stroke-linejoin="round"/>`}]},
 'atla-e':{tile:['#1E2142','#0A0B19'],layers:[{kind:'color',c:['#FFD25A','#FF4A1C'],y:[34,220],mask:`<path d="${OUT}" ${solid}/><path d="${INNER}" ${cut}/>`}]},
};
for(const [k,s] of Object.entries(set)) fs.writeFileSync(`${k}.svg`,icon({...s,id:k},'flat'));
