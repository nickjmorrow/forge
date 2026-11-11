import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff';
const rnd=w=>`stroke="#fff" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const R='transform="translate(128 128) rotate(45) translate(-128 -128)"';
// hw: blade half-width at the shoulder; gw: guard length; g: grip width; p: pommel radius
const sword=(id,hw,gw,g,p,gt=15,gripGold=true)=>{
  const half=s=>`<path d="M128 10 L${128+s*hw} 50 L${128+s*(hw-2)} 172 H128 Z" fill="${W}" ${rnd(4)}/>`;
  const gx=gw/2;
  const guardOld=`<path d="M${128-gx} 182 C${128-gx} 175 ${128-gx/2} 171 128 171 C${128+gx/2} 171 ${128+gx} 175 ${128+gx} 182 C${128+gx} 189 ${128+gx/2} 193 128 193 C${128-gx/2} 193 ${128-gx} 189 ${128-gx} 182 Z" fill="${W}"/>`;
  const guard=`<rect x="${128-gx}" y="174" width="${gw}" height="${gt}" rx="${gt/2}" fill="${W}"/>`;
  const grip=`<rect x="${128-g/2}" y="184" width="${g}" height="42" rx="${g/2.5}" fill="${W}"/>`;
  return {id,tile:['#6E72FF','#2E2A9E'],layers:[
    {kind:'white',alpha:.55,y:[40,216],mask:`<g ${R}>${half(1)}</g>`},
    {kind:'white',y:[40,216],mask:`<g ${R}>${half(-1)}${gripGold?'':grip}</g>`},
    {kind:'color',c:['#FFE27A','#FFB21E'],y:[40,216],mask:`<g ${R}>${guard}${gripGold?grip:''}<circle cx="128" cy="${232+ (12-p)/2}" r="${p}" fill="${W}"/></g>`}]};
};
for(const s of [sword('slim-a',17,96,18,13),sword('slim-b',14,90,16,12,14),sword('slim-c',14,90,16,12,14,false)])
  fs.writeFileSync(`${s.id}.svg`,icon(s,'flat'));
