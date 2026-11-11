import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const rnd=w=>`stroke="#fff" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const out=process.argv[2];
// Sword: drawn upright, centred, then tilted 45°. Two-tone blade (left half solid, right half translucent) for the bevel.
const R='transform="translate(128 128) scale(.96) rotate(45) translate(-128 -136)"';
const sword=(tile,gold)=>({id:'sword',tile,layers:[
  {kind:'white',alpha:.55,y:[40,216],mask:`<g ${R}><path d="M128 22 L154 56 V158 H128 Z" fill="${W}" ${rnd(8)}/></g>`},
  {kind:'white',y:[40,216],mask:`<g ${R}><path d="M128 22 L102 56 V158 H128 Z" fill="${W}" ${rnd(8)}/><rect x="113" y="170" width="30" height="54" rx="10" fill="${W}"/></g>`},
  {kind:'color',c:gold,y:[40,216],mask:`<g ${R}><rect x="66" y="150" width="124" height="30" rx="15" fill="${W}"/><circle cx="128" cy="234" r="17" fill="${W}"/></g>`}]});
// Flame: translucent outer flame, solid inner flame.
const outer=`<path d="M136 34 C140 70 196 100 198 154 C200 196 168 220 128 220 C88 220 56 196 56 156 C56 128 70 106 88 90 C88 112 96 126 110 132 C102 100 108 62 136 34 Z" fill="${W}" ${rnd(8)}/>`;
const inner=`<path d="M136 104 C134 126 168 146 168 178 C168 202 150 218 128 218 C106 218 88 202 88 180 C88 160 100 148 110 140 C110 152 114 160 120 164 C114 140 118 118 136 104 Z" fill="${W}" ${rnd(8)}/>`;
const flameSolid=(tile,c)=>({id:'flame',tile,layers:[{kind:'white',y:[38,218],mask:outer},{kind:'color',c,y:[104,218],mask:inner}]});
const flame=(tile,inner2)=>({id:'flame',tile,layers:[
  {kind:inner2?'color':'white',c:inner2,alpha:inner2?1:.5,y:[38,218],mask:outer},
  {kind:'white',y:[104,218],mask:inner}]});
const set={
  'sword-indigo':sword(['#6E72FF','#2E2A9E'],['#FFE27A','#FFB21E']),
  'sword-red':sword(['#FF6B6B','#E0202E'],['#FFE27A','#FFB21E']),
  'flame-orange':flameSolid(['#FFB340','#FF6A1F'],['#FFD43F','#FF8A00']),
  'flame-red':flameSolid(['#FF8A5C','#F0332A'],['#FFB340','#FF5A1F']),
  'flame-graphite':flame(['#3C3C42','#18181B'],['#FFC14D','#FF5A1F']),
  'sword-midnight':sword(['#1C2A55','#0E1630'],['#FFE27A','#FFCC33']),
  'flame-midnight':flame(['#1C2A55','#0E1630'],['#FFE27A','#FFB21E']),
};
for(const [k,s] of Object.entries(set)){fs.writeFileSync(`${out}/${k}.svg`,icon({...s,id:k},'flat'));}
