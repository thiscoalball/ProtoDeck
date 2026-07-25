package com.nettools.nettools_mobile

internal object IperfNative {
    init {
        System.loadLibrary("nettools_iperf")
    }

    external fun run(arguments: Array<String>): String
    external fun stop(): Boolean
    external fun isRunning(): Boolean
    external fun pollEvent(): String?
}
