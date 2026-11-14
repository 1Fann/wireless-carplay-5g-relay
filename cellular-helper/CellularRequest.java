package local.carplay.cellular;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Looper;
import java.lang.reflect.Method;

/** Process entry point for a KernelSU-managed cellular network request. */
public final class CellularRequest {
    public static void main(String[] args) throws Exception {
        Looper.prepareMainLooper();
        Class<?> type = Class.forName("android.app.ActivityThread");
        Method main = type.getMethod("systemMain");
        Object thread = main.invoke(null);
        Context context = (Context) type.getMethod("getSystemContext").invoke(thread);
        ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
        NetworkRequest request = new NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build();
        connectivity.requestNetwork(request, new ConnectivityManager.NetworkCallback());
        System.out.println("Cellular request registered");
        Looper.loop();
    }
}
