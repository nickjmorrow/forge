import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const P={
  // 0: the version he picked
  out0:'M136 34 C140 70 196 100 198 154 C200 196 168 220 128 220 C88 220 56 196 56 156 C56 128 70 106 88 90 C88 112 96 126 110 132 C102 100 108 62 136 34 Z',
  in0:'M134 112 C133 132 160 148 160 176 C160 196 146 206 128 206 C110 206 96 196 96 178 C96 162 105 152 113 146 C113 156 117 162 122 165 C117 145 120 126 134 112 Z',
  // 1: slimmer and taller
  out1:'M138 24 C142 64 190 96 190 152 C190 198 162 224 128 224 C94 224 66 198 66 156 C66 128 78 108 96 92 C96 114 102 126 114 132 C106 98 112 58 138 24 Z',
  in1:'M131 116 C130 138 156 152 156 179 C156 197 144 208 128 208 C112 208 100 197 100 181 C100 165 108 155 116 149 C116 159 120 165 125 167 C119 148 121 131 131 116 Z',
  // 2: a second lick on the right
  out2:'M130 24 C136 58 160 80 168 106 C174 94 178 82 176 68 C198 94 208 126 204 158 C200 198 166 224 128 224 C88 224 56 198 56 158 C56 128 70 106 88 90 C88 112 96 126 110 132 C102 96 106 58 130 24 Z',
};
P.in2=P.in1;
const solid=`fill="${W}" stroke="${W}" stroke-width="8" stroke-linejoin="round"`;
const cut=`fill="${K}" stroke="${K}" stroke-width="6" stroke-linejoin="round"`;
const line=w=>`fill="none" stroke="${W}" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const fire=['#FFB340','#F2421B'], ember=['#FF8A3D','#D9261C'], ink=['#1E2142','#0A0B19'], glyph=['#FFD25A','#FF4A1C'];
const set={};
for(const v of [0,1,2]){
  const o=P['out'+v], i=P['in'+v];
  set[`B${v}`]={tile:fire,layers:[{kind:'white',y:[24,224],mask:`<path d="${o}" ${solid}/><path d="${i}" ${cut}/>`}]};
  // C: 0 plain outline, 1 slim outline, 2 slim outline with the inner flame drawn as a second line
  const cm = v===2 ? `<path d="${P.out1}" ${line(11)}/><path d="${P.in1}" ${line(11)}/>` : `<path d="${o}" ${line(13)}/>`;
  set[`C${v}`]={tile:ember,layers:[{kind:'white',y:[24,224],mask:cm}]};
  set[`E${v}`]={tile:ink,layers:[{kind:'color',c:glyph,y:[24,224],mask:`<path d="${o}" ${solid}/><path d="${i}" ${cut}/>`}]};
}
for(const [k,s] of Object.entries(set)) fs.writeFileSync(`it-${k}.svg`,icon({...s,id:k},'flat'));
