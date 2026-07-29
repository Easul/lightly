package lightly.tool.plugin.webrtc

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import org.json.JSONObject
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.DataChannel
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.audio.JavaAudioDeviceModule

internal class WebRtcVoiceSession(
    private val context: Context,
    private val handler: Handler,
    private val emit: (JSONObject) -> Unit,
) {
    private var factory: PeerConnectionFactory? = null
    private var audioDeviceModule: JavaAudioDeviceModule? = null
    private var audioSource: AudioSource? = null
    private var localAudioTrack: AudioTrack? = null
    private var peerConnection: PeerConnection? = null
    private val pendingRemoteCandidates = mutableListOf<IceCandidate>()
    private var hasRemoteDescription = false
    private var isController = false
    private var localAudioEnabled = false
    private var previousAudioMode: Int? = null
    private var previousSpeakerphone: Boolean? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null

    val prepared: Boolean
        get() = peerConnection != null

    fun prepare(controller: Boolean, completion: (Result<Unit>) -> Unit) {
        if (prepared) {
            completion(Result.success(Unit))
            return
        }
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            completion(Result.failure(SecurityException("插件尚未获得麦克风权限")))
            return
        }
        runCatching {
            isController = controller
            configureAudioRoute()
            initializeFactory()
            val createdConnection = createPeerConnection()
                ?: error("WebRTC PeerConnection 创建失败")
            val createdSource = factory!!.createAudioSource(createAudioConstraints())
            val createdTrack = factory!!.createAudioTrack("lightly-audio", createdSource)
            createdTrack.setEnabled(false)
            createdConnection.addTrack(createdTrack, listOf("lightly-audio-stream"))
            peerConnection = createdConnection
            audioSource = createdSource
            localAudioTrack = createdTrack
            localAudioEnabled = false
            hasRemoteDescription = false
            pendingRemoteCandidates.clear()
            emitLog("webrtc-native-prepared: controller=$controller track=${createdTrack.id()}")
        }.onFailure {
            close()
            completion(Result.failure(it))
        }.onSuccess {
            if (controller) {
                createOffer(completion)
            } else {
                completion(Result.success(Unit))
            }
        }
    }

    fun setLocalAudioEnabled(enabled: Boolean): Result<Unit> {
        val track = localAudioTrack
            ?: return Result.failure(IllegalStateException("WebRTC voice session not prepared"))
        track.setEnabled(enabled)
        audioDeviceModule?.setMicrophoneMute(!enabled)
        localAudioEnabled = enabled
        configureAudioRoute()
        emitLog("webrtc-native-local-audio: enabled=$enabled track=${track.enabled()}")
        emitState()
        return Result.success(Unit)
    }

    fun handleSignal(action: String, data: JSONObject, completion: (Result<Unit>) -> Unit) {
        when (action) {
            "webrtc_offer" -> handleOffer(data, completion)
            "webrtc_answer" -> handleAnswer(data, completion)
            "webrtc_candidate" -> handleCandidate(data, completion)
            else -> completion(Result.failure(IllegalArgumentException("未知 WebRTC 信令：$action")))
        }
    }

    fun stateJson(): JSONObject = JSONObject()
        .put("prepared", prepared)
        .put("localAudioEnabled", localAudioEnabled)

    fun close() {
        pendingRemoteCandidates.clear()
        hasRemoteDescription = false
        localAudioEnabled = false
        runCatching { localAudioTrack?.setEnabled(false) }
        runCatching { peerConnection?.close() }
        runCatching { peerConnection?.dispose() }
        peerConnection = null
        runCatching { localAudioTrack?.dispose() }
        localAudioTrack = null
        runCatching { audioSource?.dispose() }
        audioSource = null
        runCatching { factory?.dispose() }
        factory = null
        runCatching { audioDeviceModule?.release() }
        audioDeviceModule = null
        restoreAudioRoute()
        emitLog("webrtc-native-closed")
        emitState()
    }

    private fun initializeFactory() {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setEnableInternalTracer(false)
                .createInitializationOptions(),
        )
        val useHardwareProcessing = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val audioModule = JavaAudioDeviceModule.builder(context)
            .setUseHardwareAcousticEchoCanceler(useHardwareProcessing)
            .setUseHardwareNoiseSuppressor(useHardwareProcessing)
            .setUseLowLatency(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            .createAudioDeviceModule()
        if (JavaAudioDeviceModule.isBuiltInNoiseSuppressorSupported()) {
            audioModule.setNoiseSuppressorEnabled(true)
        }
        audioDeviceModule = audioModule
        factory = PeerConnectionFactory.builder()
            .setAudioDeviceModule(audioModule)
            .createPeerConnectionFactory()
    }

    private fun createPeerConnection(): PeerConnection? {
        val iceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer(),
        )
        val configuration = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }
        return factory?.createPeerConnection(configuration, createPeerConstraints(), observer)
    }

    private val observer = object : PeerConnection.Observer {
        override fun onSignalingChange(state: PeerConnection.SignalingState) =
            postLog("webrtc-native-signaling-state: $state")

        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
            handler.post {
                emitLog("webrtc-native-ice-state: $state")
                if (state == PeerConnection.IceConnectionState.FAILED ||
                    state == PeerConnection.IceConnectionState.DISCONNECTED
                ) {
                    emitInterrupted("ice-$state")
                }
            }
        }

        override fun onConnectionChange(state: PeerConnection.PeerConnectionState) {
            handler.post {
                emitLog("webrtc-native-state: $state")
                if (state == PeerConnection.PeerConnectionState.FAILED ||
                    state == PeerConnection.PeerConnectionState.DISCONNECTED
                ) {
                    emitInterrupted("peer-$state")
                }
            }
        }

        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) =
            postLog("webrtc-native-gathering-state: $state")

        override fun onIceCandidate(candidate: IceCandidate) {
            handler.post {
                emit(
                    JSONObject()
                        .put("type", "signal")
                        .put("action", "webrtc_candidate")
                        .put(
                            "data",
                            JSONObject()
                                .put("candidate", candidate.sdp)
                                .put("sdpMid", candidate.sdpMid)
                                .put("sdpMLineIndex", candidate.sdpMLineIndex),
                        ),
                )
            }
        }

        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) = Unit
        override fun onAddStream(stream: MediaStream) = Unit
        override fun onRemoveStream(stream: MediaStream) = Unit
        override fun onDataChannel(channel: DataChannel) = Unit
        override fun onRenegotiationNeeded() = Unit

        override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {
            retainRemoteAudio(receiver.track())
        }

        override fun onTrack(transceiver: RtpTransceiver) {
            retainRemoteAudio(transceiver.receiver.track())
        }
    }

    private fun retainRemoteAudio(track: org.webrtc.MediaStreamTrack?) {
        handler.post {
            if (track is AudioTrack) {
                track.setEnabled(true)
                if (!isController) {
                    track.setVolume(RECEIVER_VOLUME_BOOST)
                }
                emitLog(
                    "webrtc-native-remote-audio: track=${track.id()} enabled=${track.enabled()} receiver=${!isController}",
                )
            }
        }
    }

    private fun createOffer(completion: (Result<Unit>) -> Unit) {
        val connection = peerConnection
            ?: return completion(Result.failure(IllegalStateException("WebRTC voice session not prepared")))
        connection.createOffer(
            creatingSdpObserver(
                onSuccess = { offer ->
                    setLocalDescription(offer) { result ->
                        result.onSuccess {
                            emitSignal("webrtc_offer", offer)
                            completion(Result.success(Unit))
                        }.onFailure { completion(Result.failure(it)) }
                    }
                },
                onFailure = { completion(Result.failure(it)) },
            ),
            offerConstraints(),
        )
    }

    private fun handleOffer(data: JSONObject, completion: (Result<Unit>) -> Unit) {
        val sdp = data.optString("sdp")
        if (sdp.isBlank()) {
            completion(Result.failure(IllegalArgumentException("WebRTC offer SDP 为空")))
            return
        }
        val offer = SessionDescription(
            SessionDescription.Type.fromCanonicalForm(data.optString("type", "offer")),
            sdp,
        )
        setRemoteDescription(offer) { remoteResult ->
            remoteResult.onFailure {
                completion(Result.failure(it))
                return@setRemoteDescription
            }
            val connection = peerConnection
                ?: return@setRemoteDescription completion(
                    Result.failure(IllegalStateException("WebRTC voice session not prepared")),
                )
            connection.createAnswer(
                creatingSdpObserver(
                    onSuccess = { answer ->
                        setLocalDescription(answer) { localResult ->
                            localResult.onSuccess {
                                emitSignal("webrtc_answer", answer)
                                completion(Result.success(Unit))
                            }.onFailure { completion(Result.failure(it)) }
                        }
                    },
                    onFailure = { completion(Result.failure(it)) },
                ),
                offerConstraints(),
            )
        }
    }

    private fun handleAnswer(data: JSONObject, completion: (Result<Unit>) -> Unit) {
        val sdp = data.optString("sdp")
        if (sdp.isBlank()) {
            completion(Result.failure(IllegalArgumentException("WebRTC answer SDP 为空")))
            return
        }
        setRemoteDescription(
            SessionDescription(
                SessionDescription.Type.fromCanonicalForm(data.optString("type", "answer")),
                sdp,
            ),
            completion,
        )
    }

    private fun handleCandidate(data: JSONObject, completion: (Result<Unit>) -> Unit) {
        val candidateSdp = data.optString("candidate")
        if (candidateSdp.isBlank()) {
            completion(Result.failure(IllegalArgumentException("WebRTC candidate 为空")))
            return
        }
        val candidate = IceCandidate(
            data.optString("sdpMid").takeIf { it.isNotEmpty() },
            data.optInt("sdpMLineIndex", 0),
            candidateSdp,
        )
        val connection = peerConnection
            ?: return completion(Result.failure(IllegalStateException("WebRTC voice session not prepared")))
        if (!hasRemoteDescription) {
            pendingRemoteCandidates += candidate
            completion(Result.success(Unit))
            return
        }
        if (connection.addIceCandidate(candidate)) {
            completion(Result.success(Unit))
        } else {
            completion(Result.failure(IllegalStateException("添加 WebRTC candidate 失败")))
        }
    }

    private fun setLocalDescription(
        description: SessionDescription,
        completion: (Result<Unit>) -> Unit,
    ) {
        val connection = peerConnection
            ?: return completion(Result.failure(IllegalStateException("WebRTC voice session not prepared")))
        connection.setLocalDescription(settingSdpObserver(completion), description)
    }

    private fun setRemoteDescription(
        description: SessionDescription,
        completion: (Result<Unit>) -> Unit,
    ) {
        val connection = peerConnection
            ?: return completion(Result.failure(IllegalStateException("WebRTC voice session not prepared")))
        connection.setRemoteDescription(
            settingSdpObserver { result ->
                result.onSuccess {
                    hasRemoteDescription = true
                    flushRemoteCandidates()
                }
                completion(result)
            },
            description,
        )
    }

    private fun flushRemoteCandidates() {
        val connection = peerConnection ?: return
        val pending = pendingRemoteCandidates.toList()
        pendingRemoteCandidates.clear()
        pending.forEach(connection::addIceCandidate)
        if (pending.isNotEmpty()) {
            emitLog("webrtc-native-candidate-flush: count=${pending.size}")
        }
    }

    private fun creatingSdpObserver(
        onSuccess: (SessionDescription) -> Unit,
        onFailure: (Throwable) -> Unit,
    ) = object : SdpObserver {
        override fun onCreateSuccess(description: SessionDescription) {
            handler.post { onSuccess(description) }
        }

        override fun onCreateFailure(error: String) {
            handler.post { onFailure(IllegalStateException(error)) }
        }

        override fun onSetSuccess() = Unit
        override fun onSetFailure(error: String) = Unit
    }

    private fun settingSdpObserver(completion: (Result<Unit>) -> Unit) = object : SdpObserver {
        override fun onSetSuccess() {
            handler.post { completion(Result.success(Unit)) }
        }

        override fun onSetFailure(error: String) {
            handler.post { completion(Result.failure(IllegalStateException(error))) }
        }

        override fun onCreateSuccess(description: SessionDescription) = Unit
        override fun onCreateFailure(error: String) = Unit
    }

    private fun emitSignal(action: String, description: SessionDescription) {
        emit(
            JSONObject()
                .put("type", "signal")
                .put("action", action)
                .put(
                    "data",
                    JSONObject()
                        .put("sdp", description.description)
                        .put("type", description.type.canonicalForm()),
                ),
        )
        emitLog("webrtc-native-signal-created: $action sdpLength=${description.description.length}")
    }

    private fun emitInterrupted(reason: String) {
        emit(JSONObject().put("type", "connectionInterrupted").put("reason", reason))
    }

    private fun emitState() {
        emit(JSONObject().put("type", "state").put("data", stateJson()))
    }

    private fun emitLog(message: String) {
        emit(JSONObject().put("type", "log").put("message", message))
    }

    private fun postLog(message: String) {
        handler.post { emitLog(message) }
    }

    private fun configureAudioRoute() {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (previousAudioMode == null) {
            previousAudioMode = manager.mode
            @Suppress("DEPRECATION")
            previousSpeakerphone = manager.isSpeakerphoneOn
        }
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        registerAudioDeviceCallback(manager)
        val wiredDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.availableCommunicationDevices.firstOrNull(::isWiredAudioDevice)
        } else {
            null
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && wiredDevice != null) {
            @Suppress("DEPRECATION")
            manager.isSpeakerphoneOn = false
            if (manager.communicationDevice?.id != wiredDevice.id) {
                manager.setCommunicationDevice(wiredDevice)
            }
            emitLog("webrtc-native-audio-route: wired type=${wiredDevice.type}")
            return
        }
        @Suppress("DEPRECATION")
        if (manager.isWiredHeadsetOn) {
            @Suppress("DEPRECATION")
            manager.isSpeakerphoneOn = false
            emitLog("webrtc-native-audio-route: wired-legacy")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.clearCommunicationDevice()
        }
        @Suppress("DEPRECATION")
        manager.isSpeakerphoneOn = true
        emitLog("webrtc-native-audio-route: speaker")
    }

    private fun restoreAudioRoute() {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioDeviceCallback?.let(manager::unregisterAudioDeviceCallback)
        audioDeviceCallback = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.clearCommunicationDevice()
        }
        previousAudioMode?.let { manager.mode = it }
        previousSpeakerphone?.let {
            @Suppress("DEPRECATION")
            manager.isSpeakerphoneOn = it
        }
        previousAudioMode = null
        previousSpeakerphone = null
    }

    private fun registerAudioDeviceCallback(manager: AudioManager) {
        if (audioDeviceCallback != null) return
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                handler.post(::configureAudioRoute)
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                handler.post(::configureAudioRoute)
            }
        }
        audioDeviceCallback = callback
        manager.registerAudioDeviceCallback(callback, handler)
    }

    private fun isWiredAudioDevice(device: AudioDeviceInfo): Boolean = when (device.type) {
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> true
        else -> false
    }

    private fun createPeerConstraints() = MediaConstraints().apply {
        optional += MediaConstraints.KeyValuePair("DtlsSrtpKeyAgreement", "true")
    }

    private fun createAudioConstraints() = MediaConstraints().apply {
        mandatory += MediaConstraints.KeyValuePair("googEchoCancellation", "true")
        mandatory += MediaConstraints.KeyValuePair("googNoiseSuppression", "true")
        mandatory += MediaConstraints.KeyValuePair("googAutoGainControl", "false")
        mandatory += MediaConstraints.KeyValuePair("googHighpassFilter", "true")
        mandatory += MediaConstraints.KeyValuePair("googTypingNoiseDetection", "true")
    }

    private fun offerConstraints() = MediaConstraints().apply {
        mandatory += MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true")
        mandatory += MediaConstraints.KeyValuePair("OfferToReceiveVideo", "false")
    }

    companion object {
        private const val RECEIVER_VOLUME_BOOST = 1.6
    }
}
