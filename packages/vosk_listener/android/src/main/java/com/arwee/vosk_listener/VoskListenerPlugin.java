package com.arwee.vosk_listener;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;

import androidx.annotation.NonNull;

import org.vosk.Model;
import org.vosk.Recognizer;
import org.vosk.android.RecognitionListener;
import org.vosk.android.SpeechService;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Offline speech via Vosk. One recognizer per process: the app UI (Test mode)
 * and the Ride mode service isolate each get a plugin instance, and whichever
 * started last owns the microphone and receives the events.
 */
public class VoskListenerPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private static final int MIC_REQUEST = 7311;
    private static final ExecutorService IO = Executors.newSingleThreadExecutor();

    // Shared across engines (guarded by IO's single thread).
    private static Model model;
    private static String modelPath;
    private static Recognizer recognizer;
    private static SpeechService speech;
    private static volatile VoskListenerPlugin owner;

    private final Handler main = new Handler(Looper.getMainLooper());
    private MethodChannel channel;
    private EventChannel events;
    private EventChannel.EventSink sink;
    private Context context;
    private ActivityPluginBinding activity;
    private MethodChannel.Result pendingPermission;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "pinnocate/vosk");
        channel.setMethodCallHandler(this);
        events = new EventChannel(binding.getBinaryMessenger(), "pinnocate/vosk/events");
        events.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (owner == this) IO.execute(VoskListenerPlugin::release);
        channel.setMethodCallHandler(null);
        events.setStreamHandler(null);
        sink = null;
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) { sink = events; }

    @Override
    public void onCancel(Object arguments) { sink = null; }

    private void emit(String type, String data) {
        main.post(() -> {
            if (sink == null) return;
            Map<String, Object> m = new HashMap<>();
            m.put("type", type);
            m.put("data", data);
            sink.success(m);
        });
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "hasPermission":
                result.success(hasMic());
                break;
            case "requestPermission":
                requestMic(result);
                break;
            case "start": {
                String path = call.argument("modelPath");
                String grammar = call.argument("grammar");
                IO.execute(() -> {
                    try {
                        // Keep a loaded model: switching wake -> dictation must be quick.
                        releaseSpeech();
                        if (model == null || !path.equals(modelPath)) {
                            if (model != null) model.close();
                            model = null;
                            model = new Model(path);
                            modelPath = path;
                        }
                        recognizer = grammar == null ? new Recognizer(model, 16000f) : new Recognizer(model, 16000f, grammar);
                        speech = new SpeechService(recognizer, 16000f);
                        owner = this;
                        main.post(() -> {
                            speech.startListening(listener(this));
                            result.success(true);
                        });
                    } catch (Throwable e) {
                        release();
                        main.post(() -> result.error("start_failed", String.valueOf(e.getMessage()), null));
                    }
                });
                break;
            }
            case "stop":
                IO.execute(() -> {
                    if (owner == this) release();
                    main.post(() -> result.success(null));
                });
                break;
            case "unzip": {
                String zip = call.argument("zip");
                String dest = call.argument("dest");
                IO.execute(() -> {
                    try {
                        unzip(new File(zip), new File(dest));
                        main.post(() -> result.success(null));
                    } catch (Throwable e) {
                        main.post(() -> result.error("unzip_failed", String.valueOf(e.getMessage()), null));
                    }
                });
                break;
            }
            case "vibrate":
                vibrate();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private static RecognitionListener listener(VoskListenerPlugin p) {
        return new RecognitionListener() {
            @Override public void onPartialResult(String hypothesis) { p.emit("partial", hypothesis); }
            @Override public void onResult(String hypothesis) { p.emit("result", hypothesis); }
            @Override public void onFinalResult(String hypothesis) { p.emit("result", hypothesis); }
            @Override public void onError(Exception e) { p.emit("error", String.valueOf(e.getMessage())); }
            @Override public void onTimeout() { p.emit("error", "timeout"); }
        };
    }

    private static void release() {
        releaseSpeech();
        if (model != null) {
            model.close();
            model = null;
        }
        modelPath = null;
    }

    private static void releaseSpeech() {
        if (speech != null) {
            speech.stop();
            speech.shutdown();
            speech = null;
        }
        if (recognizer != null) {
            recognizer.close();
            recognizer = null;
        }
        owner = null;
    }

    private boolean hasMic() {
        return context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestMic(MethodChannel.Result result) {
        if (hasMic()) {
            result.success(true);
            return;
        }
        Activity a = activity == null ? null : activity.getActivity();
        if (a == null || pendingPermission != null) {
            result.success(false);
            return;
        }
        pendingPermission = result;
        a.requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MIC_REQUEST);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != MIC_REQUEST || pendingPermission == null) return false;
        pendingPermission.success(grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED);
        pendingPermission = null;
        return true;
    }

    private void vibrate() {
        Vibrator v;
        if (Build.VERSION.SDK_INT >= 31) {
            VibratorManager vm = (VibratorManager) context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
            v = vm == null ? null : vm.getDefaultVibrator();
        } else {
            v = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
        }
        if (v == null || !v.hasVibrator()) return;
        v.vibrate(VibrationEffect.createWaveform(new long[]{0, 120, 90, 120}, -1));
    }

    private static void unzip(File zip, File dest) throws IOException {
        String root = dest.getCanonicalPath() + File.separator;
        byte[] buf = new byte[64 * 1024];
        try (ZipInputStream in = new ZipInputStream(new java.io.BufferedInputStream(new java.io.FileInputStream(zip)))) {
            ZipEntry e;
            while ((e = in.getNextEntry()) != null) {
                File out = new File(dest, e.getName());
                if (!out.getCanonicalPath().startsWith(root)) throw new IOException("Bad zip entry");
                if (e.isDirectory()) {
                    out.mkdirs();
                    continue;
                }
                File parent = out.getParentFile();
                if (parent != null) parent.mkdirs();
                try (OutputStream os = new FileOutputStream(out)) {
                    int n;
                    while ((n = ((InputStream) in).read(buf)) > 0) os.write(buf, 0, n);
                }
            }
        }
    }

    // ActivityAware: only the UI engine has an activity (for the permission prompt).
    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding;
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() { onDetachedFromActivity(); }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) { onAttachedToActivity(binding); }

    @Override
    public void onDetachedFromActivity() {
        if (activity != null) activity.removeRequestPermissionsResultListener(this);
        activity = null;
    }
}
