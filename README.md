# 찰칵

빌드된 iOS 시뮬레이터 `.app`을 화면별 런치 인자로 실행해 스크린샷을 찍고 GitHub Actions 아티팩트로 올린다.
UI 테스트 타깃을 안 만든다. Windows에서 iOS 앱을 만드는 사람이 TestFlight 없이 진짜 렌더링을 보려고 만들었다.

- 비용: 이미 쓰는 macOS 러너 시간 + 시뮬레이터 부팅 1~2분 + 컷당 약 10초. public 리포면 0원.
- 못 하는 것: 터치 조작, 햅틱, 위젯, 성능. 레이아웃·색·폰트·다크모드 확인용이다.

## 사용

빌드 스텝 뒤에 붙인다. 서명 없는 시뮬레이터 빌드면 된다.

```yaml
- name: Build (simulator, unsigned)
  run: |
    xcodebuild build -project MyApp.xcodeproj -scheme MyApp \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO

- uses: Yewon419/chalkak@main
  with:
    app: build/dd/Build/Products/Debug-iphonesimulator/MyApp.app
    defaults: |
      onboardingDone -bool true
    screens: |
      # 이름 | 런치 인자 (UserDefaults argument 도메인으로 들어간다)
      today    | -rootTab today
      settings | -rootTab settings
      english  | -rootTab today -AppleLanguages (en)
    appearance: light,dark
```

결과: `screenshots` 아티팩트에 `<이름>-<외관>.png` + `summary.md` + **`index.html`(갤러리)**. 잡 요약(Step Summary)에도 표가 붙는다.
zip을 풀고 `index.html`을 열면 폰 비율 격자로 보이고, 컷을 누르면 원본 크기.

### 단일 파일로 만들기

이미지를 data URI로 품은 HTML 한 장이 필요하면(Claude Artifact 등 단일 파일 호스팅):

```sh
gh run download <run-id> -n screenshots -D shots
python3 scripts/inline_gallery.py shots gallery.html
```

### 브라우저에서 바로 보기 (GitHub Pages)

아티팩트는 내려받아야 열린다. push마다 링크 하나로 보려면 출력 폴더를 `gh-pages`에 올린다. 리포가 public이면 무료.

```yaml
- uses: Yewon419/chalkak@main
  with:
    app: ...
    screens: ...
- uses: peaceiris/actions-gh-pages@v4
  if: always()
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: screenshots
```

잡에 `permissions: contents: write`가 필요하고, 리포 Settings > Pages에서 소스를 `gh-pages` 브랜치로 한 번 지정한다.
그 뒤엔 `https://<계정>.github.io/<리포>/`가 항상 마지막 런의 갤러리다. ⚠ Pages는 공개 URL이라 스크린샷이 누구에게나 보인다.

## 화면 이동 원리

앱 코드를 안 고친다. 두 경로만 쓴다.

1. **런치 인자** `-키 값`. `UserDefaults.standard`(그리고 `@AppStorage`)가 읽는 argument 도메인에 들어가며,
   앱이 application 도메인에 뭘 써도 읽기에선 argument 도메인이 이긴다. 탭·테마·언어처럼 String 키에 적합.
2. **defaults 사전 주입**. `xcrun simctl spawn <udid> defaults write <bundle-id> <키> <값>`. 첫 실행 전에만 넣는다.
   Bool 키(온보딩 완료 등)는 이쪽이 안전하다. 런치 인자의 `YES` 문자열을 `@AppStorage<Bool>`이 읽는지는 보장 못 한다.

앱이 진입 시 상태를 강제로 덮어쓰는 키(예: 실행마다 탭을 첫 탭으로 되돌림)는 2번으로는 안 되고 1번으로만 된다.

## 입력

