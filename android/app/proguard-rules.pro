# Flutter ProGuard Rules
# Keep Flutter-specific classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep dart:convert JSON serialization
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep WebView classes
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keepclassmembers class com.pichillilorenzo.flutter_inappwebview.** { *; }

# Keep crypto classes
-keep class com.google.crypto.tink.** { *; }

# Keep SharedPreferences
-keep class android.content.SharedPreferences { *; }

# Keep sqflite
-keep class com.tekartik.sqflite.** { *; }

# General Flutter keep rules
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeInvisibleParameterAnnotations

# Don't warn about missing classes
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi
-dontwarn javax.annotation.Nullable
-dontwarn javax.annotation.ParametersAreNonnullByDefault
-dontwarn org.chromium.base.JniStaticTestMocker
-dontwarn org.chromium.base.annotations.UsedByReflection
-dontwarn org.chromium.content.browser.ContactsDialogHost
-dontwarn org.chromium.content.browser.DeviceOrientationEventListener
-dontwarn org.chromium.content.browser.FloatingActionModeCallback
-dontwarn org.chromium.content.browser.GestureListenerManagerImpl
-dontwarn org.chromium.content.browser.InputDialogContainer
-dontwarn org.chromium.content.browser.JavascriptInterface
-dontwarn org.chromium.content.browser.PopupController
-dontwarn org.chromium.content.browser.SelectPopup
-dontwarn org.chromium.content.browser.SelectPopupDialog
-dontwarn org.chromium.content.browser.SelectPopupDropdown
-dontwarn org.chromium.content.browser.accessibility.WebContentsAccessibilityImpl
-dontwarn org.chromium.content.browser.accessibility.captioning.SystemCaptioningBridge
-dontwarn org.chromium.content.browser.framehost.NavigationControllerImpl
-dontwarn org.chromium.content.browser.framehost.RenderFrameHostImpl
-dontwarn org.chromium.content.browser.input.ChromiumBaseTextSelectionHandleView
-dontwarn org.chromium.content.browser.input.DateTimePickerDialog
-dontwarn org.chromium.content.browser.input.GamepadList
-dontwarn org.chromium.content.browser.input.ImeAdapterImpl
-dontwarn org.chromium.content.browser.input.SelectPopupDropdownAdapter
-dontwarn org.chromium.content.browser.input.SelectPopupItem
-dontwarn org.chromium.content.browser.input.TextSuggestionHost
-dontwarn org.chromium.content.browser.picker.DateTimeSuggestion
-dontwarn org.chromium.content.browser.picker.InputDialogContainer
-dontwarn org.chromium.content_public.browser.JavascriptInjector
-dontwarn org.chromium.content_public.browser.NavigationHandle
-dontwarn org.chromium.content_public.browser.WebContents
-dontwarn org.chromium.content_public.browser.navigation_controller.NavigationEntry
-dontwarn org.chromium.device.bluetooth.Wrappers
-dontwarn org.chromium.media.AudioManagerAndroid
-dontwarn org.chromium.media.MediaCodecBridge
-dontwarn org.chromium.media.MediaCodecUtil
-dontwarn org.chromium.media.midi.UsbMidiDeviceAndroid
-dontwarn org.chromium.midi.UsbMidiDeviceFactoryAndroid
-dontwarn org.chromium.net.AndroidCellularSignalStrength
-dontwarn org.chromium.net.AndroidKeyStore
-dontwarn org.chromium.net.AndroidTrafficStats
-dontwarn org_proxy
# Google Play Core (referenced by Flutter deferred components)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
# Loaded reflectively by YouTubeResolverChannelHandler when the private AAR is bundled.
-keep class lightly.youtube.resolver.YouTubeResolverBridge { public *; }
