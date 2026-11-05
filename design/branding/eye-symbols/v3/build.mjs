import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const base='/Users/chanyoungchoi/workspace-chanyoung/app/happylulu/develop/design/branding/eye-symbols';
const root=path.join(base,'v3');
if(fs.existsSync(root))throw new Error('Preserve existing version');
for(const dir of ['assets','fonts','reference'])fs.mkdirSync(path.join(root,dir),{recursive:true});
for(const file of ['PretendardVariable.woff2','OFL-Pretendard.txt'])fs.copyFileSync(path.join(base,'v2/fonts',file),path.join(root,'fonts',file));
const reference='/var/folders/j5/p3lkg9t1315_6vnss0g8_2880000gn/T/codex-clipboard-b73cbceb-591f-4ddd-9811-34881a1a76f2.png';
fs.copyFileSync(reference,path.join(root,'reference/사용자-부엉이-참고.png'));
// The lower outline finishes beside the beak. It does not mirror the upper V.
const rim='M39 70 C35 74 31 75 26 75 C12 75 3 64 3 50 C3 35 13 24 27 24 C37 24 45 30 50 38 C55 30 63 24 73 24 C87 24 97 35 97 50 C97 64 88 75 74 75 C69 75 65 74 61 70';
const face=rim+' Q50 64 39 70 Z';
const beak='M50 62 C54 62 58 65 57 69 C55 74 53 78 51.3 80.5 Q50 82.5 48.7 80.5 C47 78 45 74 43 69 C42 65 46 62 50 62 Z';
function eyes(color){
 const ink=color?'#302D41':'currentColor';
 return `<defs><mask id="pupil-glints" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100"><rect width="100" height="100" fill="white"/><circle cx="26" cy="42" r="2.7" fill="black"/><circle cx="70" cy="42" r="2.7" fill="black"/></mask></defs>
${color?`<path data-part="face-fill" d="${face}" fill="#FFFBF1"/>`:''}
<path data-part="eye-rim" d="${rim}" fill="none" stroke="${ink}" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>
<g data-part="pupils" fill="${ink}" mask="url(#pupil-glints)"><ellipse cx="28" cy="49" rx="10" ry="13"/><ellipse cx="72" cy="49" rx="10" ry="13"/></g>
<path data-part="beak" d="${beak}" fill="${ink}"/>`;
}
const svg=(box,label,content)=>`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${box}" role="img" aria-label="${label}"><title>${label}</title>${content}</svg>\n`;
const tile='<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#BCA0F0"/><stop offset="1" stop-color="#9472D2"/></linearGradient></defs><rect data-part="tile" x="64" y="64" width="896" height="896" rx="200" fill="url(#tile)"/>';
// Center the full face including the beak, preserving the common 6.8 scale.
fs.writeFileSync(path.join(root,'assets/app-owl.svg'),svg('0 0 1024 1024','happylulu 둥근 눈과 작은 부리 앱 아이콘',tile+`<g transform="translate(172 153) scale(6.8)">${eyes(true)}</g>`));
fs.writeFileSync(path.join(root,'assets/eyes-owl.svg'),svg('0 0 100 100','happylulu 부엉이 눈과 작은 부리 단색 심볼',eyes(false)));
let html=fs.readFileSync(path.join(base,'v2/preview.html'),'utf8');
html=html.replaceAll('app-infinity.svg','app-owl.svg').replaceAll('eyes-infinity.svg','eyes-owl.svg')
 .replace('happylulu · 연결형 눈 심볼 v2','happylulu · 부엉이 눈 심볼 v3').replace('EYES STUDY 02','EYES STUDY 03')
 .replace('가로로 누운 8자, 동그란 두 눈.','올루루의 눈, 작은 부리.')
 .replace('양쪽은 둥글게, 가운데는 잘록하게. 하나로 이어지는 올루루의 눈테.','통통한 눈테 · 큰 타원형 동공 · 작은 반짝임')
 .replace('연결형 눈테','부엉이 얼굴').replace('한 줄로 이어진 윤곽','참고 그림의 인상')
 .replace('보라색 타일 위 크림색 연결형 눈테와 둥근 동공 두 개','보라색 타일 위 크림색 둥근 눈테, 큰 타원 동공과 작은 부리')
 .replace('가로 8자 형태의 연결된 눈테 확대','둥근 눈테, 타원 동공, 반짝임과 작은 부리 확대').replace('작은 연결형 눈 심볼','작은 부엉이 얼굴 심볼')
 .replace('같은 눈테를 밝은 메뉴바와 어두운 메뉴바에.','작은 부리까지 살린 단색 부엉이 얼굴.')
 .replace('../v1/preview.html','../v2/preview.html')
 .replace('<a href="README.md">설계 기준</a>','<a href="README.md">설계 기준</a><a href="reference/사용자-부엉이-참고.png">사용자 참고 그림</a>');
