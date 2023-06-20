import { registerPlugin } from '@capacitor/core';

import type { CapDownloadPlugin } from './definitions';

const CapDownload = registerPlugin<CapDownloadPlugin>('CapDownload', {
  web: () => import('./web').then(m => new m.CapDownloadWeb()),
});

export * from './definitions';
export { CapDownload };
