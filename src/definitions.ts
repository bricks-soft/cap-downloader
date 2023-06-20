export interface Options {
    title: string;
    url: string;
    filename: string;
    mimetype: string;
}

export interface CapDownloadPlugin {
    download(options: Options): Promise<{ id: number }>;
}
