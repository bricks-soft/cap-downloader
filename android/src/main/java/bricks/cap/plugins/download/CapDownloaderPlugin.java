package bricks.cap.plugins.download;

import android.net.Uri;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "CapDownloader")
public class CapDownloaderPlugin extends Plugin {

    private final CapDownloader implementation = new CapDownloader();

    @PluginMethod
    public void download(PluginCall call) {
        final JSObject optionsJ = call.getData();
        final String title = optionsJ.getString("title");
        final String url = optionsJ.getString("url");
        final String filename = optionsJ.getString("filename");
        final String mimeType = optionsJ.getString("mimetype");

        final DownloadOptions options = new DownloadOptions(title, Uri.parse(url), filename, mimeType);

        try {
            JSObject ret = new JSObject();
            final long id = implementation.download(getContext(), options);
            ret.put("id", id);
            call.resolve(ret);
        } catch (NotImplementedError e) {
            call.reject(e.getMessage(), e);
        }
    }
}
