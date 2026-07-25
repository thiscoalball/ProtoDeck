#include <jni.h>
#include <getopt.h>
#include <pthread.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "iperf.h"
#include "iperf_api.h"

static pthread_mutex_t run_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t active_mutex = PTHREAD_MUTEX_INITIALIZER;
static struct iperf_test *active_test = NULL;
static _Thread_local jmp_buf abort_env;
static _Thread_local int abort_ready = 0;

struct iperf_event_node {
    char *json;
    struct iperf_event_node *next;
};

static pthread_mutex_t event_mutex = PTHREAD_MUTEX_INITIALIZER;
static struct iperf_event_node *event_head = NULL;
static struct iperf_event_node *event_tail = NULL;
static size_t event_count = 0;

static void clear_event_queue(void) {
    pthread_mutex_lock(&event_mutex);
    struct iperf_event_node *node = event_head;
    while (node != NULL) {
        struct iperf_event_node *next = node->next;
        free(node->json);
        free(node);
        node = next;
    }
    event_head = NULL;
    event_tail = NULL;
    event_count = 0;
    pthread_mutex_unlock(&event_mutex);
}

static void push_event(const char *json) {
    if (json == NULL || strncmp(json, "{\"event\":", 9) != 0) return;
    struct iperf_event_node *node = calloc(1, sizeof(struct iperf_event_node));
    if (node == NULL) return;
    node->json = strdup(json);
    if (node->json == NULL) {
        free(node);
        return;
    }
    pthread_mutex_lock(&event_mutex);
    if (event_tail == NULL) {
        event_head = event_tail = node;
    } else {
        event_tail->next = node;
        event_tail = node;
    }
    event_count++;
    /* A normal session produces about one event per second. Keep a hard cap
     * so an abandoned Flutter listener cannot grow native memory forever. */
    while (event_count > 256 && event_head != NULL) {
        struct iperf_event_node *old = event_head;
        event_head = old->next;
        if (event_head == NULL) event_tail = NULL;
        event_count--;
        free(old->json);
        free(old);
    }
    pthread_mutex_unlock(&event_mutex);
}

static char *pop_event(void) {
    pthread_mutex_lock(&event_mutex);
    struct iperf_event_node *node = event_head;
    if (node == NULL) {
        pthread_mutex_unlock(&event_mutex);
        return NULL;
    }
    event_head = node->next;
    if (event_head == NULL) event_tail = NULL;
    event_count--;
    pthread_mutex_unlock(&event_mutex);
    char *json = node->json;
    free(node);
    return json;
}

static void on_json_stream_event(struct iperf_test *test, char *json) {
    (void)test;
    push_event(json);
}

void nettools_iperf_abort(int exit_code) {
    if (abort_ready) {
        longjmp(abort_env, exit_code + 1);
    }
    pthread_exit(NULL);
}

static char *copy_java_string(JNIEnv *env, jstring value) {
    const char *utf = (*env)->GetStringUTFChars(env, value, NULL);
    if (utf == NULL) return NULL;
    char *copy = strdup(utf);
    (*env)->ReleaseStringUTFChars(env, value, utf);
    return copy;
}

static jstring result_json(JNIEnv *env, int ok, int code, const char *output) {
    const char *safe = output != NULL ? output : "";
    size_t escaped_capacity = strlen(safe) * 2 + 1;
    char *escaped = calloc(escaped_capacity, 1);
    if (escaped == NULL) return (*env)->NewStringUTF(env, "{\"ok\":false,\"error\":\"out of memory\"}");
    size_t out = 0;
    for (size_t i = 0; safe[i] != '\0'; i++) {
        unsigned char c = (unsigned char)safe[i];
        const char *replacement = NULL;
        if (c == '\\') replacement = "\\\\";
        else if (c == '"') replacement = "\\\"";
        else if (c == '\n') replacement = "\\n";
        else if (c == '\r') replacement = "\\r";
        else if (c == '\t') replacement = "\\t";
        if (replacement != NULL) {
            size_t length = strlen(replacement);
            memcpy(escaped + out, replacement, length);
            out += length;
        } else if (c >= 0x20) {
            escaped[out++] = (char)c;
        }
    }
    size_t capacity = out + 96;
    char *json = calloc(capacity, 1);
    if (json == NULL) {
        free(escaped);
        return (*env)->NewStringUTF(env, "{\"ok\":false,\"error\":\"out of memory\"}");
    }
    snprintf(json, capacity, "{\"ok\":%s,\"exitCode\":%d,\"output\":\"%s\"}", ok ? "true" : "false", code, escaped);
    jstring result = (*env)->NewStringUTF(env, json);
    free(json);
    free(escaped);
    return result;
}

