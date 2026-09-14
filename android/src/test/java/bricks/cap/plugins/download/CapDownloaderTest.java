package bricks.cap.plugins.download;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/**
 * Guards the scheme check that keeps a non-HTTP(S) URL away from DownloadManager.Request, which
 * throws IllegalArgumentException and would otherwise escape and kill the host app.
 *
 * Tests the scheme directly rather than through Uri, which is not implemented in local unit tests.
 */
public class CapDownloaderTest {

    @Test
    public void acceptsHttpAndHttpsRegardlessOfCase() {
        assertTrue(CapDownloader.isDownloadableScheme("https"));
        assertTrue(CapDownloader.isDownloadableScheme("http"));
        assertTrue(CapDownloader.isDownloadableScheme("HTTPS"));
        assertTrue(CapDownloader.isDownloadableScheme("Http"));
    }

    @Test
    public void rejectsSchemesDownloadManagerCannotHandle() {
        assertFalse(CapDownloader.isDownloadableScheme("blob"));
        assertFalse(CapDownloader.isDownloadableScheme("data"));
        assertFalse(CapDownloader.isDownloadableScheme("file"));
        assertFalse(CapDownloader.isDownloadableScheme("content"));
        assertFalse(CapDownloader.isDownloadableScheme("ftp"));
    }

    @Test
    public void rejectsMissingScheme() {
        assertFalse(CapDownloader.isDownloadableScheme(null));
        assertFalse(CapDownloader.isDownloadableScheme(""));
    }
}