fs.writeFileSync(path.join(root,'preview.html'),html);
fs.writeFileSync(path.join(root,'README.md'),`# happylulu 부엉이 눈 심볼 v3

2026-10-19. 사용자가 제공한 그림의 오른쪽 눈·부리 심볼을 기준으로 새로 작성한 SVG 디자인 후보입니다. [원본 참고 그림](reference/사용자-부엉이-참고.png)은 변경 없이 함께 보관합니다.

## 이번 기준

v2의 위아래 대칭 땅콩 모양과 작은 원형 동공이 귀엽지 않고 부엉이답지 않다는 피드백을 반영합니다. 최신 참고 그림이 이전의 정확한 원형 동공 조건을 대체합니다.

- 위 중앙은 두 둥근 눈이 만나는 부드러운 V 모양입니다.
- 아래 윤곽은 눈을 둥글게 감싸며, 부리 옆에서 끝납니다. 위아래 대칭으로 깊게 파지 않습니다.
- 동공은 큰 세로 타원 두 개이며, 작은 반짝임을 포함합니다.
- 아래 중앙에 짧고 둥근 물방울 형태의 부리를 추가합니다.
- 컬러 앱 아이콘과 단색 심볼이 같은 눈테·동공·부리를 사용합니다.
- 앱은 기존 라벤더 타일과 크림색 눈 주변을 유지합니다. 1024 캔버스, x64/y64의896×896타일, R200입니다.
- 부리까지 포함한 얼굴의 시각적 중심을 맞추기 위해 전체 눈 심볼의 위치만 위로19단위 옮겼습니다. 타일 규격은 유지하며 심볼 배율은6.8입니다.
- Pretendard Variable v1.3.9, 제목700·본문400·브랜드700, happylulu 소문자 표기를 유지합니다.

## 확인과 범위

[미리보기](preview.html) · [비교판](비교판.png) · [앱 SVG](assets/app-owl.svg) · [단색 SVG](assets/eyes-owl.svg)

SVG에서 앱·단색 눈테와 부리의 동일성, 큰 세로 타원 동공 두 개와 반짝임 마스크, 공통 타일 치수를 확인합니다. 브라우저에서 이미지·폰트 로드,18×18 CSS px 메뉴 모형,1200/390px 가로 넘침을 확인하고 validation.json에 관측 결과를 남깁니다. 외부 디자인 선택과 실제 AppKit18pt 실기기 검증은 별개입니다.

v1·v2 및 실제 앱 코드는 보존합니다. 이 파일들은 SVG로 작성한 제안이며 앱 반영이나 배포는 하지 않았습니다.
`);
fs.copyFileSync(new URL(import.meta.url),path.join(root,'build.mjs'));
const files=['assets/app-owl.svg','assets/eyes-owl.svg','fonts/PretendardVariable.woff2','fonts/OFL-Pretendard.txt','reference/사용자-부엉이-참고.png','preview.html','README.md','build.mjs'];
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify({version:3,date:'2026-10-19',status:'design-proposal',method:'Native SVG based on user visual reference',files:files.map(file=>({file,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex')}))},null,2)+'\n');
console.log(root);
