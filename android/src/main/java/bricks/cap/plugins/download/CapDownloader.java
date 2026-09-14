package bricks.cap.plugins.download;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Environment;
import android.webkit.MimeTypeMap;

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

class InvalidUrlError extends Exception {

    public InvalidUrlError(String message) {
        super(message);
    }
}

public class CapDownloader {

    public long download(Context context, DownloadOptions options) throws NotImplementedError, InvalidUrlError {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) {
            throw new NotImplementedError("Not available on Android API 23 or earlier.");
        }

        if (!isDownloadableUrl(options.url)) {
            throw new InvalidUrlError("Only http and https URLs can be downloaded, got: " + options.url);
        }

        final String ext = MimeTypeMap.getFileExtensionFromUrl(options.url.toString());
        String mimetype = !ext.isEmpty() ? MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) : null;
        if (mimetype == null) {
            mimetype = options.mimetype;
        }

        final DownloadManager dm = context.getSystemService(DownloadManager.class);
        final DownloadManager.Request req = new DownloadManager.Request(options.url)
            .setTitle(options.title)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setMimeType(mimetype)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, options.filename);

        return dm.enqueue(req);
    }

    /**
     * DownloadManager.Request throws IllegalArgumentException for any non-HTTP(S) URI, which would
     * escape as an uncaught exception and kill the host app. Check the scheme first so the caller
     * gets a rejected promise instead.
     */
    static boolean isDownloadableUrl(Uri url) {
        return url != null && isDownloadableScheme(url.getScheme());
    }

    static boolean isDownloadableScheme(String scheme) {
        return "http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme);
    }
}
