#!/bin/bash

# blue 및 green 인스턴스 이름
BLUE_INSTANCE="front_web02"
GREEN_INSTANCE="front_web"

# Docker Host IP or Host
HOST="127.0.0.1"

# 현재 nginx에서 proxypass 주소 정보(ex: set $service_url http://${HOST}:8081;)
SERVICE_URL="nginx/service_url.inc"

# 도커 레지스트리 로그인(여기서는 Azure registry 사용)
docker_login()
{
  docker login hiclass.azurecr.io -u 'USER' -p 'XXXXXXX' >/dev/null 2>&1
}

# 가장 최근에 만들어진 docker image의 태그 빌드넘버 찾기(ex: hiclass.azureecr.io/fromt:latest)
BUILD_NUMBER()
{
  docker image ls| grep hiclass.azurecr.io/front |awk '{print $2}' | head -1
}

# service-url.inc에서 포트 번호를 가져온다.
CURRENT_PORT()
{
  cat $SERVICE_URL |awk -F ':' '{print $3}'|grep -Po '[0-9]+'
}

# 블루 및 그린 인스턴스 이름을 가져온다.
EXIST_BLUE()
{
  docker container ls | grep -Po ${BLUE_INSTANCE}\$
}
EXIST_GREEN()
{
  docker container ls | grep -Po ${GREEN_INSTANCE}\$
}

# TARGET_PORT 기본값
TARGET_PORT=8080
# INSTANCE는 toggle_port_number 함수에 의해 결정된다.
INSTANCE=0

# 현재 BLUE_INSTANCE이면 GREEN_INSTANCE로 설정, 현재 GREEN_INSTANCE면 BLUE_INSTANCE로 설정
toggle_port_number()
{
  if [[ $(EXIST_BLUE) == ${BLUE_INSTANCE} ]]; then
      echo "> Select Instance ${GREEN_INSTANCE}"
      INSTANCE=${GREEN_INSTANCE}
  elif [[ $(EXIST_GREEN) == ${GREEN_INSTANCE} ]]; then
      echo "> Select Instance ${BLUE_INSTANCE}"
      INSTANCE=${BLUE_INSTANCE}
  else
      echo "> No WAS is connected to nginx"
      exit 1
  fi
}

# 블루 도커 인스턴스 시작 : front_web02
START_BLUE()
{
  docker run -d \
  --name ${BLUE_INSTANCE} \
  -v /mnt/xcms:/data \
  -v /var/log/front_web:/usr/local/tomcat/logs \
  --network educon_network \
  --network-alias web hiclass.azurecr.io/front:$(BUILD_NUMBER)
}

# 그린 도커 인스턴스 시작 : front_web02
START_GREEN()
{
  docker run -d \
  --name ${GREEN_INSTANCE} \
  -v /mnt/xcms:/data \
  -v /var/log/front_web:/usr/local/tomcat/logs \
  --network educon_network \
  --network-alias web hiclass.azurecr.io/front:$(BUILD_NUMBER)
}

# health check : 새로 실행한 도커 인스턴스가 정상적으로 실행되고 있는지 curl을 통해 확인한다.
HEALTH_CHECK()
{
  # toggle_port_number
  echo "> Start health check of WAS at 'http://${HOST}:${TARGET_PORT}' ..."
  for RETRY_COUNT in {1..10}
  do
      echo "> #${RETRY_COUNT} trying..."
      # RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}"  http://127.0.0.1:${TARGET_PORT}/health)
      RESPONSE_CODE=$(docker exec ${INSTANCE} curl -s -o /dev/null -w "%{http_code}"  http://${HOST}:${TARGET_PORT}/user/login.do)   # HTTP 응답 코드 체크
      if [[ ${RESPONSE_CODE} -eq 200 ]] || [[ ${RESPONSE_CODE} -eq 301 ]]; then
          echo "> New WAS successfully running"
          break
      elif [[ ${RETRY_COUNT} -eq 10 ]]; then
          echo "> Health check failed."
          exit 1
      fi
      sleep 10
  done
}

# nginx 서비스 트래픽을 새로운 인스턴스의 proxypass로 보냄.
SWITCH_PORT()
{
  # service-url.inc에 설정된 인스턴스명:포트번호를 변경할 인스턴스명:포트번호로 설정한다.
  echo "> Nginx currently proxies to $(CURRENT_PORT)."
  echo "set \$service_url http://${INSTANCE}:${TARGET_PORT};" | tee $SERVICE_URL
  echo "> Now Nginx proxies to ${TARGET_PORT}."
  # Reload nginx Docker
  docker exec nginx nginx -s reload  # only jenkins
  echo "> Nginx Docker reloaded."
}


# 블루 도커 인스턴스 제거
REMOVE_BLUE_INSTANCE()
{
  echo "> Stop ${BLUE_INSTANCE}"
  docker stop ${BLUE_INSTANCE}
  echo "> Remove ${BLUE_INSTANCE}"
  docker rm ${BLUE_INSTANCE}
}

# 그린 도커 인스턴스 제거
REMOVE_GREEN_INSTANCE()
{
  echo "> Stop ${GREEN_INSTANCE}"
  docker stop ${GREEN_INSTANCE}
  echo "> Remove ${GREEN_INSTANCE}"
  docker rm ${GREEN_INSTANCE}
}
