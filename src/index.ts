import { registerPlugin } from '@capacitor/core';

import type { CapDownloaderPlugin } from './definitions';

const nativeDownloader = registerPlugin<CapDownloaderPlugin>('CapDownloader', {
  web: () => import('./web').then((m) => new m.CapDownloaderWeb()),
});

const CapDownloader: CapDownloaderPlugin = {
  download: (options) => {
    if (/^\s*(blob|data):/i.test(options.url)) {
      return import('./web').then(({ CapDownloaderWeb }) => new CapDownloaderWeb().download(options));
    }
    return nativeDownloader.download(options);
  },
};

export * from './definitions';
export { CapDownloader };
