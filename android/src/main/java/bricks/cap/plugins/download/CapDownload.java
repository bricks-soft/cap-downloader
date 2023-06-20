package bricks.cap.plugins.download;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Environment;

class DownloadOptions {
    final String title;
    final Uri url;
    final String filename;
    final String mimetype;

    public DownloadOptions(String title, Uri url, String filename, String mimetype) {
        this.title = title;
        this.url = url;
        this.filename = filename;
        this.mimetype = mimetype;
    }
}

class NotImplementedError extends Exception {
    public NotImplementedError(String message) {
        super(message);
    }
}


public class CapDownload {
    private final Context context;

    public CapDownload(Context context) {
        this.context = context;
    }

    public long download(DownloadOptions options) throws NotImplementedError {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) {
            throw new NotImplementedError("Not available on Android API 23 or earlier.");
        }

        final DownloadManager dm = this.context.getSystemService(DownloadManager.class);
        final DownloadManager.Request req = new DownloadManager.Request(options.url)
                .setTitle(options.title)
                .setMimeType(options.mimetype)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, options.filename);

        return dm.enqueue(req);
    }
}
