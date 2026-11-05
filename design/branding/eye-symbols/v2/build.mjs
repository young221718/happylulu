import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root = '/Users/chanyoungchoi/workspace-chanyoung/app/happylulu/develop/design/branding/eye-symbols/v2';
if (fs.existsSync(root)) throw new Error('Preserve existing draft; use a new version');
fs.mkdirSync(path.join(root, 'assets'), {recursive:true});
fs.mkdirSync(path.join(root, 'fonts'));
const fontSource = '/Users/chanyoungchoi/workspace-chanyoung/design/common/typography/fonts';
for (const file of ['PretendardVariable.woff2', 'OFL-Pretendard.txt']) fs.copyFileSync(path.join(fontSource,file),path.join(root,'fonts',file));
// One closed contour: two round lobes with a curved, nonzero waist.
const contour = 'M50 41 C43 41 40 25 26 25 C13 25 4 35 4 50 C4 65 13 75 26 75 C40 75 43 59 50 59 C57 59 60 75 74 75 C87 75 96 65 96 50 C96 35 87 25 74 25 C60 25 57 41 50 41 Z';
function eyes(color) {
  return `<path data-part="connected-mask" d="${contour}" fill="${color?'#FFF8EA':'none'}" stroke="${color?'none':'currentColor'}" stroke-width="6" stroke-linejoin="round"/>
<g data-part="pupils" fill="${color?'#35264D':'currentColor'}"><circle cx="26" cy="50" r="9.5"/><circle cx="74" cy="50" r="9.5"/></g>
${color?'<g fill="#FFFDF7" data-part="catchlights"><circle cx="23" cy="46.5" r="2.6"/><circle cx="71" cy="46.5" r="2.6"/></g>':''}`;
}
function svg(viewBox,label,body) {return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" role="img" aria-label="${label}"><title>${label}</title>${body}</svg>\n`;}
const tile = `<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#BCA0F0"/><stop offset="1" stop-color="#9472D2"/></linearGradient></defs><rect data-part="tile" x="64" y="64" width="896" height="896" rx="200" fill="url(#tile)"/>`;
fs.writeFileSync(path.join(root,'assets/app-infinity.svg'), svg('0 0 1024 1024','happylulu 연결형 부엉이 눈 앱 아이콘',tile+`<g transform="translate(172 172) scale(6.8)">${eyes(true)}</g>`));
fs.writeFileSync(path.join(root,'assets/eyes-infinity.svg'), svg('0 0 100 100','happylulu 연결형 부엉이 눈 단색 심볼',eyes(false)));
const menu=(theme)=>`<div class="menu ${theme}"><span class="menu-name">happylulu</span><div class="menu-items"><img class="menu-eye" src="assets/eyes-infinity.svg" alt="${theme==='dark'?'어두운':'밝은'} 메뉴바의 눈 심볼"><span class="battery" aria-hidden="true"></span><span>09:41</span></div></div>`;
fs.writeFileSync(path.join(root,'preview.html'),`<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>happylulu · 연결형 눈 심볼 v2</title><style>
@font-face{font-family:Pretendard;src:url('fonts/PretendardVariable.woff2') format('woff2');font-weight:100 900;font-display:swap}
*{box-sizing:border-box}body{margin:0;background:#F5F2EF;color:#342943;font:400 16px/1.6 Pretendard,sans-serif;font-synthesis:none;letter-spacing:-.01em}.board{max-width:1200px;margin:auto;padding:40px 44px 30px}.eyebrow{color:#8B719F;font-size:12px;font-weight:600;letter-spacing:.08em;margin:0 0 8px}h1{margin:0;font-size:38px;line-height:1.2;letter-spacing:-.03em;font-weight:700}.intro{margin:12px 0 28px;color:#85768C;font-size:15px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:22px}.card{min-width:0;background:#FFFDFC;border:1px solid #E6DEE9;border-radius:24px;padding:25px 28px}.label{font-size:12px;font-weight:600;color:#8B7898;display:flex;justify-content:space-between;align-items:center}.badge{background:#F0E9F7;color:#82669E;border-radius:5px;padding:2px 7px;font-size:10px}.app-icon{display:block;width:330px;max-width:100%;height:auto;margin:9px auto 0}.brand{text-align:center;margin:0;font-weight:700;font-size:25px;letter-spacing:-.025em;line-height:1.2}.caption{text-align:center;margin:9px 0 0;color:#8C7F95;font-size:12px}.symbol-stage{height:187px;display:flex;align-items:center;justify-content:center;gap:38px}.symbol{display:block;width:230px;height:170px}.symbol-stage .small{width:38px;height:38px}.rule{border:0;border-top:1px solid #EEE8F1;margin:0 0 17px}.menu-label{font-size:12px;color:#8B7898;margin-bottom:10px}.menu{display:flex;align-items:center;justify-content:space-between;height:40px;border-radius:8px;padding:0 14px;margin:9px 0;font-size:11px;line-height:1;letter-spacing:0}.light{background:#EFECEA;color:#2B2730}.dark{background:#312A3C;color:#FCF9FF}.menu-name{font-weight:600}.menu-items{display:flex;align-items:center;gap:13px}.menu-eye{width:18px;height:18px;display:block}.dark .menu-eye{filter:invert(1)}.battery{width:18px;height:9px;border:1px solid currentColor;border-radius:2px;position:relative;opacity:.8}.battery:before{content:'';position:absolute;inset:1px 4px 1px 1px;background:currentColor;border-radius:1px}.battery:after{content:'';position:absolute;right:-3px;top:2px;width:1px;height:3px;background:currentColor}.detail{font-size:12px;color:#8C7F95;margin:17px 0 0}.foot{margin-top:23px;display:flex;justify-content:space-between;gap:16px;color:#91819C;font-size:11px}.links{max-width:1200px;margin:0 auto 36px;padding:0 44px;display:flex;flex-wrap:wrap;gap:20px;font-size:13px}.links a{color:#76568F;text-decoration:none}.links a:hover{text-decoration:underline}.links a:focus-visible{outline:2px solid #76568F;outline-offset:4px}@media(max-width:720px){.board{padding:28px 18px 22px}.grid{grid-template-columns:1fr}.card{padding:22px}h1{font-size:30px}.intro{font-size:14px}.app-icon{width:290px}.symbol-stage{height:170px;gap:20px}.symbol{width:210px;height:160px}.foot{display:block}.foot span{display:block}.links{padding:0 18px;gap:15px}}
</style></head><body><main class="board" id="comparison-board"><p class="eyebrow">happylulu · EYES STUDY 02</p><h1>가로로 누운 8자, 동그란 두 눈.</h1><p class="intro">양쪽은 둥글게, 가운데는 잘록하게. 하나로 이어지는 올루루의 눈테.</p><div class="grid"><section class="card"><div class="label"><span>앱 아이콘</span><span class="badge">연결형 눈테</span></div><img class="app-icon" src="assets/app-infinity.svg" alt="보라색 타일 위 크림색 연결형 눈테와 둥근 동공 두 개"><p class="brand">happylulu</p><p class="caption">라벤더 · 크림 · 짙은 보라</p></section><section class="card"><div class="label"><span>눈 심볼</span><span class="badge">한 줄로 이어진 윤곽</span></div><div class="symbol-stage"><img class="symbol" src="assets/eyes-infinity.svg" alt="가로 8자 형태의 연결된 눈테 확대"><img class="small" src="assets/eyes-infinity.svg" alt="작은 연결형 눈 심볼"></div><hr class="rule"><div class="menu-label">메뉴바 · 18 × 18 크기</div>${menu('light')}${menu('dark')}<p class="detail">같은 눈테를 밝은 메뉴바와 어두운 메뉴바에.</p></section></div><div class="foot"><span>공통 타일 896 × 896 · R200 · 여백 64 / 1024 기준</span><span>Pretendard · 제목 700 / 본문 400</span></div></main><nav class="links" aria-label="시안 파일"><a href="assets/app-infinity.svg" download>앱 아이콘 SVG</a><a href="assets/eyes-infinity.svg" download>눈 심볼 SVG</a><a href="README.md">설계 기준</a><a href="../v1/preview.html">이전 시안</a></nav></body></html>`);
fs.writeFileSync(path.join(root,'README.md'),`# happylulu 연결형 눈 심볼 v2

2026-10-19. 사용자가 설명한 가로로 누운 8자(∞) 형태를 반영한 디자인 미리보기입니다. v1의 분리된 눈테를 대신하는 새 후보이며, v1 파일과 실제 앱 코드는 변경하지 않습니다.

## 의도와 완료 기준

- 눈테는 한 개의 닫힌 곡선입니다. 양쪽 둥근 부분이 잘록한 가운데에서 이어집니다.
- 동공 두 개는 같은 반지름 9.5의 원입니다. 앱 컬러판만 작은 반짝임을 사용합니다.
- 앱과 단색 심볼의 눈테 곡선 및 동공 위치가 같습니다. 메뉴바에는 18×18 CSS px 모형을 제공합니다.
- 타일은 1024×1024 캔버스에 x64/y64, 896×896, R200입니다. 외부 그림자는 없습니다.
- 브랜드는 happylulu이며 lulu는 소문자입니다. 실제 글꼴은 Pretendard Variable v1.3.9, 제목700·본문400입니다. 글꼴과 OFL을 fonts/에 포함합니다.

## 확인 방법

SVG에서 단일 눈테 path, 두 원형 동공, 공통 path와 타일 치수를 확인합니다. 미리보기에서 이미지 로드, 폰트 로드, 밝고 어두운 18px 메뉴 심볼, 1200px 및 390px 화면의 가로 넘침을 확인합니다. 실제 측정은 validation.json에 기록합니다. 디자인이 사용자의 의도에 맞는지에 대한 최종 선택은 아직 하지 않았습니다.

[미리보기](preview.html) · [비교판 PNG](비교판.png) · [앱 SVG](assets/app-infinity.svg) · [단색 SVG](assets/eyes-infinity.svg)

SVG/HTML로 만든 벡터 시안입니다. AppKit 메뉴바 18pt의 1×·2× 실기기 출력, 실제 앱 적용 및 배포는 이 작업 범위에 포함하지 않습니다.
`);
fs.copyFileSync(new URL(import.meta.url),path.join(root,'build.mjs'));
const files=['assets/app-infinity.svg','assets/eyes-infinity.svg','fonts/PretendardVariable.woff2','fonts/OFL-Pretendard.txt','preview.html','README.md','build.mjs'];
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify({version:2,date:'2026-10-19',status:'design-proposal',files:files.map(file=>({file,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex')}))},null,2)+'\n');
console.log(root);
