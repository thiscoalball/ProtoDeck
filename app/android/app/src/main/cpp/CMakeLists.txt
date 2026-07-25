cmake_minimum_required(VERSION 3.22.1)
project(nettools_iperf C)

set(CMAKE_C_STANDARD 11)
set(IPERF_SRC ${CMAKE_CURRENT_SOURCE_DIR}/iperf/src)
set(IPERF_MOBILE_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/mobile_config)

add_library(nettools_iperf SHARED
    nettools_iperf_jni.c
    ${IPERF_SRC}/cjson.c
    ${IPERF_SRC}/dscp.c
    ${IPERF_SRC}/iperf_api.c
    ${IPERF_SRC}/iperf_auth.c
    ${IPERF_SRC}/iperf_client_api.c
    ${IPERF_SRC}/iperf_error.c
    ${IPERF_SRC}/iperf_locale.c
    ${IPERF_SRC}/iperf_pthread.c
    ${IPERF_SRC}/iperf_sctp.c
    ${IPERF_SRC}/iperf_server_api.c
    ${IPERF_SRC}/iperf_tcp.c
    ${IPERF_SRC}/iperf_time.c
    ${IPERF_SRC}/iperf_udp.c
    ${IPERF_SRC}/iperf_util.c
    ${IPERF_SRC}/net.c
    ${IPERF_SRC}/tcp_info.c
    ${IPERF_SRC}/timer.c
    ${IPERF_SRC}/units.c
)

target_include_directories(nettools_iperf PRIVATE
    ${IPERF_MOBILE_CONFIG}
    ${IPERF_SRC}
)
target_compile_definitions(nettools_iperf PRIVATE NETTOOLS_MOBILE=1 _GNU_SOURCE=1)
target_compile_options(nettools_iperf PRIVATE -Wall -Wno-unused-parameter -Wno-sign-compare)
target_link_libraries(nettools_iperf log m)
