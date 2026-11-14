package local.carplay.cellular;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.IBinder;
import android.util.Log;

public final class CellularService extends Service {
    private static final String CHANNEL = "carplay_cellular";
    private ConnectivityManager connectivity;
    private ConnectivityManager.NetworkCallback cellular;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager notifications = getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(new NotificationChannel(
                CHANNEL, "CarPlay 蜂窝连接", NotificationManager.IMPORTANCE_LOW));
        startForeground(1, new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
                .setContentTitle("无线Carplay盒子5G中继")
                .setContentText("正在为 CarPlay 保留蜂窝网络")
                .setOngoing(true)
                .build());

        if (cellular == null) {
            connectivity = getSystemService(ConnectivityManager.class);
            ConnectivityManager.NetworkCallback callback = new ConnectivityManager.NetworkCallback();
            NetworkRequest request = new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build();
            try {
                connectivity.requestNetwork(request, callback);
                cellular = callback;
            } catch (RuntimeException error) {
                Log.e("CarPlayCellular", "Could not request cellular connectivity", error);
                stopSelf(startId);
            }
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (cellular != null) {
            connectivity.unregisterNetworkCallback(cellular);
            cellular = null;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