| 입력 | 기본 | 설명 |
|---|---|---|
| `app` | 필수 | 시뮬레이터용 `.app` 경로 |
| `screens` | 필수 | 한 줄에 한 화면 `이름 \| 런치 인자`. 인자 생략 가능. `#` 주석 |
| `defaults` | `''` | 한 줄에 하나. `defaults write <bundle-id>` 뒤에 붙는 인자 그대로 |
| `appearance` | `light` | `light` / `dark` / `light,dark` |
| `device` | `''` | 기기 이름 부분 문자열. 비우면 최신 iOS 런타임의 첫 iPhone |
| `runtime` | `''` | `iOS 26` 같은 런타임 필터 |
| `wait` | `5` | 실행 후 촬영까지 대기 초. 스플래시가 길면 늘린다 |
| `output-dir` | `screenshots` | 출력 폴더 |
| `artifact-name` | `screenshots` | 아티팩트 이름 |
| `upload` | `true` | 아티팩트 업로드 여부 |
| `fail-on-crash` | `true` | 촬영 시점에 앱이 죽어 있던 컷이 있으면 스텝 실패 |
| `bundle-id` | `''` | 비우면 `Info.plist`의 `CFBundleIdentifier` |
| `title` | `''` | 갤러리 제목. 비우면 `<실행파일명> 찰칵` |
| `privacy` | `''` | 설치 후 미리 허용할 권한. 쉼표 구분, `simctl privacy` 서비스명(`location`, `photos`, `all` 등) |

## 로컬 Mac에서

```sh
APP=build/dd/Build/Products/Debug-iphonesimulator/MyApp.app \
SCREENS=$'today | -rootTab today\nsettings | -rootTab settings' \
DEFAULTS='onboardingDone -bool true' \
scripts/shoot.sh
```

시뮬레이터는 끝나도 안 끈다(`SHUTDOWN=true`면 끈다). 같은 시뮬레이터에 다시 돌리면 `defaults`는 이미 실행된 앱의 캐시에 밀릴 수 있으니
깨끗이 하려면 `xcrun simctl uninstall booted <bundle-id>` 후 재실행.

## 함정

- **entitlements는 빌드 단계에서.** 시뮬레이터용 entitlements는 codesign이 아니라 링크 시점에 바이너리의
  `__TEXT,__entitlements` 섹션으로 들어간다. `CODE_SIGNING_ALLOWED=NO`로 빌드하면 이 섹션이 없어서 CloudKit을 쓰는 앱은
  `CKContainer(identifier:)`가 `EXC_BREAKPOINT`로 죽는다(실측). 처방은 시뮬레이터 빌드에 서명을 켜는 것:

  ```sh
  xcodebuild build ... -destination 'generic/platform=iOS Simulator' \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO     # ad-hoc. 인증서·프로파일 불필요
  ```

  빌드 뒤에 `codesign --entitlements`로 심는 건 안 된다. 호스트 macOS의 taskgated가 제한 entitlement를 가진 ad-hoc 프로세스를
  죽인다(실측: `SIGKILL (Code Signature Invalid)`, `Taskgated Invalid Signature`). 그래서 찰칵은 서명을 건드리지 않는다.
  iCloud 계정이 없어도 컨테이너 초기화는 통과하고 동기화만 실패 로그를 낸다.
- 기기 이름을 하드코딩하지 않는다. 러너 이미지가 바뀌면 `device not found`로 깨진다(actions/runner-images #10960). 런타임 목록에서 고른다.
- **시스템 권한 시트는 한 번 뜨면 앱을 다시 실행해도 남아서 이후 모든 컷을 가린다**(실측: 위치 시트 하나가 44컷 중 22컷을 덮었다).
  위치·사진·연락처 등은 `privacy` 입력으로 미리 허용한다. 알림·HealthKit은 `simctl privacy`에 없어 못 준다. 시트가 뜨는 화면은 목록 마지막에 두는 것도 방법.
- 촬영 시점에 앱이 죽어 있으면 `summary.md`에 `죽음`으로 남고 `crash/`에 `.ips` 리포트가 들어간다. 홈 화면이 찍혀 있으면 그 경우다.
- 러너에서 시뮬레이터 첫 부팅은 5분까지 걸렸다(실측, iOS 26.5). 컷 자체는 10초 안팎.
- 상태바 고정(`status_bar override`)이 기기·런타임에 따라 안 먹을 수 있다. 실패해도 촬영은 계속한다.
- 아티팩트 이미지는 PR 코멘트에 인라인이 안 된다. zip을 내려받아 본다.
