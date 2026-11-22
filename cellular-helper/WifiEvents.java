package local.carplay.cellular;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.ScanResult;
import android.net.wifi.SupplicantState;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.FileObserver;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;

/** Relays Android connection events to the module service. */
public final class WifiEvents {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final WifiManager wifi;
    private final File settings;
    private final FileObserver settingsObserver;
    private final FileObserver moduleObserver;
    private final Runnable sendWifi = () -> send("wifi");
    private long lastBoxScan;

    private WifiEvents(Context context, File settings, File module) {
        this.wifi = context.getSystemService(WifiManager.class);
        this.settings = settings;
        settingsObserver = watch(settings.getParentFile(), settings.getName());
        moduleObserver = watch(module, "disable", "remove", "module.prop");

        IntentFilter filter = new IntentFilter();
        filter.addAction(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
        filter.addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION);
        filter.addAction(WifiManager.WIFI_STATE_CHANGED_ACTION);
        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override public void onReceive(Context ignored, Intent intent) {
                if (WifiManager.SCAN_RESULTS_AVAILABLE_ACTION.equals(intent.getAction())) {
                    if (intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)) scanFinished();
                } else {
                    wifiChanged();
                }
            }
        };
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            context.registerReceiver(receiver, filter);
        }
        NetworkRequest request = new NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build();
        context.getSystemService(ConnectivityManager.class).registerNetworkCallback(
                request, new ConnectivityManager.NetworkCallback() {
                    @Override public void onAvailable(Network network) { wifiChanged(); }
                    @Override public void onLost(Network network) { wifiChanged(); }
                    @Override public void onLinkPropertiesChanged(Network network, LinkProperties properties) {
                        wifiChanged();
                    }
                }, handler);
        settingsObserver.startWatching();
        moduleObserver.startWatching();
    }

    private void wifiChanged() {
        handler.removeCallbacks(sendWifi);
        handler.postDelayed(sendWifi, 200);
    }

    private void scanFinished() {
        if (!wifi.isWifiEnabled()) return;
        WifiInfo current = wifi.getConnectionInfo();
        if (current != null && current.getSupplicantState() == SupplicantState.COMPLETED) return;
        try (BufferedReader reader = new BufferedReader(new FileReader(settings))) {
            String ssid = reader.readLine();
            for (int i = 0; i < 6; i++) reader.readLine();
            if (ssid == null || !"1".equals(reader.readLine())) return;
            long now = SystemClock.elapsedRealtimeNanos() / 1000;
            long newest = lastBoxScan;
            for (ScanResult scan : wifi.getScanResults()) {
                if (ssid.equals(scan.SSID) && scan.timestamp > newest
                        && now - scan.timestamp >= 0 && now - scan.timestamp <= 60_000_000L) {
                    newest = scan.timestamp;
                }
            }
            if (newest != lastBoxScan) {
                lastBoxScan = newest;
                send("scan");
            }
        } catch (IOException ignored) {
            // Settings may not have been saved yet.
        } catch (SecurityException error) {
            System.err.println("Wi-Fi scan result unavailable: " + error.getMessage());
        }
    }

    private FileObserver watch(File dir, String... names) {
        return new FileObserver(dir, FileObserver.CLOSE_WRITE | FileObserver.MOVED_TO
                | FileObserver.MOVED_FROM | FileObserver.CREATE | FileObserver.DELETE
                | FileObserver.DELETE_SELF | FileObserver.MOVE_SELF) {
            @Override public void onEvent(int event, String path) {
                if (path == null) {
                    handler.post(() -> send("settings"));
                    return;
                }
                for (String name : names) {
                    if (path.equals(name)) {
                        handler.post(() -> send("settings"));
                        return;
                    }
                }
            }
        };
    }

    private static void send(String event) {
        System.out.println(event);
        if (System.out.checkError()) System.exit(1);
    }

    public static void main(String[] args) {
        try {
            Looper.prepareMainLooper();
            Class<?> thread = Class.forName("android.app.ActivityThread");
            Context context = (Context) thread.getMethod("getSystemContext")
                    .invoke(thread.getMethod("systemMain").invoke(null));
            WifiEvents events = new WifiEvents(context, new File(args[0]), new File(args[1]));
            send("ready");
            Looper.loop();
            java.lang.ref.Reference.reachabilityFence(events);
        } catch (Exception error) {
            error.printStackTrace(System.err);
            System.exit(1);
        }
    }
}
