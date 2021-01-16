#!/bin/bash
# include function
. ./blue_green_fnc.sh
echo "> Current port of running WAS is $(CURRENT_PORT)."

# docker_login
docker_login && toggle_port_number

# 인스턴스 실행 -> health check -> switch port -> old 인스턴스 삭제
if [[ -z $(EXIST_BLUE) ]] && [[ -n $(EXIST_GREEN) ]]; then
  echo "> Start ${BLUE_INSTANCE}"
  START_BLUE
  HEALTH_CHECK && SWITCH_PORT && REMOVE_GREEN_INSTANCE
  sleep 10
elif [[ -z $(EXIST_GREEN) ]] && [[ -n $(EXIST_BLUE) ]]; then
  echo "> Start ${GREEN_INSTANCE}"
  START_GREEN
  HEALTH_CHECK && SWITCH_PORT && REMOVE_BLUE_INSTANCE
  sleep 10
else
  echo "> Unable to run instance."
  exit 1
fi

echo "> Now new WAS runs at ${INSTANCE}:${TARGET_PORT}."
exit 0
