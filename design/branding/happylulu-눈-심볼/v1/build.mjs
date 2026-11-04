import fs from 'node:fs';
import path from 'node:path';
const root='/Users/chanyoungchoi/workspace-chanyoung/디자인/올루루/happylulu-눈-심볼/v1';
if(fs.existsSync(root)) throw new Error('Preserve existing draft; choose a new version');
fs.mkdirSync(path.join(root,'assets'),{recursive:true});
fs.mkdirSync(path.join(root,'fonts'));
const old='/Users/chanyoungchoi/workspace-chanyoung/디자인/올루루/앱-브랜딩-제안/fonts';
for(const file of ['PretendardVariable.woff2','OFL-Pretendard.txt'])fs.copyFileSync(path.join(old,file),path.join(root,'fonts',file));
const variants=[
 {id:'bright',letter:'A',name:'초롱눈',tag:'기본 로고 추천',desc:'또렷하고 호기심 있는 표정'},
 {id:'smile',letter:'B',name:'반달눈',tag:'웃는 반응',desc:'살짝 눌렀을 때 반갑게 웃는 느낌'},
 {id:'relaxed',letter:'C',name:'능청눈',tag:'느긋한 캐릭터',desc:'여유 있고 살짝 능청스러운 표정'}
];
const eye='M 8 29 C 8 26 10 25 13 26 L 30 29 C 39 31 43 39 43 50 C 43 64 35 74 24 74 C 12 74 4 65 4 52 C 4 43 6 35 8 29 Z';
function mark(id,color=false){
 const ink=color?'#35264D':'currentColor';
 const outlines=`<path d="${eye}"/><path d="${eye}" transform="translate(100 0) scale(-1 1)"/>`;
 const outer=`<g fill="${color?'#FFF8EA':'none'}" stroke="${color?'none':ink}" stroke-width="6.5" stroke-linejoin="round">${outlines}</g>`;
 let inner='';
 if(id==='bright')inner=`<ellipse cx="25" cy="50" rx="9" ry="12"/><ellipse cx="75" cy="50" rx="9" ry="12"/>`;
 if(id==='smile')inner=`<g fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round"><path d="M16 53 Q25 38 34 53"/><path d="M66 53 Q75 38 84 53"/></g>`;
 if(id==='relaxed')inner=`<path d="M16 46H34C34 62 16 62 16 46Z"/><path d="M66 46H84C84 62 66 62 66 46Z"/><g fill="none" stroke="${ink}" stroke-width="6.5" stroke-linecap="round"><path d="M14 46H36"/><path d="M64 46H86"/></g>`;
 let glints='';
 if(color&&id==='bright') glints='<g fill="#FFFDF7"><circle cx="22.5" cy="46" r="2.5"/><circle cx="72.5" cy="46" r="2.5"/></g>';
 return outer+`<g fill="${ink}">${inner}</g>`+glints;
}
const svg=(viewBox,content,label)=>`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" role="img" aria-label="${label}"><title>${label}</title>${content}</svg>`;
for(const v of variants){
 fs.writeFileSync(path.join(root,'assets',`eyes-${v.id}.svg`),svg('0 0 100 100',mark(v.id),`happylulu ${v.name} 메뉴바 심볼`));
 const tile='<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#BCA0F0"/><stop offset="1" stop-color="#9472D2"/></linearGradient><clipPath id="tile-clip"><rect x="64" y="64" width="896" height="896" rx="200"/></clipPath></defs><rect x="64" y="64" width="896" height="896" rx="200" fill="url(#tile)"/>';
 const content=tile+`<g clip-path="url(#tile-clip)"><g transform="translate(172 172) scale(6.8)">${mark(v.id,true)}</g></g>`;
 fs.writeFileSync(path.join(root,'assets',`app-${v.id}.svg`),svg('0 0 1024 1024',content,`happylulu ${v.name} 앱 아이콘 시안`));
}
const cards=variants.map(v=>`<article class="card" data-variant="${v.id}">
 <div class="card-top"><h2>${v.letter}<span>${v.name}</span></h2><span class="tag">${v.tag}</span></div>
 <div class="app-area"><img class="app-icon" src="assets/app-${v.id}.svg" alt="${v.name} 앱 아이콘"></div>
 <p class="description">${v.desc}</p>
 <div class="menu-label">메뉴바 · 원래 크기</div>
 <div class="menu light"><span>happylulu</span><div class="menu-right"><img class="menu-eye" src="assets/eyes-${v.id}.svg" alt="밝은 메뉴바 ${v.name}"><span class="battery"></span><span>09:41</span></div></div>
 <div class="menu dark"><span>happylulu</span><div class="menu-right"><img class="menu-eye" src="assets/eyes-${v.id}.svg" alt="어두운 메뉴바 ${v.name}"><span class="battery"></span><span>09:41</span></div></div>
 <div class="zoom"><span>눈 심볼 확대</span><img src="assets/eyes-${v.id}.svg" alt="${v.name} 눈 심볼 확대"></div>
 <div class="links"><a href="assets/app-${v.id}.svg" download>앱 SVG</a><a href="assets/eyes-${v.id}.svg" download>눈 SVG</a></div>
 </article>`).join('');
