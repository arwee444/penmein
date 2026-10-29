package com.arwee.vosk_listener;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;

import androidx.annotation.NonNull;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;

import org.vosk.Model;
import org.vosk.Recognizer;

import java.io.ByteArrayOutputStream;
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
    private static final Map<String, Model> models = new HashMap<>();
    private static Recognizer recognizer;
    private static AudioRecord audio;
    private static Thread micThread;
    private static volatile boolean running;
    private static volatile VoskListenerPlugin owner;
    private static final int SAMPLE_RATE = 16000;
    private static final Object PCM_LOCK = new Object();
    private static ByteArrayOutputStream pcm;

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
                Boolean keep = call.argument("record");
                IO.execute(() -> {
                    try {
                        // Keep loaded models: switching wake -> dictation must be quick,
                        // even when the two use different models.
                        releaseSpeech();
                        Model model = models.get(path);
                        if (model == null) {
                            model = new Model(path);
                            models.put(path, model);
                        }
                        recognizer = grammar == null ? new Recognizer(model, SAMPLE_RATE) : new Recognizer(model, SAMPLE_RATE, grammar);
                        synchronized (PCM_LOCK) {
                            pcm = Boolean.TRUE.equals(keep) ? new ByteArrayOutputStream(SAMPLE_RATE * 2 * 30) : null;
                        }
                        owner = this;
                        startMic(this);
                        main.post(() -> result.success(true));
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
            case "takeAudio":
                result.success(takeAudio());
                break;
            case "vibrate":
                vibrate();
                result.success(null);
                break;
            case "beep":
                beep(call.argument("kind"));
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    /**
     * Our own mic loop (instead of Vosk's SpeechService) so the raw audio of a
     * note can also be kept for Whisper. Same source and format Vosk uses.
     */
    private static void startMic(VoskListenerPlugin p) {
        int min = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
        AudioRecord r = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, Math.max(min, SAMPLE_RATE));
        if (r.getState() != AudioRecord.STATE_INITIALIZED) {
            r.release();
            throw new IllegalStateException("Microphone unavailable");
        }
        r.startRecording();
        if (r.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) {
            r.release();
            throw new IllegalStateException("Microphone busy");
        }
        audio = r;
        running = true;
        final Recognizer rec = recognizer;
        micThread = new Thread(() -> {
            short[] buf = new short[SAMPLE_RATE / 10];
            byte[] bytes = new byte[buf.length * 2];
            while (running) {
                int n = r.read(buf, 0, buf.length);
                if (n < 0) {
                    if (running) p.emit("error", "read " + n);
                    break;
                }
                if (n == 0) continue;
                synchronized (PCM_LOCK) {
                    if (pcm != null) {
                        for (int i = 0; i < n; i++) {
                            bytes[2 * i] = (byte) buf[i];
                            bytes[2 * i + 1] = (byte) (buf[i] >> 8);
                        }
                        pcm.write(bytes, 0, n * 2);
                    }
                }
                if (rec.acceptWaveForm(buf, n)) {
                    p.emit("result", rec.getResult());
                } else {
                    p.emit("partial", rec.getPartialResult());
                }
            }
        }, "vosk-mic");
        micThread.start();
    }

    /** The audio kept since start(record: true), as 16 kHz mono PCM16 LE; stops keeping more. */
    private static byte[] takeAudio() {
        synchronized (PCM_LOCK) {
            byte[] out = pcm == null ? null : pcm.toByteArray();
            pcm = null;
            return out;
        }
    }

    private static void release() {
        releaseSpeech();
        for (Model m : models.values()) m.close();
        models.clear();
    }

    private static void releaseSpeech() {
        running = false;
        if (micThread != null) {
            try {
                micThread.join(1500);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
            micThread = null;
        }
        if (audio != null) {
            try {
                audio.stop();
            } catch (IllegalStateException ignored) {
                // Already stopped.
            }
            audio.release();
            audio = null;
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

    /** start = one high beep, end = two beeps, fail = low "nope". Follows notification volume. */
    private void beep(String kind) {
        int tone, ms;
        if ("start".equals(kind)) { tone = ToneGenerator.TONE_PROP_BEEP; ms = 200; }
        else if ("end".equals(kind)) { tone = ToneGenerator.TONE_PROP_ACK; ms = 400; }
        else { tone = ToneGenerator.TONE_PROP_NACK; ms = 400; }
        try {
            ToneGenerator g = new ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90);
            g.startTone(tone, ms);
            main.postDelayed(g::release, ms + 300);
        } catch (RuntimeException ignored) {
            // No audio hardware available right now: the vibration still confirms.
        }
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
