import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff';
// bowl: a thick U whose arms taper up into the side tongues, tips bending in
const BOWL='M80 74 C44 112 42 182 80 212 C104 232 152 232 176 212 C214 182 212 112 176 74 C188 114 188 150 172 168 C156 186 100 186 84 168 C68 150 68 114 80 74 Z';
// centre flame: tall teardrop, its base sinks into the bowl
const CORE='M128 26 C138 64 160 100 158 140 C157 168 146 188 128 190 C110 188 99 168 98 140 C96 100 118 64 128 26 Z';
// the curl: a tail off the centre's base hooking up into the right gap
const CURL='M150 178 C170 176 180 156 174 142 C170 132 158 132 157 142';
const fill=`fill="${W}" stroke="${W}" stroke-width="5" stroke-linejoin="round"`;
const line=w=>`fill="none" stroke="${W}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"`;
const mark=(curl)=>`<path d="${BOWL}" ${fill}/><path d="${CORE}" ${fill}/>`+(curl?`<path d="${CURL}" ${line(11)}/>`:'');
const fire=['#FFB340','#F2421B'], ember=['#FF8A3D','#D9261C'], ink=['#1E2142','#0A0B19'], emberGlyph=['#FFD25A','#FF4A1C'];
const set={
 'el3-b':{tile:fire,layers:[{kind:'white',y:[26,220],mask:mark(true)}]},
 'el3-b2':{tile:fire,layers:[{kind:'white',y:[26,220],mask:mark(false)}]},
 'el3-c':{tile:ember,layers:[{kind:'white',y:[26,220],mask:`<path d="${BOWL}" ${line(10)}/><path d="${CORE}" ${line(10)}/><path d="${CURL}" ${line(10)}/>`}]},
 'el3-e':{tile:ink,layers:[{kind:'color',c:emberGlyph,y:[26,220],mask:mark(true)}]},
};
for(const [k,s] of Object.entries(set)) fs.writeFileSync(`${k}.svg`,icon({...s,id:k},'flat'));
