package bricks.cap.plugins.download;

import android.net.Uri;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "CapDownload")
public class CapDownloadPlugin extends Plugin {

    private CapDownload implementation = new CapDownload(this.getContext());

    @PluginMethod
    public void echo(PluginCall call) {
        final JSObject optionsJ = call.getObject("options", new JSObject());
        final String title = optionsJ.getString("title");
        final String url = optionsJ.getString("url");
        final String filename = optionsJ.getString("filename");
        final String mimeType = optionsJ.getString("mimeType");

        final DownloadOptions options = new DownloadOptions(title, Uri.parse(url), filename, mimeType);

        JSObject ret = new JSObject();
        try {
            ret.put("id", implementation.download(options));
        } catch (NotImplementedError e) {
            call.reject(e.getMessage(), e);
        }
        call.resolve(ret);
    }
}