fs.writeFileSync(path.join(root,'preview.html'),`<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>happylulu · 눈 심볼 시안</title>
<style>
@font-face{font-family:PP;src:url('fonts/PretendardVariable.woff2') format('woff2');font-weight:100 900;font-display:swap}
*{box-sizing:border-box}body{margin:0;background:#F6F3EE;color:#322940;font:400 16px/1.6 PP,sans-serif;font-synthesis:none;letter-spacing:-.01em}.board{max-width:1240px;margin:auto;padding:38px 40px 30px}.eyebrow{font-size:12px;font-weight:600;letter-spacing:.1em;color:#7D6A99;margin:0 0 8px}h1{margin:0;font-size:36px;line-height:1.2;font-weight:700;letter-spacing:-.03em}.intro{color:#756B81;font-size:15px;margin:12px 0 26px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}.card{border:1px solid #E2DBE9;border-radius:22px;background:#FFFDFB;padding:20px;min-width:0}.card:first-child{border-color:#A18AC2;box-shadow:0 0 0 1px #A18AC2}.card-top{display:flex;align-items:center;justify-content:space-between;gap:6px}h2{margin:0;font-size:18px;font-weight:700;color:#715494;line-height:1.2}h2 span{margin-left:8px;color:#322940}.tag{color:#77638F;font-size:10px;font-weight:600;background:#F1EAFB;border-radius:6px;padding:3px 7px}.app-area{display:flex;justify-content:center;padding:16px 0 0}.app-icon{display:block;width:232px;max-width:100%;height:auto}.description{margin:3px 0 23px;text-align:center;font-size:12px;color:#796C84}.menu-label{font-size:11px;color:#85778D;margin-bottom:8px}.menu{display:flex;justify-content:space-between;align-items:center;height:34px;padding:0 11px;border-radius:8px;margin:7px 0;font-size:10px;line-height:1;letter-spacing:0}.light{background:#ECEAE8;color:#29272D}.dark{background:#302B3B;color:#FAF7FF}.menu-right{display:flex;align-items:center;gap:11px}.menu-eye{display:block;width:18px;height:18px}.dark .menu-eye{filter:invert(1)}.battery{width:17px;height:8px;border:1px solid currentColor;border-radius:2px;position:relative;opacity:.8}.battery:before{content:'';position:absolute;inset:1px 4px 1px 1px;background:currentColor;border-radius:1px}.battery:after{content:'';position:absolute;width:1px;height:3px;right:-3px;top:1.5px;background:currentColor}.zoom{display:flex;align-items:center;justify-content:space-between;border-top:1px solid #EEE8F2;margin-top:20px;padding-top:10px;min-height:66px}.zoom span{font-size:11px;color:#8B7B96}.zoom img{width:70px;height:70px}.links{display:flex;gap:15px;font-size:11px}.links a{color:#715494;text-decoration:none}.links a:hover{text-decoration:underline}.links a:focus-visible{outline:2px solid #715494;outline-offset:3px}.foot{display:flex;justify-content:space-between;gap:16px;color:#7E7288;font-size:11px;margin-top:20px}.notes{max-width:1160px;margin:0 auto 40px;padding:0 40px;color:#7E7288;font-size:12px}.notes a{color:#715494}@media(max-width:750px){.board{padding:26px 18px}.grid{grid-template-columns:1fr;gap:16px}.card{max-width:420px;width:100%;margin:auto}.app-icon{width:210px}h1{font-size:28px}.foot{display:block}.notes{padding:0 18px}}
</style></head><body><main class="board" id="comparison-board"><p class="eyebrow">happylulu · EYES STUDY 01</p><h1>눈으로 기억되는 happylulu</h1><p class="intro">같은 눈테, 같은 크기. 표정만 다르게.</p><div class="grid">${cards}</div><div class="foot"><span>공통 타일 896 × 896 · R200 · 여백 64 / 1024 기준</span><span>메뉴바 심볼 18 × 18 · Pretendard 700 / 400</span></div></main><div class="notes">디자인 비교용 시안입니다. 실제 메뉴바 적용 전 1×·2× 화면에서 확인합니다. <a href="README.md">설계 기준과 SVG 원본 안내</a></div></body></html>`);
fs.writeFileSync(path.join(root,'README.md'),`# happylulu 눈 심볼 시안 v1

올루루의 큰 눈을 앱과 메뉴바에 함께 사용하는 세 가지 벡터 시안입니다. 사용자의 2026-10-19 요청에 따른 미리보기이며, 실제 앱 코드를 변경하거나 적용하지 않았습니다.

- A 초롱눈: 또렷한 기본 로고 후보.
- B 반달눈: 눌렀을 때 웃는 반응의 후보. 애니메이션이나 앱 동작은 구현하지 않았습니다.
- C 능청눈: 반쯤 뜬 느긋한 표정 후보.

[비교판](preview.html)에서 앱 아이콘, 밝고 어두운 메뉴바, 눈 심볼 확대를 함께 볼 수 있습니다. 자산은 assets/에 있습니다.

## 공통 규격

- 브랜드 표기: happylulu. lulu는 항상 소문자입니다.
- 앱 아이콘: 1024×1024 viewBox, x64/y64의896×896타일, R200, 외부 그림자 없음.
- 눈 모양: 세 표정이 동일한 외곽 path를 사용합니다. 같은 변환 translate(172 172) scale(6.8)을 적용하고 눈 내부만 바꿉니다.
- 단색 메뉴바: 100×100 viewBox, 18×18 CSS px로 표시하는 모형, 외곽선6.5단위. 실제 AppKit 18pt의 1×·2× 출력과 광학 보정은 적용 단계에서 확인해야 합니다.
- 앱과 메뉴바의 눈 외곽은 동일합니다. 앱에서는 크림색 면과 짙은 동공을, 메뉴바에서는 단색 윤곽선과 동공을 사용합니다.
- 앱의 작은 동공 반짝임은 밝은눈 컬러판에만 사용하며 18pt 단색판에서는 생략합니다.
- 실제 글꼴: 함께 보관한 Pretendard Variable v1.3.9. 제목700·본문400. OFL 라이선스를 fonts/에 포함했습니다.

기존 올루루 이미지나 레포에 보관한 시안은 교체하지 않았습니다. 이 시안은 SVG/HTML로 직접 작성한 벡터 자산이며 이미지 생성 모델로 제작한 비트맵이 아닙니다.
`);
fs.copyFileSync(new URL(import.meta.url),path.join(root,'build.mjs'));
console.log(root);
