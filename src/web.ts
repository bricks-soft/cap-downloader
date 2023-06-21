import { WebPlugin } from '@capacitor/core';
import { saveAs } from 'file-saver';

import type { CapDownloaderPlugin, Options } from './definitions';

export class CapDownloaderWeb extends WebPlugin implements CapDownloaderPlugin {
  async download(options: Options): Promise<{ id?: number }> {
    return fetch(options.url)
      .then(response => response.blob())
      .then(blob => saveAs(blob, options.filename))
      .then(() => ({}));
  }
}
