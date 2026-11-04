# CPU 러너 실제 렌더

이 폴더는 최초 구현(v1)의 이력입니다. 2026-10-22 사용자 검토에서 제안 시안과 머리·몸·다리 비율이 다르다는 지적을 받았습니다. 기능·렌더 검사의 통과는 디자인 수락을 뜻하지 않으며, 이 파일들은 비교용으로 보존합니다.

2026-10-22 승인한 햄스터·토끼·고양이 3종의 AppKit 그림 렌더입니다. `app/happylulu/cpu-runner`의 `RunnerArtwork`와 `scripts/check-runner-artwork.sh`에서 생성했습니다.

- `runner-preview.gif`: 세 동물의 실제 8프레임 애니메이션을 고정 속도로 비교합니다. 실시간 CPU 측정 화면이 아닙니다.
- `runner-frames-light.png`, `runner-frames-dark.png`: 26×18pt 크기와 확대 그림의 8프레임 비교.

런타임은 CPU를 1초마다 측정해 속도를 바꾸며 동작 줄이기·저전력 모드를 따릅니다. 기존 부엉이 및 출퇴근 표시를 대체하지 않습니다.

설정 화면 PNG는 실제 `CPURunnerSettingsView`를 최소500pt폭으로 렌더한 검사 화면입니다. CPU35%는 개인정보 없는 고정 예시값이며 실제 사용량이 아닙니다.
