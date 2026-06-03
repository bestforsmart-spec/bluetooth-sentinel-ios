package com.bestforsmart.btsentinel;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class MainActivity extends Activity {
    private static final long QUIET_START_MS = 60_000L;
    private static final long RSSI_WINDOW_MS = 8_000L;
    private static final long UI_UPDATE_MS = 1_000L;
    private static final long APPROACH_WINDOW_MS = 12_000L;
    private static final long AUTO_KNOWN_MS = 5L * 60L * 1_000L;
    private static final long STALE_MS = 60_000L;
    private static final int MIN_AUTO_KNOWN_SAMPLES = 20;
    private static final int RSSI_DEADBAND_DBM = 3;
    private static final int APPROACH_GAIN_DBM = 8;
    private static final int DARK_BG = Color.rgb(7, 12, 15);
    private static final int DARK_CARD = Color.rgb(19, 27, 31);
    private static final int DARK_TEXT = Color.rgb(235, 242, 241);
    private static final int LIGHT_BG = Color.rgb(243, 245, 248);
    private static final int LIGHT_CARD = Color.WHITE;
    private static final int LIGHT_TEXT = Color.rgb(12, 18, 22);
    private static final int GREEN = Color.rgb(42, 199, 124);
    private static final int ORANGE = Color.rgb(242, 153, 74);
    private static final int RED = Color.rgb(234, 84, 85);
    private static final int TEAL = Color.rgb(12, 124, 132);

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Map<String, DeviceState> devices = new HashMap<>();
    private final Set<String> discoveryAlerted = new HashSet<>();
    private final Set<String> approachAlerted = new HashSet<>();
    private final Map<String, String> unnamedLabels = new HashMap<>();
    private int nextUnnamedNumber = 1;
    private BluetoothAdapter adapter;
    private BluetoothLeScanner scanner;
    private ToneGenerator tone;
    private Vibrator vibrator;
    private LinearLayout root;
    private LinearLayout deviceList;
    private TextView statusTitle;
    private TextView statusSubtitle;
    private TextView totalCount;
    private TextView newCount;
    private TextView knownCount;
    private TextView quietBadge;
    private Button soundButton;
    private Button themeButton;
    private boolean scanning;
    private boolean darkMode = true;
    private boolean soundEnabled = true;
    private long quietStartEndsAt;

    private final ScanCallback callback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            handleScan(result);
        }

        @Override
        public void onBatchScanResults(List<ScanResult> results) {
            for (ScanResult result : results) {
                handleScan(result);
            }
        }

        @Override
        public void onScanFailed(int errorCode) {
            statusSubtitle.setText("Ошибка сканирования: " + errorCode);
            scanning = false;
            render();
        }
    };

    private final Runnable uiTick = new Runnable() {
        @Override
        public void run() {
            updateDisplayedValues();
            cleanupStaleDevices();
            render();
            handler.postDelayed(this, UI_UPDATE_MS);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        quietStartEndsAt = now() + QUIET_START_MS;
        BluetoothManager manager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        adapter = manager == null ? null : manager.getAdapter();
        vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        tone = new ToneGenerator(AudioManager.STREAM_ALARM, 90);

        buildUi();
        requestNeededPermissions();
        handler.post(uiTick);
    }

    @Override
    protected void onResume() {
        super.onResume();
        startScanIfReady();
    }

    @Override
    protected void onPause() {
        super.onPause();
        stopScan();
    }

    @Override
    protected void onDestroy() {
        stopScan();
        handler.removeCallbacksAndMessages(null);
        if (tone != null) {
            tone.release();
        }
        super.onDestroy();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        startScanIfReady();
    }

    private void buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(18), dp(16), dp(18));
        scroll.addView(root, new ScrollView.LayoutParams(-1, -2));
        setContentView(scroll);
        render();
    }

    private void render() {
        int bg = darkMode ? DARK_BG : LIGHT_BG;
        int card = darkMode ? DARK_CARD : LIGHT_CARD;
        int text = darkMode ? DARK_TEXT : LIGHT_TEXT;
        getWindow().setStatusBarColor(bg);
        root.setBackgroundColor(bg);
        root.removeAllViews();

        LinearLayout top = row(Gravity.CENTER_VERTICAL);
        TextView brand = label("BT Sentinel", 20, text, Typeface.BOLD);
        top.addView(brand, weightParams());
        soundButton = pill(soundEnabled ? "звук" : "тихо", soundEnabled ? GREEN : ORANGE, Color.WHITE);
        soundButton.setOnClickListener(v -> {
            soundEnabled = !soundEnabled;
            if (soundEnabled) {
                playTone(740, 80);
            }
            render();
        });
        themeButton = pill(darkMode ? "темн" : "свет", TEAL, Color.WHITE);
        themeButton.setOnClickListener(v -> {
            darkMode = !darkMode;
            render();
        });
        top.addView(soundButton, boxParams(74, 38));
        top.addView(themeButton, boxParams(76, 38));
        root.addView(top, matchWrap());

        LinearLayout status = card(card);
        status.setOrientation(LinearLayout.VERTICAL);
        LinearLayout line = row(Gravity.CENTER_VERTICAL);
        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        statusTitle = label(isBluetoothReady() ? "Bluetooth включен" : "Bluetooth недоступен", 21, text, Typeface.BOLD);
        statusSubtitle = label(scanning ? "Сканирование активно" : "Ожидание разрешений", 14, dim(text), Typeface.NORMAL);
        titles.addView(statusTitle);
        titles.addView(statusSubtitle);
        line.addView(titles, weightParams());
        totalCount = label(String.valueOf(devices.size()), 28, text, Typeface.BOLD);
        line.addView(totalCount);
        status.addView(line);

        LinearLayout chips = row(Gravity.CENTER);
        newCount = chip("Новые", countNew(), darkMode ? Color.rgb(62, 47, 32) : Color.rgb(255, 236, 213), ORANGE);
        knownCount = chip("Известные", countKnown(), darkMode ? Color.rgb(26, 46, 42) : Color.rgb(220, 244, 234), GREEN);
        quietBadge = chip(isQuietStart() ? "Тихий старт" : "OK", isQuietStart() ? secondsLeftQuiet() : 0, darkMode ? Color.rgb(32, 39, 44) : Color.rgb(238, 241, 245), dim(text));
        chips.addView(newCount, weightParams());
        chips.addView(knownCount, weightParams());
        chips.addView(quietBadge, weightParams());
        status.addView(chips, topMarginParams(12));
        root.addView(status, topMarginParams(16));

        LinearLayout section = row(Gravity.CENTER_VERTICAL);
        section.addView(label("Устройства", 22, text, Typeface.BOLD), weightParams());
        section.addView(label(String.valueOf(devices.size()), 14, dim(text), Typeface.BOLD));
        root.addView(section, topMarginParams(18));

        deviceList = new LinearLayout(this);
        deviceList.setOrientation(LinearLayout.VERTICAL);
        root.addView(deviceList, topMarginParams(8));
        renderDeviceRows(card, text);
    }

    private void renderDeviceRows(int cardColor, int textColor) {
        deviceList.removeAllViews();
        List<DeviceState> rows = sortedDevices();
        if (rows.isEmpty()) {
            TextView empty = label("скан", 18, dim(textColor), Typeface.BOLD);
            empty.setGravity(Gravity.CENTER);
            deviceList.addView(empty, topMarginParams(24));
            return;
        }

        for (DeviceState device : rows) {
            LinearLayout card = card(cardColor);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setOnClickListener(v -> showDetails(device));

            LinearLayout row = row(Gravity.CENTER_VERTICAL);
            LinearLayout names = new LinearLayout(this);
            names.setOrientation(LinearLayout.VERTICAL);
            names.addView(label(device.name, 18, textColor, Typeface.BOLD));
            names.addView(label(device.kind + " · " + shortId(device.id), 12, dim(textColor), Typeface.NORMAL));
            row.addView(names, weightParams());

            LinearLayout metrics = new LinearLayout(this);
            metrics.setGravity(Gravity.RIGHT);
            metrics.setOrientation(LinearLayout.VERTICAL);
            metrics.addView(label(rssiText(device), 14, rssiColor(device.displayRssi, textColor), Typeface.BOLD));
            metrics.addView(label(distanceText(device), 12, dim(textColor), Typeface.BOLD));
            row.addView(metrics, boxParams(82, -2));

            LinearLayout power = new LinearLayout(this);
            power.setGravity(Gravity.RIGHT);
            power.setOrientation(LinearLayout.VERTICAL);
            TextView bars = label(powerBars(device.displayRssi), 15, rssiColor(device.displayRssi, textColor), Typeface.BOLD);
            bars.setSingleLine(true);
            power.addView(bars);
            power.addView(label(device.trendLabel(), 12, trendColor(device, textColor), Typeface.BOLD));
            row.addView(power, boxParams(96, -2));
            card.addView(row);
            deviceList.addView(card, topMarginParams(8));
        }
    }

    private void showDetails(DeviceState device) {
        String body = "Имя: " + device.name
                + "\nID: " + device.id
                + "\nСтатус: " + (device.known ? "известное" : "новое")
                + "\nRSSI: " + rssiText(device)
                + "\nДистанция: " + distanceText(device)
                + "\nПакеты: " + device.totalSamples
                + "\nПервое обнаружение: " + elapsed(device.firstSeen)
                + "\nПоследний пакет: " + elapsed(device.lastSeen)
                + "\nТренд: " + device.trendLabel()
                + "\n\nRSSI на Android тоже может прыгать: тело, рельеф, антенна телефона и мощность маяка меняют сигнал.";
        new AlertDialog.Builder(this)
                .setTitle(device.name)
                .setMessage(body)
                .setPositiveButton("OK", null)
                .setNegativeButton(device.known ? null : "Доверять", (d, w) -> {
                    device.known = true;
                    render();
                })
                .show();
    }

    private void requestNeededPermissions() {
        List<String> permissions = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            addIfMissing(permissions, Manifest.permission.BLUETOOTH_SCAN);
            addIfMissing(permissions, Manifest.permission.BLUETOOTH_CONNECT);
        } else {
            addIfMissing(permissions, Manifest.permission.ACCESS_FINE_LOCATION);
        }
        if (Build.VERSION.SDK_INT >= 33) {
            addIfMissing(permissions, Manifest.permission.POST_NOTIFICATIONS);
        }
        if (!permissions.isEmpty() && Build.VERSION.SDK_INT >= 23) {
            requestPermissions(permissions.toArray(new String[0]), 7);
        } else {
            startScanIfReady();
        }
    }

    private void addIfMissing(List<String> permissions, String permission) {
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
            permissions.add(permission);
        }
    }

    private boolean hasScanPermission() {
        if (Build.VERSION.SDK_INT < 23) {
            return true;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
                    && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED;
        }
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private void startScanIfReady() {
        if (scanning || !isBluetoothReady() || !hasScanPermission()) {
            render();
            return;
        }
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            render();
            return;
        }
        ScanSettings settings = new ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setReportDelay(0)
                .build();
        try {
            scanner.startScan(null, settings, callback);
            scanning = true;
        } catch (SecurityException ignored) {
            scanning = false;
        }
        render();
    }

    private void stopScan() {
        if (!scanning || scanner == null) {
            return;
        }
        try {
            scanner.stopScan(callback);
        } catch (SecurityException ignored) {
            // Permission may have been revoked while the app was active.
        }
        scanning = false;
    }

    private void handleScan(ScanResult result) {
        long t = now();
        int rssi = result.getRssi();
        String id = deviceId(result);
        String rawName = deviceName(result);
        boolean isNew = !devices.containsKey(id);
        DeviceState device = devices.get(id);
        if (device == null) {
            device = new DeviceState();
            device.id = id;
            device.name = displayName(id, rawName);
            device.kind = classify(result);
            device.firstSeen = t;
            device.displayRssi = rssi;
            device.known = isQuietStart();
            device.orderBoostAt = t;
            devices.put(id, device);
        } else {
            device.name = displayName(id, rawName);
            device.kind = classify(result);
        }

        device.lastSeen = t;
        device.rawRssi = rssi;
        device.totalSamples++;
        device.samples.add(new Sample(t, rssi));
        trimSamples(device, t);

        if (isNew && !device.known && !isQuietStart()) {
            device.orderBoostAt = t;
            if (!discoveryAlerted.contains(id)) {
                discoveryAlerted.add(id);
                playDiscoveryAlert();
            }
        }

        updateDeviceAnalysis(device, t);
        maybePromoteKnown(device, t);
    }

    private String deviceId(ScanResult result) {
        try {
            return result.getDevice().getAddress();
        } catch (SecurityException ignored) {
            return "unknown-" + result.hashCode();
        }
    }

    private String deviceName(ScanResult result) {
        String name = null;
        try {
            name = result.getDevice().getName();
        } catch (SecurityException ignored) {
            // Keep generated label.
        }
        if (TextUtils.isEmpty(name) && result.getScanRecord() != null) {
            name = result.getScanRecord().getDeviceName();
        }
        return name == null ? "" : name.trim();
    }

    private String displayName(String id, String rawName) {
        if (!isUnnamed(rawName)) {
            return rawName;
        }
        String existing = unnamedLabels.get(id);
        if (existing != null) {
            return existing;
        }
        String label = "Новый " + nextUnnamedNumber++;
        unnamedLabels.put(id, label);
        return label;
    }

    private boolean isUnnamed(String rawName) {
        if (rawName == null || rawName.trim().isEmpty()) {
            return true;
        }
        String lower = rawName.trim().toLowerCase(Locale.ROOT);
        return lower.equals("без имени") || lower.equals("unknown") || lower.equals("unnamed");
    }

    private String classify(ScanResult result) {
        if (result.getScanRecord() == null) {
            return "BLE";
        }
        if (!result.getScanRecord().getServiceUuids().isEmpty()) {
            return "BLE service";
        }
        if (result.isConnectable()) {
            return "BLE connectable";
        }
        return "BLE beacon";
    }

    private void updateDisplayedValues() {
        long t = now();
        for (DeviceState device : devices.values()) {
            updateDeviceAnalysis(device, t);
            maybePromoteKnown(device, t);
        }
    }

    private void updateDeviceAnalysis(DeviceState device, long t) {
        trimSamples(device, t);
        if (device.samples.isEmpty()) {
            return;
        }
        List<Sample> displayWindow = samplesSince(device.samples, t - RSSI_WINDOW_MS);
        int stable = trimmedMedian(displayWindow);
        device.jittery = rssiSpread(displayWindow) >= 12;
        if (device.lastDisplayedAt == 0 || t - device.lastDisplayedAt >= UI_UPDATE_MS) {
            if (Math.abs(stable - device.displayRssi) >= RSSI_DEADBAND_DBM || device.lastDisplayedAt == 0) {
                device.displayRssi = stable;
            }
            device.lastDisplayedAt = t;
        }

        int oldStable = medianAtOrBefore(device.samples, t - APPROACH_WINDOW_MS);
        int gain = stable - oldStable;
        device.approaching = device.samples.size() >= 8 && oldStable > -120 && gain >= APPROACH_GAIN_DBM;
        if (device.approaching && !isQuietStart() && !approachAlerted.contains(device.id)) {
            approachAlerted.add(device.id);
            device.orderBoostAt = t;
            playApproachAlert();
        }
    }

    private void maybePromoteKnown(DeviceState device, long t) {
        if (device.known || device.approaching || approachAlerted.contains(device.id)) {
            return;
        }
        boolean oldEnough = t - device.firstSeen >= AUTO_KNOWN_MS;
        boolean enoughSamples = device.totalSamples >= MIN_AUTO_KNOWN_SAMPLES;
        boolean fresh = t - device.lastSeen < 12_000L;
        if (oldEnough && enoughSamples && fresh) {
            device.known = true;
        }
    }

    private void cleanupStaleDevices() {
        long t = now();
        Iterator<Map.Entry<String, DeviceState>> iterator = devices.entrySet().iterator();
        while (iterator.hasNext()) {
            DeviceState device = iterator.next().getValue();
            if (t - device.lastSeen > STALE_MS) {
                iterator.remove();
                discoveryAlerted.remove(device.id);
                approachAlerted.remove(device.id);
            }
        }
    }

    private void trimSamples(DeviceState device, long t) {
        long historyWindow = Math.max(RSSI_WINDOW_MS, APPROACH_WINDOW_MS) + 3_000L;
        Iterator<Sample> iterator = device.samples.iterator();
        while (iterator.hasNext()) {
            if (t - iterator.next().time > historyWindow) {
                iterator.remove();
            }
        }
    }

    private List<Sample> samplesSince(List<Sample> samples, long since) {
        List<Sample> window = new ArrayList<>();
        for (Sample sample : samples) {
            if (sample.time >= since) {
                window.add(sample);
            }
        }
        return window.isEmpty() ? samples : window;
    }

    private int trimmedMedian(List<Sample> samples) {
        List<Integer> values = new ArrayList<>();
        for (Sample sample : samples) {
            values.add(sample.rssi);
        }
        if (values.isEmpty()) {
            return -127;
        }
        Collections.sort(values);
        int trim = Math.max(0, (int) Math.floor(values.size() * 0.18));
        int from = Math.min(trim, values.size() - 1);
        int to = Math.max(from + 1, values.size() - trim);
        List<Integer> core = values.subList(from, to);
        return core.get(core.size() / 2);
    }

    private int rssiSpread(List<Sample> samples) {
        if (samples.size() < 4) {
            return 0;
        }
        int min = 127;
        int max = -127;
        for (Sample sample : samples) {
            min = Math.min(min, sample.rssi);
            max = Math.max(max, sample.rssi);
        }
        return max - min;
    }

    private int medianAtOrBefore(List<Sample> samples, long threshold) {
        List<Sample> old = new ArrayList<>();
        for (Sample sample : samples) {
            if (sample.time <= threshold + 2_000L) {
                old.add(sample);
            }
        }
        if (old.isEmpty()) {
            return -127;
        }
        return trimmedMedian(old);
    }

    private List<DeviceState> sortedDevices() {
        List<DeviceState> rows = new ArrayList<>(devices.values());
        Collections.sort(rows, new Comparator<DeviceState>() {
            @Override
            public int compare(DeviceState a, DeviceState b) {
                if (a.approaching != b.approaching) {
                    return a.approaching ? -1 : 1;
                }
                if (a.known != b.known) {
                    return a.known ? 1 : -1;
                }
                int boost = Long.compare(b.orderBoostAt, a.orderBoostAt);
                if (boost != 0) {
                    return boost;
                }
                return Long.compare(b.lastSeen, a.lastSeen);
            }
        });
        return rows;
    }

    private void playDiscoveryAlert() {
        vibrate(120);
        if (!soundEnabled) {
            return;
        }
        playTone(1040, 90);
        handler.postDelayed(() -> playTone(1320, 110), 120);
    }

    private void playApproachAlert() {
        vibrate(220);
        if (!soundEnabled) {
            return;
        }
        playTone(880, 100);
        handler.postDelayed(() -> playTone(1240, 110), 130);
        handler.postDelayed(() -> playTone(1560, 130), 270);
    }

    private void playTone(int hz, int durationMs) {
        if (tone == null) {
            return;
        }
        int toneType = hz >= 1400 ? ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD
                : hz >= 1100 ? ToneGenerator.TONE_PROP_ACK
                : ToneGenerator.TONE_PROP_BEEP;
        tone.startTone(toneType, durationMs);
    }

    private void vibrate(long durationMs) {
        if (vibrator == null) {
            return;
        }
        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE));
        } else {
            vibrator.vibrate(durationMs);
        }
    }

    private int countNew() {
        int count = 0;
        for (DeviceState device : devices.values()) {
            if (!device.known) {
                count++;
            }
        }
        return count;
    }

    private int countKnown() {
        int count = 0;
        for (DeviceState device : devices.values()) {
            if (device.known) {
                count++;
            }
        }
        return count;
    }

    private boolean isBluetoothReady() {
        return adapter != null && adapter.isEnabled();
    }

    private boolean isQuietStart() {
        return now() < quietStartEndsAt;
    }

    private int secondsLeftQuiet() {
        return Math.max(0, (int) Math.ceil((quietStartEndsAt - now()) / 1000.0));
    }

    private String rssiText(DeviceState device) {
        return device.displayRssi + " dBm";
    }

    private String distanceText(DeviceState device) {
        double meters = Math.pow(10.0, (-59.0 - device.displayRssi) / 24.0);
        if (meters < 1.0) {
            return "~<1 м";
        }
        if (meters < 10.0) {
            return String.format(Locale.US, "~%.1f м", meters);
        }
        return String.format(Locale.US, "~%.0f м", meters);
    }

    private String powerBars(int rssi) {
        int level;
        if (rssi >= -55) {
            level = 10;
        } else if (rssi >= -62) {
            level = 8;
        } else if (rssi >= -70) {
            level = 6;
        } else if (rssi >= -78) {
            level = 4;
        } else if (rssi >= -86) {
            level = 2;
        } else {
            level = 1;
        }
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < 10; i++) {
            builder.append(i < level ? "▮" : "▯");
        }
        return builder.toString();
    }

    private int rssiColor(int rssi, int textColor) {
        if (rssi >= -58) {
            return GREEN;
        }
        if (rssi >= -72) {
            return ORANGE;
        }
        return dim(textColor);
    }

    private int trendColor(DeviceState device, int textColor) {
        if (device.approaching) {
            return RED;
        }
        if (device.jittery) {
            return ORANGE;
        }
        return dim(textColor);
    }

    private String shortId(String id) {
        if (id == null || id.length() <= 8) {
            return id == null ? "--" : id;
        }
        return id.substring(Math.max(0, id.length() - 8));
    }

    private String elapsed(long since) {
        long seconds = Math.max(0, (now() - since) / 1000L);
        if (seconds < 60) {
            return seconds + " сек";
        }
        long minutes = seconds / 60;
        long rest = seconds % 60;
        return minutes + ":" + String.format(Locale.US, "%02d", rest);
    }

    private long now() {
        return System.currentTimeMillis();
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private LinearLayout row(int gravity) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(gravity);
        return row;
    }

    private LinearLayout card(int color) {
        LinearLayout card = new LinearLayout(this);
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(16));
        drawable.setStroke(dp(1), darkMode ? Color.rgb(35, 46, 52) : Color.rgb(225, 229, 235));
        card.setBackground(drawable);
        return card;
    }

    private TextView label(String text, int sp, int color, int style) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setTypeface(Typeface.DEFAULT, style);
        view.setIncludeFontPadding(true);
        return view;
    }

    private Button pill(String text, int bg, int fg) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextSize(12);
        button.setTextColor(fg);
        button.setAllCaps(false);
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(bg);
        drawable.setCornerRadius(dp(18));
        button.setBackground(drawable);
        return button;
    }

    private TextView chip(String title, int value, int bg, int fg) {
        TextView view = label(title.equals("OK") ? "OK" : value + "\n" + title, 13, fg, Typeface.BOLD);
        view.setGravity(Gravity.CENTER);
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(bg);
        drawable.setCornerRadius(dp(12));
        view.setBackground(drawable);
        view.setPadding(dp(8), dp(8), dp(8), dp(8));
        return view;
    }

    private int dim(int color) {
        int r = Color.red(color);
        int g = Color.green(color);
        int b = Color.blue(color);
        if (darkMode) {
            return Color.rgb((r + 80) / 2, (g + 80) / 2, (b + 80) / 2);
        }
        return Color.rgb((r + 160) / 2, (g + 160) / 2, (b + 160) / 2);
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(-1, -2);
    }

    private LinearLayout.LayoutParams weightParams() {
        return new LinearLayout.LayoutParams(0, -2, 1f);
    }

    private LinearLayout.LayoutParams boxParams(int widthDp, int heightDp) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(widthDp < 0 ? widthDp : dp(widthDp), heightDp < 0 ? heightDp : dp(heightDp));
        params.leftMargin = dp(8);
        return params;
    }

    private LinearLayout.LayoutParams topMarginParams(int topDp) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.topMargin = dp(topDp);
        return params;
    }

    private static final class Sample {
        final long time;
        final int rssi;

        Sample(long time, int rssi) {
            this.time = time;
            this.rssi = rssi;
        }
    }

    private static final class DeviceState {
        String id = "";
        String name = "";
        String kind = "BLE";
        int rawRssi = -100;
        int displayRssi = -100;
        long firstSeen;
        long lastSeen;
        long orderBoostAt;
        long lastDisplayedAt;
        int totalSamples;
        boolean known;
        boolean approaching;
        boolean jittery;
        final List<Sample> samples = new ArrayList<>();

        String trendLabel() {
            if (approaching) {
                return "ближе";
            }
            if (jittery) {
                return "дрожит";
            }
            return "скан";
        }
    }
}
