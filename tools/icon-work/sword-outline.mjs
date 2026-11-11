import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff';
// line sword: drawn upright, tilted 45°; sw = stroke width on the 256 canvas
const sword=(sw,{hw=18,closedTip=true}={})=>{
  const st=`fill="none" stroke="${W}" stroke-width="${sw}" stroke-linejoin="round" stroke-linecap="round"`;
  return `<g transform="translate(128 128) scale(.98) rotate(45) translate(-128 -128)">`+
   `<path d="M128 24 L${128+hw} 56 V170 H${128-hw} V56 Z" ${st}/>`+
   `<path d="M80 170 H176" ${st}/><path d="M128 170 V214" ${st}/><circle cx="128" cy="228" r="${sw*0.85}" fill="${W}"/></g>`;
};
const solidGuard=(sw)=>{ // outline blade, solid hilt
  const st=`fill="none" stroke="${W}" stroke-width="${sw}" stroke-linejoin="round" stroke-linecap="round"`;
  return `<g transform="translate(128 128) scale(.98) rotate(45) translate(-128 -128)"><path d="M128 24 L146 56 V164 H110 V56 Z" ${st}/></g>`;
};
const hilt=(sw)=>`<g transform="translate(128 128) scale(.98) rotate(45) translate(-128 -128)" fill="none" stroke="${W}" stroke-width="${sw}" stroke-linecap="round"><path d="M80 172 H176"/><path d="M128 172 V214"/><circle cx="128" cy="228" r="9" fill="${W}"/></g>`;
const indigo=['#6E72FF','#2E2A9E'], ink=['#1E2142','#0A0B19'];
const set={
 'outline-a':{tile:indigo,layers:[{kind:'white',y:[40,216],mask:sword(11)}]},
 'outline-b':{tile:indigo,layers:[{kind:'white',y:[40,216],mask:sword(14)}]},
 'outline-c':{tile:indigo,layers:[{kind:'white',y:[40,216],mask:solidGuard(11)},{kind:'color',c:['#FFE27A','#FFB21E'],y:[40,216],mask:hilt(13)}]},
 'outline-d':{tile:ink,layers:[{kind:'color',c:['#C3C6FF','#9DA1FF'],y:[40,216],mask:sword(12)}]},
};
for(const [k,s] of Object.entries(set)) fs.writeFileSync(`${k}.svg`,icon({...s,id:k},'flat'));
