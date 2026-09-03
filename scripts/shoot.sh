#!/usr/bin/env bash
# 찰칵 : 빌드된 iOS 시뮬레이터 .app을 화면별 런치 인자로 실행해 스크린샷을 찍는다.
# UI 테스트 타깃 없이 동작한다. 화면 이동은 UserDefaults argument 도메인(런치 인자)과
# 사전 주입 defaults로만 한다. macOS + Xcode 필요. GitHub Actions 밖(로컬 Mac)에서도 그대로 돈다.
#
# 입력(환경변수):
#   APP            필수. 시뮬레이터용 .app 경로 (Debug-iphonesimulator/*.app)
#   SCREENS        필수. 한 줄에 한 화면: "<이름> | <런치 인자>". 인자는 비워도 된다. '#' 줄은 주석.
#   DEFAULTS       선택. 한 줄에 하나: "<키> -bool true" 식으로 `defaults write <bundle-id>` 뒤에 붙는 인자.
#   APPEARANCE     선택. light | dark | light,dark  (기본 light)
#   DEVICE         선택. 기기 이름 부분 문자열 (예: "iPhone 17 Pro"). 비우면 최신 iOS 런타임의 첫 iPhone.
#   RUNTIME        선택. "iOS 26" 처럼 런타임 필터. 비우면 최신.
#   WAIT           선택. 실행 후 촬영까지 대기 초 (기본 5)
#   OUT            선택. 출력 폴더 (기본 screenshots)
#   BUNDLE_ID      선택. 비우면 Info.plist에서 읽는다.
#   FAIL_ON_CRASH  선택. 촬영 시점에 앱이 죽어 있으면 마지막에 실패 종료 (기본 true)
#   SHUTDOWN       선택. 끝나고 시뮬레이터 종료 (기본 false. 로컬 디버깅 편의)
set -euo pipefail

APP="${APP:?APP=<path.app> 필요}"
SCREENS="${SCREENS:?SCREENS=<이름 | 런치 인자> 줄 목록 필요}"
DEFAULTS="${DEFAULTS:-}"
APPEARANCE="${APPEARANCE:-light}"
DEVICE="${DEVICE:-}"
RUNTIME="${RUNTIME:-}"
WAIT="${WAIT:-5}"
OUT="${OUT:-screenshots}"
BUNDLE_ID="${BUNDLE_ID:-}"
FAIL_ON_CRASH="${FAIL_ON_CRASH:-true}"
SHUTDOWN="${SHUTDOWN:-false}"

log() { printf '[찰칵] %s\n' "$*"; }
die() { printf '[찰칵] 오류: %s\n' "$*" >&2; exit 1; }
trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

command -v xcrun >/dev/null || die "xcrun 없음. macOS + Xcode에서만 돈다"
[ -d "$APP" ] || die "앱 번들 없음: $APP"
PLIST="$APP/Info.plist"
[ -f "$PLIST" ] || die "Info.plist 없음: $PLIST"
[ -n "$BUNDLE_ID" ] || BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
EXEC_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")
log "앱 $BUNDLE_ID (실행파일 $EXEC_NAME)"

# ── 기기 선택: 이름 하드코딩 금지. 러너 이미지가 바뀌면 "device not found"로 깨진다
#    (actions/runner-images #10960). 런타임 목록에서 고른다.
PICK=$(RUNTIME="$RUNTIME" DEVICE="$DEVICE" python3 - <<'PY'
import json, os, subprocess, sys
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", "devices", "available"]))
want_rt = os.environ.get("RUNTIME", "").strip()
want_dev = os.environ.get("DEVICE", "").strip()

def rt_key(rt):  # "...SimRuntime.iOS-26-5" -> (26, 5)
    return tuple(int(p) for p in rt.rsplit("iOS-", 1)[1].split("-"))

runtimes = [rt for rt in data["devices"] if ".iOS-" in rt]
if want_rt:
    tag = want_rt.replace("iOS ", "iOS-").replace(".", "-")
    runtimes = [rt for rt in runtimes if tag in rt]
runtimes.sort(key=rt_key, reverse=True)
for rt in runtimes:
    for d in data["devices"][rt]:
        if not d.get("isAvailable", False):
            continue
        name = d["name"]
        if want_dev:
            if want_dev not in name:
                continue
        elif not name.startswith("iPhone"):
            continue
        print(d["udid"] + "\t" + name + "\t" + rt.rsplit(".", 1)[1])
        sys.exit(0)
sys.exit(1)
PY
) || die "조건에 맞는 시뮬레이터 없음 (RUNTIME='$RUNTIME' DEVICE='$DEVICE'). 'xcrun simctl list devices available'로 확인"
UDID=$(printf '%s' "$PICK" | cut -f1)
DEV_NAME=$(printf '%s' "$PICK" | cut -f2)
RT_NAME=$(printf '%s' "$PICK" | cut -f3)
log "기기 $DEV_NAME ($RT_NAME) $UDID"

# ── 부팅 (재시도 3회. 러너에서 첫 부팅이 간헐적으로 실패한다)
booted=false
for attempt in 1 2 3; do
  if xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1; then booted=true; break; fi
  log "부팅 시도 $attempt 실패, 재시도"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  sleep 5
