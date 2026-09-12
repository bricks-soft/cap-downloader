# cap-downloader

Download files with Android Download Manager or an iOS background URLSession.

On iOS, `download()` resolves after the transfer is queued. The native session
continues while the app is suspended, stores completed files in
`Documents/Downloads` with iCloud backup disabled, and posts a notification that
opens the downloaded file. Immediate queue failures reject the promise; later
transfer failures are reported with a native notification. A user force-quit
cancels active iOS background transfers.

The first iOS download requests notification permission. Queueing fails if the
permission is denied because notifications provide the completion and open-file
interaction.

## Install

```bash
npm install @bricks-soft/cap-downloader
npx cap sync
```

For iOS background relaunch handling, forward the application delegate callback:

```swift
import BricksSoftCapDownloader

func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
) {
    if !CapDownloaderPlugin.handleEventsForBackgroundURLSession(
        identifier,
        completionHandler: completionHandler
    ) {
        completionHandler()
    }
}
```

## API

<docgen-index>

* [`download(...)`](#download)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### download(...)

```typescript
download(options: Options) => Promise<{ id?: number; }>
```

| Param         | Type                                        |
| ------------- | ------------------------------------------- |
| **`options`** | <code><a href="#options">Options</a></code> |

**Returns:** <code>Promise&lt;{ id?: number; }&gt;</code>

--------------------


### Interfaces


#### Options

| Prop           | Type                |
| -------------- | ------------------- |
| **`title`**    | <code>string</code> |
| **`url`**      | <code>string</code> |
| **`filename`** | <code>string</code> |
| **`mimetype`** | <code>string</code> |

</docgen-api>
