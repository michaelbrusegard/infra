package com.hermes.agent.accessibility;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.graphics.Path;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.FutureTask;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

public final class HermesAccessibilityService extends AccessibilityService {
    private static final String TAG = "HermesAccessibility";
    private static final int LISTEN_PORT = 8765;
    private static final int MAX_REQUEST_CHARS = 1024 * 1024;
    private static final int MAX_NODES = 5000;
    private static final int MAX_DEPTH = 64;
    private static final int MAX_LIVE_SNAPSHOTS = 32;
    private static final long DEFAULT_TTL_MS = 30_000L;
    private static final long MAX_TTL_MS = 300_000L;
    private static final long DEFAULT_VERIFY_MS = 3_000L;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService clients = new ThreadPoolExecutor(
            2,
            4,
            60L,
            TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(32));
    private final AtomicLong eventSequence = new AtomicLong();
    private volatile boolean running;
    private volatile ServerSocket serverSocket;
    private volatile Thread acceptThread;
    private volatile String activePackage = "";
    private volatile int activeWindowId = -1;
    private final LinkedHashMap<String, Snapshot> snapshots = new LinkedHashMap<>();
    private Snapshot lastSnapshot;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        if (running) {
            return;
        }
        running = true;
        acceptThread = new Thread(this::acceptLoop, "hermes-accessibility-accept");
        acceptThread.setDaemon(true);
        acceptThread.start();
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        eventSequence.incrementAndGet();
        if (event.getPackageName() != null) {
            activePackage = event.getPackageName().toString();
        }
        activeWindowId = event.getWindowId();
    }

    @Override
    public void onInterrupt() {
        eventSequence.incrementAndGet();
    }

    @Override
    public void onDestroy() {
        running = false;
        ServerSocket socket = serverSocket;
        if (socket != null) {
            try {
                socket.close();
            } catch (IOException ignored) {
                // The accept loop is already shutting down.
            }
        }
        clients.shutdownNow();
        super.onDestroy();
    }

    private void acceptLoop() {
        try (ServerSocket socket = new ServerSocket()) {
            socket.setReuseAddress(true);
            socket.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), LISTEN_PORT), 16);
            serverSocket = socket;
            while (running) {
                Socket client = socket.accept();
                try {
                    clients.submit(() -> serveClient(client));
                } catch (RejectedExecutionException overloaded) {
                    client.close();
                }
            }
        } catch (IOException error) {
            if (running) {
                eventSequence.incrementAndGet();
                Log.e(TAG, "accessibility listener failed", error);
            }
        } finally {
            running = false;
            serverSocket = null;
        }
    }

    private void serveClient(Socket socket) {
        try (Socket client = socket;
             BufferedReader reader = new BufferedReader(
                     new InputStreamReader(client.getInputStream(), StandardCharsets.UTF_8));
             BufferedWriter writer = new BufferedWriter(
                     new OutputStreamWriter(client.getOutputStream(), StandardCharsets.UTF_8))) {
            client.setSoTimeout(20_000);
            String requestText = readRequest(reader);
            JSONObject response;
            try {
                response = handleRequest(new JSONObject(requestText));
                response.put("ok", true);
            } catch (Exception error) {
                response = new JSONObject();
                response.put("ok", false);
                response.put("error", safe(error));
                response.put("error_type", error.getClass().getSimpleName());
            }
            writer.write(response.toString());
            writer.write('\n');
            writer.flush();
        } catch (Exception error) {
            // ADB clients can disconnect at any point; each request is independent.
            Log.w(TAG, "accessibility request failed", error);
        }
    }

    private static String readRequest(BufferedReader reader) throws IOException {
        StringBuilder request = new StringBuilder();
        while (request.length() <= MAX_REQUEST_CHARS) {
            int next = reader.read();
            if (next == -1 || next == '\n') {
                break;
            }
            request.append((char) next);
        }
        if (request.length() == 0) {
            throw new IOException("empty request");
        }
        if (request.length() > MAX_REQUEST_CHARS) {
            throw new IOException("request exceeds one MiB");
        }
        return request.toString();
    }

    private JSONObject handleRequest(JSONObject request) throws Exception {
        requireAuthentication(request);
        String operation = request.getString("op");
        switch (operation) {
            case "health":
                return onMain(this::health);
            case "snapshot":
                long ttlMs = bounded(request.optLong("ttl_ms", DEFAULT_TTL_MS), 1_000L, MAX_TTL_MS);
                return onMain(() -> snapshotJson(ttlMs));
            case "action":
                return performNodeAction(request);
            case "gesture":
                return performGestureRequest(request);
            case "global_action":
                return performGlobalActionRequest(request);
            default:
                throw new IllegalArgumentException("unsupported operation: " + operation);
        }
    }

    private void requireAuthentication(JSONObject request) {
        String expected = getSharedPreferences(ConfigReceiver.PREFERENCES, MODE_PRIVATE)
                .getString(ConfigReceiver.TOKEN_KEY, "");
        String presented = request.optString("token", "");
        if (expected.isEmpty() || !MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                presented.getBytes(StandardCharsets.UTF_8))) {
            throw new SecurityException("missing or invalid companion token");
        }
        request.remove("token");
    }

    private JSONObject health() throws JSONException {
        JSONObject result = new JSONObject();
        result.put("service", "HermesAccessibilityService");
        result.put("listen_address", "127.0.0.1");
        result.put("listen_port", LISTEN_PORT);
        result.put("connected", running);
        result.put("event_sequence", eventSequence.get());
        result.put("package", activePackage);
        result.put("window_id", activeWindowId);
        AccessibilityNodeInfo root = getRootInActiveWindow();
        result.put("has_root", root != null);
        if (root != null) {
            root.recycle();
        }
        if (lastSnapshot != null) {
            result.put("last_tree_id", lastSnapshot.treeId);
            result.put("last_tree_expires_at_ms", lastSnapshot.expiresAtMs);
        }
        return result;
    }

    private JSONObject snapshotJson(long ttlMs) throws JSONException {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        long capturedAtMs = System.currentTimeMillis();
        Snapshot snapshot = new Snapshot(
                UUID.randomUUID().toString(),
                capturedAtMs,
                capturedAtMs + ttlMs,
                eventSequence.get(),
                activePackage,
                activeWindowId);
        MessageDigest digest = sha256();
        if (root != null) {
            try {
                traverse(root, "", null, 0, snapshot, digest);
            } finally {
                root.recycle();
            }
        }
        snapshot.digest = hex(digest.digest());
        pruneSnapshots(capturedAtMs);
        snapshots.put(snapshot.treeId, snapshot);
        while (snapshots.size() > MAX_LIVE_SNAPSHOTS) {
            Iterator<String> oldest = snapshots.keySet().iterator();
            oldest.next();
            oldest.remove();
        }
        lastSnapshot = snapshot;
        return snapshot.toJson();
    }

    private void pruneSnapshots(long nowMs) {
        snapshots.entrySet().removeIf(entry -> nowMs >= entry.getValue().expiresAtMs);
    }

    private void traverse(
            AccessibilityNodeInfo node,
            String path,
            String parentRef,
            int depth,
            Snapshot snapshot,
            MessageDigest digest) throws JSONException {
        if (node == null || depth > MAX_DEPTH || snapshot.nodes.size() >= MAX_NODES) {
            return;
        }
        String ref = "r" + snapshot.nodes.size();
        NodeRecord record = NodeRecord.from(node, ref, parentRef, path, depth);
        snapshot.nodes.put(ref, record);
        digest.update(record.digestMaterial().getBytes(StandardCharsets.UTF_8));
        int childCount = node.getChildCount();
        for (int index = 0; index < childCount && snapshot.nodes.size() < MAX_NODES; index++) {
            AccessibilityNodeInfo child = node.getChild(index);
            if (child == null) {
                continue;
            }
            String childPath = path.isEmpty() ? Integer.toString(index) : path + "/" + index;
            traverse(child, childPath, ref, depth + 1, snapshot, digest);
            child.recycle();
        }
    }

    private JSONObject performNodeAction(JSONObject request) throws Exception {
        final String treeId = request.getString("tree_id");
        final String ref = request.getString("ref");
        final String action = request.getString("action").toLowerCase(Locale.ROOT);
        final String value = request.optString("value", "");
        final boolean fallbackGesture = request.optBoolean("fallback_gesture", true);
        final long verifyMs = bounded(
                request.optLong("verify_timeout_ms", DEFAULT_VERIFY_MS), 0L, 30_000L);
        final boolean requireChange = request.optBoolean("require_change", false);

        ActionStart started = onMain(() -> startNodeAction(
                treeId, ref, action, value, fallbackGesture));
        JSONObject result = started.toJson();
        if (!started.accepted) {
            throw new IllegalStateException("Android rejected accessibility action " + action + " for " + ref);
        }
        if (verifyMs == 0L) {
            return result;
        }

        long deadline = SystemClock.elapsedRealtime() + verifyMs;
        JSONObject after = null;
        boolean changed = false;
        do {
            SystemClock.sleep(125L);
            after = onMain(() -> snapshotJson(DEFAULT_TTL_MS));
            changed = !started.beforeDigest.equals(after.getString("digest"))
                    || started.beforeEventSequence != after.getLong("event_sequence");
        } while (!changed && SystemClock.elapsedRealtime() < deadline);
        result.put("changed", changed);
        result.put("after", after);
        if (requireChange && !changed) {
            throw new IllegalStateException("accessibility tree and event sequence did not change after action");
        }
        return result;
    }

    private ActionStart startNodeAction(
            String treeId,
            String ref,
            String action,
            String value,
            boolean fallbackGesture) throws Exception {
        Snapshot snapshot = snapshots.get(treeId);
        if (snapshot == null) {
            throw new IllegalStateException("stale tree_id; request a new accessibility snapshot");
        }
        if (System.currentTimeMillis() >= snapshot.expiresAtMs) {
            snapshots.remove(treeId);
            throw new IllegalStateException("accessibility refs expired; request a new snapshot");
        }
        NodeRecord record = snapshot.nodes.get(ref);
        if (record == null) {
            throw new IllegalArgumentException("unknown accessibility ref: " + ref);
        }
        AccessibilityNodeInfo node = resolvePath(record.path);
        if (node == null || !record.fingerprint.equals(NodeRecord.fingerprint(node))) {
            if (node != null) {
                node.recycle();
            }
            throw new IllegalStateException("accessibility node changed; request a new snapshot");
        }

        boolean accepted;
        boolean usedGesture = false;
        switch (action) {
            case "click":
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                if (!accepted && fallbackGesture) {
                    accepted = dispatchPointGesture(record.bounds, 1L);
                    usedGesture = accepted;
                }
                break;
            case "long_click":
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK);
                if (!accepted && fallbackGesture) {
                    accepted = dispatchPointGesture(record.bounds, 750L);
                    usedGesture = accepted;
                }
                break;
            case "focus":
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
                break;
            case "accessibility_focus":
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS);
                break;
            case "clear_focus":
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_CLEAR_FOCUS);
                break;
            case "scroll_forward":
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD);
                break;
            case "scroll_backward":
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD);
                break;
            case "set_text":
                if (!node.isFocused()) {
                    node.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
                    node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS);
                }
                Bundle arguments = new Bundle();
                arguments.putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        value);
                accepted = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments);
                break;
            default:
                node.recycle();
                throw new IllegalArgumentException("unsupported node action: " + action);
        }
        node.recycle();
        return new ActionStart(
                accepted,
                usedGesture,
                snapshot.digest,
                snapshot.eventSequence,
                treeId,
                ref,
                action);
    }

    private AccessibilityNodeInfo resolvePath(String path) {
        AccessibilityNodeInfo node = getRootInActiveWindow();
        if (node == null || path.isEmpty()) {
            return node;
        }
        for (String component : path.split("/")) {
            int index = Integer.parseInt(component);
            AccessibilityNodeInfo child = node.getChild(index);
            node.recycle();
            if (child == null) {
                return null;
            }
            node = child;
        }
        return node;
    }

    private JSONObject performGestureRequest(JSONObject request) throws Exception {
        String type = request.getString("type").toLowerCase(Locale.ROOT);
        long durationMs = bounded(request.optLong("duration_ms", 100L), 1L, 60_000L);
        boolean accepted = onMain(() -> {
            if ("tap".equals(type) || "long_press".equals(type)) {
                Rect point = new Rect(
                        request.getInt("x"),
                        request.getInt("y"),
                        request.getInt("x"),
                        request.getInt("y"));
                return dispatchPointGesture(point, "long_press".equals(type) ? durationMs : 1L);
            }
            if ("swipe".equals(type)) {
                Path path = new Path();
                path.moveTo(request.getInt("x1"), request.getInt("y1"));
                path.lineTo(request.getInt("x2"), request.getInt("y2"));
                GestureDescription gesture = new GestureDescription.Builder()
                        .addStroke(new GestureDescription.StrokeDescription(path, 0L, durationMs))
                        .build();
                return dispatchGesture(gesture, null, null);
            }
            throw new IllegalArgumentException("unsupported gesture: " + type);
        });
        JSONObject result = new JSONObject();
        result.put("type", type);
        result.put("accepted", accepted);
        return result;
    }

    private JSONObject performGlobalActionRequest(JSONObject request) throws Exception {
        String action = request.getString("action").toLowerCase(Locale.ROOT);
        int actionCode;
        switch (action) {
            case "back": actionCode = GLOBAL_ACTION_BACK; break;
            case "home": actionCode = GLOBAL_ACTION_HOME; break;
            case "recents": actionCode = GLOBAL_ACTION_RECENTS; break;
            case "notifications": actionCode = GLOBAL_ACTION_NOTIFICATIONS; break;
            case "quick_settings": actionCode = GLOBAL_ACTION_QUICK_SETTINGS; break;
            case "power_dialog": actionCode = GLOBAL_ACTION_POWER_DIALOG; break;
            case "lock_screen": actionCode = GLOBAL_ACTION_LOCK_SCREEN; break;
            case "take_screenshot": actionCode = GLOBAL_ACTION_TAKE_SCREENSHOT; break;
            default: throw new IllegalArgumentException("unsupported global action: " + action);
        }
        boolean accepted = onMain(() -> performGlobalAction(actionCode));
        JSONObject result = new JSONObject();
        result.put("action", action);
        result.put("accepted", accepted);
        return result;
    }

    private boolean dispatchPointGesture(Rect bounds, long durationMs) {
        float x = bounds.exactCenterX();
        float y = bounds.exactCenterY();
        Path path = new Path();
        path.moveTo(x, y);
        GestureDescription gesture = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0L, durationMs))
                .build();
        return dispatchGesture(gesture, null, null);
    }

    private <T> T onMain(Callable<T> callable) throws Exception {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return callable.call();
        }
        FutureTask<T> task = new FutureTask<>(callable);
        mainHandler.post(task);
        return task.get(15, TimeUnit.SECONDS);
    }

    private static long bounded(long value, long minimum, long maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    private static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    private static String hex(byte[] value) {
        StringBuilder result = new StringBuilder(value.length * 2);
        for (byte item : value) {
            result.append(String.format(Locale.ROOT, "%02x", item & 0xff));
        }
        return result.toString();
    }

    private static String text(CharSequence value) {
        return value == null ? "" : value.toString();
    }

    private static String safe(Exception error) {
        String message = error.getMessage();
        return message == null || message.isEmpty() ? error.getClass().getSimpleName() : message;
    }

    private static final class Snapshot {
        final String treeId;
        final long capturedAtMs;
        final long expiresAtMs;
        final long eventSequence;
        final String packageName;
        final int windowId;
        final LinkedHashMap<String, NodeRecord> nodes = new LinkedHashMap<>();
        String digest = "";

        Snapshot(
                String treeId,
                long capturedAtMs,
                long expiresAtMs,
                long eventSequence,
                String packageName,
                int windowId) {
            this.treeId = treeId;
            this.capturedAtMs = capturedAtMs;
            this.expiresAtMs = expiresAtMs;
            this.eventSequence = eventSequence;
            this.packageName = packageName;
            this.windowId = windowId;
        }

        JSONObject toJson() throws JSONException {
            JSONObject result = new JSONObject();
            result.put("backend", "accessibility-service");
            result.put("tree_id", treeId);
            result.put("digest", digest);
            result.put("captured_at_ms", capturedAtMs);
            result.put("expires_at_ms", expiresAtMs);
            result.put("event_sequence", eventSequence);
            result.put("package", packageName);
            result.put("window_id", windowId);
            JSONArray items = new JSONArray();
            for (NodeRecord node : nodes.values()) {
                items.put(node.toJson());
            }
            result.put("nodes", items);
            result.put("node_count", nodes.size());
            result.put("truncated", nodes.size() >= MAX_NODES);
            return result;
        }
    }

    private static final class NodeRecord {
        final String ref;
        final String parentRef;
        final String path;
        final int depth;
        final String className;
        final String packageName;
        final String text;
        final String description;
        final String viewId;
        final Rect bounds;
        final boolean clickable;
        final boolean editable;
        final boolean enabled;
        final boolean focusable;
        final boolean focused;
        final boolean scrollable;
        final boolean selected;
        final boolean checkable;
        final boolean checked;
        final boolean visible;
        final List<Integer> actions;
        final String fingerprint;

        NodeRecord(
                String ref,
                String parentRef,
                String path,
                int depth,
                String className,
                String packageName,
                String text,
                String description,
                String viewId,
                Rect bounds,
                boolean clickable,
                boolean editable,
                boolean enabled,
                boolean focusable,
                boolean focused,
                boolean scrollable,
                boolean selected,
                boolean checkable,
                boolean checked,
                boolean visible,
                List<Integer> actions,
                String fingerprint) {
            this.ref = ref;
            this.parentRef = parentRef;
            this.path = path;
            this.depth = depth;
            this.className = className;
            this.packageName = packageName;
            this.text = text;
            this.description = description;
            this.viewId = viewId;
            this.bounds = bounds;
            this.clickable = clickable;
            this.editable = editable;
            this.enabled = enabled;
            this.focusable = focusable;
            this.focused = focused;
            this.scrollable = scrollable;
            this.selected = selected;
            this.checkable = checkable;
            this.checked = checked;
            this.visible = visible;
            this.actions = actions;
            this.fingerprint = fingerprint;
        }

        static NodeRecord from(
                AccessibilityNodeInfo node,
                String ref,
                String parentRef,
                String path,
                int depth) {
            Rect bounds = new Rect();
            node.getBoundsInScreen(bounds);
            List<Integer> actions = new ArrayList<>();
            for (AccessibilityNodeInfo.AccessibilityAction action : node.getActionList()) {
                actions.add(action.getId());
            }
            return new NodeRecord(
                    ref,
                    parentRef,
                    path,
                    depth,
                    text(node.getClassName()),
                    text(node.getPackageName()),
                    text(node.getText()),
                    text(node.getContentDescription()),
                    text(node.getViewIdResourceName()),
                    bounds,
                    node.isClickable(),
                    node.isEditable(),
                    node.isEnabled(),
                    node.isFocusable(),
                    node.isFocused(),
                    node.isScrollable(),
                    node.isSelected(),
                    node.isCheckable(),
                    node.isChecked(),
                    node.isVisibleToUser(),
                    actions,
                    fingerprint(node));
        }

        static String fingerprint(AccessibilityNodeInfo node) {
            Rect bounds = new Rect();
            node.getBoundsInScreen(bounds);
            return text(node.getClassName()) + '\u001f'
                    + text(node.getPackageName()) + '\u001f'
                    + text(node.getViewIdResourceName()) + '\u001f'
                    + text(node.getText()) + '\u001f'
                    + text(node.getContentDescription()) + '\u001f'
                    + bounds.flattenToString();
        }

        String digestMaterial() {
            return path + '\u001e' + fingerprint + '\u001e'
                    + clickable + '\u001e' + editable + '\u001e' + enabled + '\n';
        }

        JSONObject toJson() throws JSONException {
            JSONObject result = new JSONObject();
            result.put("ref", ref);
            result.put("parent_ref", parentRef == null ? JSONObject.NULL : parentRef);
            result.put("depth", depth);
            result.put("class", className);
            result.put("package", packageName);
            result.put("text", text);
            result.put("content_description", description);
            result.put("view_id", viewId);
            JSONObject rectangle = new JSONObject();
            rectangle.put("left", bounds.left);
            rectangle.put("top", bounds.top);
            rectangle.put("right", bounds.right);
            rectangle.put("bottom", bounds.bottom);
            JSONArray center = new JSONArray();
            center.put(Math.round(bounds.exactCenterX()));
            center.put(Math.round(bounds.exactCenterY()));
            rectangle.put("center", center);
            result.put("bounds", rectangle);
            result.put("clickable", clickable);
            result.put("editable", editable);
            result.put("enabled", enabled);
            result.put("focusable", focusable);
            result.put("focused", focused);
            result.put("scrollable", scrollable);
            result.put("selected", selected);
            result.put("checkable", checkable);
            result.put("checked", checked);
            result.put("visible", visible);
            JSONArray actionIds = new JSONArray();
            for (int action : actions) {
                actionIds.put(action);
            }
            result.put("actions", actionIds);
            return result;
        }
    }

    private static final class ActionStart {
        final boolean accepted;
        final boolean usedGesture;
        final String beforeDigest;
        final long beforeEventSequence;
        final String treeId;
        final String ref;
        final String action;

        ActionStart(
                boolean accepted,
                boolean usedGesture,
                String beforeDigest,
                long beforeEventSequence,
                String treeId,
                String ref,
                String action) {
            this.accepted = accepted;
            this.usedGesture = usedGesture;
            this.beforeDigest = beforeDigest;
            this.beforeEventSequence = beforeEventSequence;
            this.treeId = treeId;
            this.ref = ref;
            this.action = action;
        }

        JSONObject toJson() throws JSONException {
            JSONObject result = new JSONObject();
            result.put("tree_id", treeId);
            result.put("ref", ref);
            result.put("action", action);
            result.put("accepted", accepted);
            result.put("used_gesture_fallback", usedGesture);
            result.put("before_digest", beforeDigest);
            result.put("before_event_sequence", beforeEventSequence);
            return result;
        }
    }
}
