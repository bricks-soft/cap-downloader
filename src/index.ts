import { registerPlugin } from '@capacitor/core';

import type { CapDownloaderPlugin } from './definitions';

const CapDownloader = registerPlugin<CapDownloaderPlugin>('CapDownloader', {
  web: () => import('./web').then(m => new m.CapDownloaderWeb()),
});

export * from './definitions';
export { CapDownloader };
