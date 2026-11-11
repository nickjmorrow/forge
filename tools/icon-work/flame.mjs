import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const OUT='M136 34 C140 70 196 100 198 154 C200 196 168 220 128 220 C88 220 56 196 56 156 C56 128 70 106 88 90 C88 112 96 126 110 132 C102 100 108 62 136 34 Z';
const IN='M136 104 C134 126 168 146 168 178 C168 202 150 218 128 218 C106 218 88 202 88 180 C88 160 100 148 110 140 C110 152 114 160 120 164 C114 140 118 118 136 104 Z';
// inner flame raised so negative space leaves a white rim at the bottom
const IN_CUT='M134 112 C133 132 160 148 160 176 C160 196 146 206 128 206 C110 206 96 196 96 178 C96 162 105 152 113 146 C113 156 117 162 122 165 C117 145 120 126 134 112 Z';
const f=(d,extra='')=>`<path d="${d}" ${extra}/>`;
const solid=`fill="${W}" stroke="${W}" stroke-width="8" stroke-linejoin="round"`;
const line=w=>`fill="none" stroke="${W}" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const fire=['#FFB340','#F2421B'], ember=['#FF8A3D','#D9261C'], graphite=['#3C3C42','#18181B'], ink=['#1E2142','#0A0B19'];
const set={
 'fire-a':{tile:graphite,layers:[{kind:'color',c:['#FFC14D','#FF4A1C'],y:[34,220],mask:f(OUT,solid)},{kind:'white',y:[104,218],mask:f(IN,solid)}]},
 'fire-b':{tile:fire,layers:[{kind:'white',y:[34,220],mask:f(OUT,solid)+f(IN_CUT,`fill="${K}" stroke="${K}" stroke-width="6" stroke-linejoin="round"`)}]},
 'fire-c':{tile:ember,layers:[{kind:'white',y:[34,220],mask:f(OUT,line(13))}]},
 'fire-c2':{tile:ember,layers:[{kind:'white',y:[34,220],mask:f(OUT,line(12))+f('M131 136 C131 150 152 162 152 180 C152 194 142 202 128 202 C114 202 104 194 104 181 C104 168 112 160 118 155 C119 162 121 166 125 168 C121 156 123 145 131 136 Z',`fill="#fff" stroke="#fff" stroke-width="4" stroke-linejoin="round"`)}]},
 'fire-d':{tile:ink,layers:[{kind:'color',c:['#FFD25A','#FF4A1C'],y:[34,220],mask:f(OUT,solid)+f(IN_CUT,`fill="${K}" stroke="${K}" stroke-width="6" stroke-linejoin="round"`)}]},
};
for(const [k,s] of Object.entries(set)) fs.writeFileSync(`${k}.svg`,icon({...s,id:k},'flat'));