done
[ "$booted" = true ] || die "시뮬레이터 부팅 실패: $UDID"
log "부팅 완료"

# 상태바 고정: 시각 9:41, 배터리 100, 신호 만땅. 실패해도 촬영은 계속한다.
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 \
  >/dev/null 2>&1 || log "상태바 고정 실패 (계속)"

# ── 서명은 건드리지 않는다. 시뮬레이터 entitlements는 codesign이 아니라 링크 시점에 바이너리의
#    __TEXT,__entitlements 섹션으로 들어간다. 여기서 codesign --entitlements로 심으면 호스트 macOS의
#    taskgated가 "제한 entitlement를 가진 ad-hoc 프로세스"로 보고 죽인다
#    (실측: SIGKILL "Code Signature Invalid", termination "Taskgated Invalid Signature").
#    entitlements가 필요한 앱(CloudKit·App Group)은 빌드 단계에서 서명을 켜야 한다. README 참조.
xcrun simctl install "$UDID" "$APP"
log "설치 완료"

# ── defaults 사전 주입 (첫 실행 전에만 의미가 있다. 이미 실행된 앱은 cfprefsd 캐시가 이길 수 있다)
if [ -n "$DEFAULTS" ]; then
  while IFS= read -r line; do
    line=$(trim "$line")
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    # shellcheck disable=SC2086  # 키 값 인자는 의도적으로 단어 분리한다
    xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" $line </dev/null
    log "defaults: $line"
  done <<EOF
$DEFAULTS
EOF
fi

mkdir -p "$OUT"
STAMP="$OUT/.started"
touch "$STAMP"
SUMMARY="$OUT/summary.md"
{
  echo "# 찰칵 결과"
  echo
  echo "- 앱: \`$BUNDLE_ID\`"
  echo "- 기기: $DEV_NAME ($RT_NAME)"
  echo
  echo "| 화면 | 외관 | 파일 | 앱 상태 |"
  echo "|---|---|---|---|"
} > "$SUMMARY"

crashed=0
shots=0
IFS=',' read -r -a MODES <<< "$APPEARANCE"
for mode in "${MODES[@]}"; do
  mode=$(trim "$mode")
  case "$mode" in light|dark) ;; *) die "APPEARANCE 값 이상: '$mode' (light|dark)" ;; esac
  xcrun simctl ui "$UDID" appearance "$mode"
  log "외관 $mode"

  while IFS= read -r line; do
    line=$(trim "$line")
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    if [[ "$line" == *"|"* ]]; then
      name=$(trim "${line%%|*}")
      args=$(trim "${line#*|}")
    else
      name="$line"
      args=""
    fi
    [ -n "$name" ] || die "화면 이름이 비었다: '$line'"

    # 루프 안 명령엔 </dev/null : 화면 목록을 읽는 stdin(heredoc)을 삼키지 않게
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 </dev/null || true
    # 실행 거부는 스크립트를 멈추지 않는다. 컷은 찍고(홈 화면이 남는다) 상태만 남긴다.
    launched=true
    # shellcheck disable=SC2086  # 런치 인자는 의도적으로 단어 분리한다
    xcrun simctl launch "$UDID" "$BUNDLE_ID" $args >/dev/null </dev/null || launched=false
    sleep "$WAIT"
    file="$OUT/${name}-${mode}.png"
    xcrun simctl io "$UDID" screenshot "$file" >/dev/null </dev/null
    shots=$((shots + 1))

    if [ "$launched" != true ]; then
      status="실행 실패"
      crashed=$((crashed + 1))
    elif pgrep -f "/${EXEC_NAME}.app/${EXEC_NAME}" >/dev/null; then
      status="살아있음"
    else
      status="죽음"
      crashed=$((crashed + 1))
    fi
    log "$name ($mode) -> $file [$status]"
    echo "| $name | $mode | \`$(basename "$file")\` | $status |" >> "$SUMMARY"
  done <<EOF
$SCREENS
EOF
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# 크래시 리포트 회수: 이 실행 이후 생긴 것만
if [ "$crashed" -gt 0 ]; then
  mkdir -p "$OUT/crash"
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name "${EXEC_NAME}*" -newer "$STAMP" \
    -exec cp {} "$OUT/crash/" \; 2>/dev/null || true
  {
    echo
    echo "죽은 실행 ${crashed}건. 크래시 리포트: \`crash/\`"
  } >> "$SUMMARY"
fi
rm -f "$STAMP"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$SHUTDOWN" = true ]; then
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
fi

# 변수 뒤에 한글이 바로 붙으면 macOS bash가 다음 바이트까지 변수명으로 읽는다(실측: "crashed�: unbound variable"). 항상 ${}로 감싼다.
log "촬영 ${shots}컷, 죽음 ${crashed}건, 출력 $OUT/"
if [ "$crashed" -gt 0 ] && [ "$FAIL_ON_CRASH" = true ]; then
  die "촬영 중 앱이 죽은 컷이 있다 (${crashed}건). FAIL_ON_CRASH=false면 무시한다"
fi