JNIEXPORT jstring JNICALL
Java_com_nettools_nettools_1mobile_IperfNative_run(JNIEnv *env, jclass clazz, jobjectArray java_args) {
    (void)clazz;
    if (pthread_mutex_trylock(&run_mutex) != 0) {
        return result_json(env, 0, -2, "another iPerf session is already running");
    }
    clear_event_queue();

    int arg_count = (int)(*env)->GetArrayLength(env, java_args);
    int argc = arg_count + 1;
    char **argv = calloc((size_t)argc + 1, sizeof(char *));
    struct iperf_test *volatile test = NULL;
    char *output_copy = NULL;
    int rc = -1;
    if (argv == NULL) goto cleanup;
    argv[0] = strdup("iperf3");
    for (int i = 0; i < arg_count; i++) {
        jstring value = (jstring)(*env)->GetObjectArrayElement(env, java_args, i);
        argv[i + 1] = copy_java_string(env, value);
        (*env)->DeleteLocalRef(env, value);
        if (argv[i + 1] == NULL) goto cleanup;
    }

    test = iperf_new_test();
    if (test == NULL) goto cleanup;
    iperf_defaults((struct iperf_test *)test);
    /* getopt_long() keeps process-global parsing state. A mobile process runs
     * many iPerf sessions, and error/abort paths do not always reach
     * iperf_parse_arguments()'s trailing reset. Without this, a later `-c` or
     * `-s` can be skipped and libiperf reports IENOROLE. */
    optind = 1;
    optarg = NULL;
    optopt = 0;
    opterr = 0;
    i_errno = IENONE;
    if (iperf_parse_arguments((struct iperf_test *)test, argc, argv) < 0) {
        output_copy = strdup(iperf_strerror(i_errno));
        rc = -3;
        goto cleanup;
    }
    if (iperf_get_test_role((struct iperf_test *)test) != 's' &&
        iperf_get_test_connect_timeout((struct iperf_test *)test) < 0) {
        /* Keep an unreachable LAN target from blocking the mobile UI forever. */
        iperf_set_test_connect_timeout((struct iperf_test *)test, 5000);
    }
    iperf_set_test_json_output((struct iperf_test *)test, 1);
    iperf_set_test_json_stream((struct iperf_test *)test, 1);
    iperf_set_test_json_stream_full_output((struct iperf_test *)test, 1);
    iperf_set_test_json_callback((struct iperf_test *)test, on_json_stream_event);

    pthread_mutex_lock(&active_mutex);
    active_test = (struct iperf_test *)test;
    pthread_mutex_unlock(&active_mutex);

    abort_ready = 1;
    int aborted = setjmp(abort_env);
    if (aborted == 0) {
        char role = iperf_get_test_role((struct iperf_test *)test);
        rc = role == 's'
            ? iperf_run_server((struct iperf_test *)test)
            : iperf_run_client((struct iperf_test *)test);
    } else {
        rc = -100 - aborted;
    }
    abort_ready = 0;

    const char *json_output = iperf_get_test_json_output_string((struct iperf_test *)test);
    if (json_output != NULL) output_copy = strdup(json_output);
    if (output_copy == NULL) output_copy = strdup(iperf_strerror(i_errno));

cleanup:
    pthread_mutex_lock(&active_mutex);
    active_test = NULL;
    pthread_mutex_unlock(&active_mutex);
    if (test != NULL) {
        iperf_free_test((struct iperf_test *)test);
    }
    if (argv != NULL) {
        for (int i = 0; i < argc; i++) free(argv[i]);
        free(argv);
    }
    jstring result = result_json(env, rc == 0, rc, output_copy != NULL ? output_copy : "iPerf initialization failed");
    free(output_copy);
    pthread_mutex_unlock(&run_mutex);
    return result;
}

JNIEXPORT jboolean JNICALL
Java_com_nettools_nettools_1mobile_IperfNative_stop(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    int stopped = 0;
    pthread_mutex_lock(&active_mutex);
    struct iperf_test *test = active_test;
    if (test != NULL) {
        iperf_set_test_state(test, IPERF_DONE);
        int sockets[] = {test->ctrl_sck, test->listener, test->prot_listener};
        for (size_t i = 0; i < sizeof(sockets) / sizeof(sockets[0]); i++) {
            if (sockets[i] >= 0) shutdown(sockets[i], SHUT_RDWR);
        }
        stopped = 1;
    }
    pthread_mutex_unlock(&active_mutex);
    return stopped ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_nettools_nettools_1mobile_IperfNative_isRunning(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    pthread_mutex_lock(&active_mutex);
    int running = active_test != NULL;
    pthread_mutex_unlock(&active_mutex);
    return running ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_nettools_nettools_1mobile_IperfNative_pollEvent(JNIEnv *env, jclass clazz) {
    (void)clazz;
    char *json = pop_event();
    if (json == NULL) return NULL;
    jstring result = (*env)->NewStringUTF(env, json);
    free(json);
    return result;
}
