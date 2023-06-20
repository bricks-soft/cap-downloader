import {WebPlugin} from '@capacitor/core';

import type {CapDownloadPlugin, Options} from './definitions';

export class CapDownloadWeb extends WebPlugin implements CapDownloadPlugin {
    async download(_options: Options): Promise<{ id: number }> {
        throw new Error("Not implemented");
    }
}
