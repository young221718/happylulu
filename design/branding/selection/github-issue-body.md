## 변경 내용

Mac 메뉴바의 웃는 시계 아이콘을 올루루의 눈·부리 심볼(v3)로 변경합니다. 앱 아이콘과 메뉴바 심볼은 별도 자산으로 유지합니다.

## 확정한 디자인

- **앱 아이콘:** 기존에 선택한 민트색 타일의 보라색 올루루 + 시계 디자인을 유지합니다. 이번 작업에서 앱 아이콘 리소스를 교체하지 않습니다.
- **메뉴바:** v3의 둥근 눈테, 큰 세로 타원 동공, 작은 반짝임과 부리가 있는 단색 심볼을 채택합니다.
- v3 비교판에 함께 있던 보라색 타일의 눈 전용 앱 아이콘은 미채택입니다.
- 브랜드 표기는 **happylulu**이며 **lulu는 항상 소문자**입니다. 공통 글꼴은 Pretendard Variable, 제목·브랜드 700 / 본문 400 / 버튼 600입니다.

## 적용 위치와 완료 조건

현재 메뉴바 아이콘은 [Sources/AfterSix/LuluBrand.swift](https://github.com/young221718/happylulu/blob/main/Sources/AfterSix/LuluBrand.swift)의 `menuBarIcon()`에서 18×18pt NSImage로 그리고 있습니다.

- [ ] 아래 SVG 원본을 기준으로 메뉴바 눈·부리 심볼을 구현합니다. 눈테와 부리 사이의 작은 틈, 타원 동공과 반짝임을 유지합니다.
- [ ] 18×18pt 크기와 `isTemplate = true`를 유지하고 밝은·어두운 메뉴바에서 확인합니다.
- [ ] 실제 1×·2× 화면에서 눈테·동공·부리가 뭉개지거나 잘리지 않는지 확인합니다. SVG 좌표를 AppKit으로 옮길 때 상하 방향도 확인합니다.
- [ ] 앱 아이콘 리소스는 변경하지 않고, 클릭으로 메뉴를 여는 기존 동작을 확인합니다.
- [ ] 저장소의 `swift run --build-system native AfterSixChecks`와 `bash scripts/build-app.sh` 결과를 기록합니다.

## 채택한 SVG 원본

파일명: `eyes-owl.svg` · viewBox: `0 0 100 100` · 단색 `currentColor`

SHA-256: `3d9a2440d3af41a5ab18d3a1280f6ea80bccb08bdba2aef6cefd5ee05fa86134`

아래 코드를 `eyes-owl.svg`로 저장하면 채택한 원본을 사용할 수 있습니다. 반짝임은 마스크로 뚫은 투명 영역입니다.

<details>
<summary>eyes-owl.svg 전체 원본</summary>

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="happylulu 부엉이 눈과 작은 부리 단색 심볼"><title>happylulu 부엉이 눈과 작은 부리 단색 심볼</title><defs><mask id="pupil-glints" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100"><rect width="100" height="100" fill="white"/><circle cx="26" cy="42" r="2.7" fill="black"/><circle cx="70" cy="42" r="2.7" fill="black"/></mask></defs>

<path data-part="eye-rim" d="M39 70 C35 74 31 75 26 75 C12 75 3 64 3 50 C3 35 13 24 27 24 C37 24 45 30 50 38 C55 30 63 24 73 24 C87 24 97 35 97 50 C97 64 88 75 74 75 C69 75 65 74 61 70" fill="none" stroke="currentColor" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>
<g data-part="pupils" fill="currentColor" mask="url(#pupil-glints)"><ellipse cx="28" cy="49" rx="10" ry="13"/><ellipse cx="72" cy="49" rx="10" ry="13"/></g>
<path data-part="beak" d="M50 62 C54 62 58 65 57 69 C55 74 53 78 51.3 80.5 Q50 82.5 48.7 80.5 C47 78 45 74 43 69 C42 65 46 62 50 62 Z" fill="currentColor"/></svg>
```

</details>

## 확인한 범위

디자인 선택은 완료했습니다. 로컬 브라우저에서 18×18 CSS px의 밝은·어두운 메뉴바 모형과 SVG 로드를 확인했습니다. 실제 AppKit 출력, 앱 구현, 빌드, CI, 배포는 아직 수행하지 않았습니다.

워크스페이스 디자인 기록: `artifacts/design/archive/ollulu/happylulu-selection/README.md`

기존 앱 아이콘 참고 원본: `artifacts/design/archive/ollulu/app-branding-proposal/icons/happylulu.png` (SHA-256: `82a8ba2d30478b3a68a25a9b74071c4d01706263734494e2e8a40a26a55fa084`). 위 두 경로는 로컬 보관 위치이며 GitHub 첨부 링크가 아닙니다.
