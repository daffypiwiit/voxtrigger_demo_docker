#!/bin/bash
set -euo pipefail

mkdir -p /opt/cdr/vxt
chown -R freeswitch:freeswitch /opt/cdr/vxt

VARS=/etc/freeswitch/vars.xml
if [ -f "$VARS" ]; then
  FS_EXTERNAL_RTP_IP="${FS_EXTERNAL_RTP_IP:-auto}"
  FS_EXTERNAL_SIP_IP="${FS_EXTERNAL_SIP_IP:-auto}"

  if grep -q 'data="external_sip_port_0=' "$VARS"; then
    sed -i 's|data="external_sip_port_0=[^"]*"|data="external_sip_port_0=5080"|' "$VARS"
  else
    sed -i '/external_sip_port=5080/a\  <X-PRE-PROCESS cmd="set" data="external_sip_port_0=5080"/>' "$VARS"
  fi

  if grep -q 'data="external_rtp_ip=' "$VARS"; then
    sed -i "s|data=\"external_rtp_ip=[^\"]*\"|data=\"external_rtp_ip=${FS_EXTERNAL_RTP_IP}\"|" "$VARS"
  else
    sed -i '/external_sip_port_0=5080/a\  <X-PRE-PROCESS cmd="set" data="external_rtp_ip='"${FS_EXTERNAL_RTP_IP}"'"/>' "$VARS"
  fi

  if grep -q 'data="external_sip_ip=' "$VARS"; then
    sed -i "s|data=\"external_sip_ip=[^\"]*\"|data=\"external_sip_ip=${FS_EXTERNAL_SIP_IP}\"|" "$VARS"
  else
    sed -i '/external_rtp_ip=/a\  <X-PRE-PROCESS cmd="set" data="external_sip_ip='"${FS_EXTERNAL_SIP_IP}"'"/>' "$VARS"
  fi
fi

SWITCH_CFG=/etc/freeswitch/autoload_configs/switch.conf.xml
if [ -f "$SWITCH_CFG" ]; then
  FS_RTP_START_PORT="${FS_RTP_START_PORT:-16384}"
  FS_RTP_END_PORT="${FS_RTP_END_PORT:-32768}"

  if grep -q 'name="rtp-start-port"' "$SWITCH_CFG"; then
    sed -i "s|name=\"rtp-start-port\" value=\"[0-9]*\"|name=\"rtp-start-port\" value=\"${FS_RTP_START_PORT}\"|" "$SWITCH_CFG"
  fi
  if grep -q 'name="rtp-end-port"' "$SWITCH_CFG"; then
    sed -i "s|name=\"rtp-end-port\" value=\"[0-9]*\"|name=\"rtp-end-port\" value=\"${FS_RTP_END_PORT}\"|" "$SWITCH_CFG"
  fi
fi

ESL_CFG=/etc/freeswitch/autoload_configs/event_socket.conf.xml
if [ -f "$ESL_CFG" ]; then
  sed -i 's/name="listen-ip" value="::"/name="listen-ip" value="0.0.0.0"/' "$ESL_CFG"
fi

SIP_PROFILES_DIR=/etc/freeswitch/sip_profiles
if [ -d "$SIP_PROFILES_DIR" ]; then
  # Keep only external_0 profile to avoid bind collisions.
  for profile in "$SIP_PROFILES_DIR"/*.xml; do
    [ -f "$profile" ] || continue
    if [ "$(basename "$profile")" != "external_0.xml" ]; then
      rm -f "$profile"
    fi
  done
fi

DIALPLAN=/etc/freeswitch/dialplan/public/vmd_ai.xml
if [ -f "$DIALPLAN" ]; then
  PWT_SBC_IP="${PWT_SBC_IP:-opensips}"
  PWT_SBC_PORT="${PWT_SBC_PORT:-5060}"
  SOFIA_PROFILE_NAME="${SOFIA_PROFILE_NAME:-external_0}"
  PWT_VOXTRIGGER_IP="${PWT_VOXTRIGGER_IP:-haproxy}"
  PWT_VOXTRIGGER_PORT="${PWT_VOXTRIGGER_PORT:-8080}"
  MEDIA_OUT="${MEDIA_OUT:-false}"
  VXT_ANSWER_DETECT="${VXT_ANSWER_DETECT:-false}"
  TIMEOUTMS_ANSWER_VXT="${TIMEOUTMS_ANSWER_VXT:-2300}"
  VXT_WS_EXCLUDE_PREANSWER="${VXT_WS_EXCLUDE_PREANSWER:-}"
  VXT_WS_EXCLUDE_ANSWER="${VXT_WS_EXCLUDE_ANSWER:-}"
  esc_sed() {
    printf '%s' "$1" | sed 's/[&|]/\\&/g'
  }
  sed -i \
    -e "s|\${pwt_sbc_ip}|$(esc_sed "$PWT_SBC_IP")|g" \
    -e "s|\${pwt_sbc_port}|$(esc_sed "$PWT_SBC_PORT")|g" \
    -e "s|\${sofia_profile_name}|$(esc_sed "$SOFIA_PROFILE_NAME")|g" \
    -e "s|\${pwt_voxtrigger_ip}|$(esc_sed "$PWT_VOXTRIGGER_IP")|g" \
    -e "s|\${pwt_voxtrigger_port}|$(esc_sed "$PWT_VOXTRIGGER_PORT")|g" \
    -e "s|\${media_out}|$(esc_sed "$MEDIA_OUT")|g" \
    -e "s|\${vxt_answer_detect}|$(esc_sed "$VXT_ANSWER_DETECT")|g" \
    -e "s|\${timeoutms_answer_vxt}|$(esc_sed "$TIMEOUTMS_ANSWER_VXT")|g" \
    -e "s|\${vxt_ws_exclude_preanswer}|$(esc_sed "$VXT_WS_EXCLUDE_PREANSWER")|g" \
    -e "s|\${vxt_ws_exclude_answer}|$(esc_sed "$VXT_WS_EXCLUDE_ANSWER")|g" \
    "$DIALPLAN"
fi

FS_PID=
cleanup() {
  if [ -n "${FS_PID:-}" ] && kill -0 "$FS_PID" 2>/dev/null; then
    kill -TERM "$FS_PID" 2>/dev/null || true
    wait "$FS_PID" 2>/dev/null || true
  fi
}
trap cleanup TERM INT

/usr/bin/freeswitch -nonat -nf &
FS_PID=$!

deadline=$((SECONDS + 60))
while [ "$SECONDS" -lt "$deadline" ]; do
  if ! kill -0 "$FS_PID" 2>/dev/null; then
    wait "$FS_PID" || exit 1
    echo "FreeSWITCH exited during startup" >&2
    exit 1
  fi
  if fs_cli -H 127.0.0.1 -P 8021 -p ClueCon -x status 2>/dev/null | grep -q 'UP'; then
    wait "$FS_PID"
    exit $?
  fi
  sleep 1
done

echo "FreeSWITCH failed readiness check (event socket :8021)" >&2
kill -TERM "$FS_PID" 2>/dev/null || true
wait "$FS_PID" 2>/dev/null || true
exit 1
