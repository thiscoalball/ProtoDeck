#ifndef NETTOOLS_IPERF_CONFIG_H
#define NETTOOLS_IPERF_CONFIG_H

/* Android NDK feature configuration for the embedded iPerf 3.21 library. */
#define _GNU_SOURCE 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_CLOCK_NANOSLEEP 1
#define HAVE_ENDIAN_H 1
#define HAVE_GETLINE 1
#define HAVE_INTTYPES_H 1
#define HAVE_MSG_TRUNC 1
#define HAVE_NANOSLEEP 1
#define HAVE_POLL_H 1
#define HAVE_PTHREAD 1
#define HAVE_SENDFILE 1
#define HAVE_SOCKET_SHUTDOWN_SHUT_WR 1
#define HAVE_STDATOMIC_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAVE_TCP_CONGESTION 1
#define HAVE_TCP_KEEPALIVE 1
#define HAVE_TCP_USER_TIMEOUT 1
#define STDC_HEADERS 1

#define PACKAGE "iperf"
#define PACKAGE_NAME "iperf"
#define PACKAGE_STRING "iperf 3.21"
#define PACKAGE_TARNAME "iperf"
#define PACKAGE_URL "https://software.es.net/iperf/"
#define PACKAGE_VERSION "3.21"
#define PACKAGE_BUGREPORT "https://github.com/esnet/iperf/issues"
#define VERSION "3.21"

#endif
