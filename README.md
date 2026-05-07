# Agent Family

macOS에서 실행 중인 터미널 창을 감지하고, GUI 리스트에서 해당 창을 바로 앞으로 가져오는 앱입니다.

## MVP 목표

- 실행 중인 Terminal.app / iTerm2 감지
- 각 터미널 창 리스트업
- 아이콘/버튼 클릭으로 해당 창 활성화
- 추후 아이콘, 이미지, 상태, 태그, 그룹 관리 기능 확장

## 현재 구현

- SwiftUI 기반 macOS 앱
- SwiftUI 기본 WindowGroup 대신 직접 생성한 투명 NSWindow overlay
- borderless 투명 floating overlay 창
- 항상 다른 앱 위에 표시
- 마우스 드래그로 위치 이동
- 창 크기 조절 가능
- 배경/타이틀바/일반 창 크롬 제거
- 마우스 휠로 좌우 전환되는 터미널 캐러셀 UI
- 선택된 터미널의 현재 경로를 말풍선으로 표시
- AppleScript로 Terminal / iTerm2 전체 창 목록 조회
- AppleScript가 권한 문제로 실패하면 Accessibility API로 전체 창 목록 fallback 감지
- Accessibility도 실패하면 macOS Window Server 창 목록으로 fallback 감지
- Window Server fallback에서는 메뉴바/보조 surface 같은 작은 내부 창을 제외
- AppleScript로 선택한 창 활성화
- 3초마다 자동 새로고침

## 응용프로그램 빌드

더블클릭 가능한 macOS `.app` 번들을 생성합니다.

```bash
cd ~/Desktop/Sjw_dev/Coding/Agent_Family
./scripts/build-app.sh
open "dist/Agent Family.app"
```

생성 위치:

```text
dist/Agent Family.app
```

원하면 Finder에서 `dist/Agent Family.app`을 `/Applications` 폴더로 드래그해서 일반 앱처럼 사용할 수 있습니다.

## 개발 실행

```bash
cd ~/Desktop/Sjw_dev/Coding/Agent_Family
swift run AgentFamily
```

처음 실행 시 macOS가 자동화 권한을 요청할 수 있습니다.
허용 위치:

- System Settings → Privacy & Security → Automation
- 필요 시 Accessibility 권한도 추가

## 향후 아이디어

- 아이콘 커스터마이징
- 터미널별 이름/태그 저장
- shell command/current path 표시
- Agent별 상태 표시
- 메뉴바 앱 모드
- 창 검색/필터링
- 터미널 창 스냅샷/미리보기
