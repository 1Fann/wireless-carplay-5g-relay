package local.carplay.cellular;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.wifi.ScanResult;
import android.net.wifi.SupplicantState;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Looper;
import android.os.SystemClock;

import java.lang.reflect.Method;

/** Applies the saved Wi-Fi preference to the configured CarPlay network. */
public final class BoxWifi {
    public static void main(String[] args) {
        try {
            if (args.length != 2 || args[0].isEmpty()) {
                throw new IllegalArgumentException("Expected configured Wi-Fi name and event");
            }
            Looper.prepareMainLooper();
            Class<?> thread = Class.forName("android.app.ActivityThread");
            Context context = (Context) thread.getMethod("getSystemContext")
                    .invoke(thread.getMethod("systemMain").invoke(null));
            repair(context, args[0], "scan".equals(args[1]));
        } catch (Exception error) {
            error.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static void repair(Context context, String ssid, boolean allowConnect) throws Exception {
        WifiManager wifi = context.getSystemService(WifiManager.class);
        if (!wifi.isWifiEnabled()) return;

        WifiInfo current = wifi.getConnectionInfo();
        final String savedSsid = "\"" + ssid + "\"";
        if (current != null && current.getSupplicantState() == SupplicantState.COMPLETED
                && !savedSsid.equals(current.getSSID())) return;
        if (!allowConnect && (current == null || !savedSsid.equals(current.getSSID()))) return;

        WifiConfiguration saved = null;
        for (WifiConfiguration candidate : wifi.getConfiguredNetworks()) {
            if (!savedSsid.equals(candidate.SSID)) continue;
            if (isConnectedTo(current, candidate)) {
                saved = candidate;
                break;
            }
            if (saved != null && saved.networkId != candidate.networkId) return;
            saved = candidate;
        }
        if (saved == null || !WifiConfiguration.class.getField("allowAutojoin").getBoolean(saved)) return;

        ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
        Method currentNetwork = WifiManager.class.getMethod("getCurrentNetwork");

        if (isConnectedTo(current, saved)) {
            acceptUnvalidated(wifi, connectivity, currentNetwork, saved);
            return;
        }
        if (!allowConnect || !isIdle(current) || currentNetwork.invoke(wifi) != null
                || !seenRecently(wifi, ssid)) return;
        // Recheck because Android may have resumed its own connection during the scan lookup.
        if (!isIdle(wifi.getConnectionInfo()) || currentNetwork.invoke(wifi) != null
                || !wifi.enableNetwork(saved.networkId, true)) return;

        System.out.println("Requested connection using the saved CarPlay Wi-Fi configuration");
    }

    private static boolean isIdle(WifiInfo info) {
        if (info == null) return true;
        SupplicantState state = info.getSupplicantState();
        return state == SupplicantState.DISCONNECTED || state == SupplicantState.INACTIVE
                || state == SupplicantState.SCANNING;
    }

    private static boolean isConnectedTo(WifiInfo info, WifiConfiguration saved) {
        return info != null && info.getNetworkId() == saved.networkId
                && saved.SSID.equals(info.getSSID());
    }

    private static boolean seenRecently(WifiManager wifi, String ssid) {
        long nowUs = SystemClock.elapsedRealtimeNanos() / 1000;
        for (ScanResult scan : wifi.getScanResults()) {
            long ageUs = nowUs - scan.timestamp;
            if (ssid.equals(scan.SSID) && ageUs >= 0 && ageUs <= 60_000_000L) return true;
        }
        return false;
    }

    private static boolean acceptUnvalidated(WifiManager wifi, ConnectivityManager connectivity,
            Method currentNetwork, WifiConfiguration saved) throws Exception {
        Network network = (Network) currentNetwork.invoke(wifi);
        if (network == null || !isConnectedTo(wifi.getConnectionInfo(), saved)
                || !network.equals(currentNetwork.invoke(wifi))) return false;
        NetworkCapabilities capabilities = connectivity.getNetworkCapabilities(network);
        if (capabilities == null || !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return false;
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                && !WifiConfiguration.class.getField("noInternetAccessExpected").getBoolean(saved)) {
            ConnectivityManager.class.getMethod("setAcceptUnvalidated", Network.class,
                    boolean.class, boolean.class).invoke(connectivity, network, true, true);
            System.out.println("Requested per-network acceptance of local-only Wi-Fi");
        }
        return true;
    }
}
