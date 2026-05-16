package com.proxy.core

object ProxyCore {
    init {
        System.loadLibrary("proxy_core")
    }

    @JvmStatic
    external fun nativeInit(logLevel: String): Int

    @JvmStatic
    external fun nativeStart(listenAddr: String, config: String): Int

    @JvmStatic
    external fun nativeStop(): Int

    @JvmStatic
    fun startWithVless(
        logLevel: String = "info",
        listenAddr: String = "127.0.0.1:23333",
        vlessConfig: VlessConfig
    ): Int {
        val initResult = nativeInit(logLevel)
        if (initResult != 0) {
            return initResult
        }
        
        val configJson = buildConfigJson(vlessConfig)
        return nativeStart(listenAddr, configJson)
    }

    @JvmStatic
    fun stopService(): Int = nativeStop()

    private fun buildConfigJson(config: VlessConfig): String = """
        {
            "vless": {
                "uuid": "${config.uuid}",
                "server_addr": "${config.serverAddr}",
                "server_port": ${config.serverPort},
                "security": "${config.security}",
                "host": "${config.host}",
                "sni": "${config.sni}",
                "path": "${config.path}"
            }
        }
    """.trimIndent()

    data class VlessConfig(
        val uuid: String,
        val serverAddr: String,
        val serverPort: Int = 443,
        val security: String = "tls",
        val host: String? = null,
        val sni: String? = null,
        val path: String = "/"
    ) {
        init {
            require(uuid.isNotBlank())
            require(serverAddr.isNotBlank())
        }
    }

    enum class Status {
        IDLE,
        INITIALIZED,
        RUNNING,
        STOPPED,
        ERROR
    }
}
