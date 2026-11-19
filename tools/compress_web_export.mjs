import { createReadStream, createWriteStream, statSync } from "node:fs";
import { pipeline } from "node:stream/promises";
import { createBrotliCompress, constants } from "node:zlib";
import path from "node:path";

const root = process.argv[2] ?? "build/web";
const quality = Number(process.argv[3] ?? 5);
const files = ["index.pck", "index.wasm"];

if (!Number.isInteger(quality) || quality < 0 || quality > 11) {
	throw new Error("Brotli quality must be an integer from 0 to 11");
}

for (const name of files) {
	const source = path.join(root, name);
	const destination = `${source}.br`;
	const sourceBytes = statSync(source).size;
	const compressor = createBrotliCompress({
		params: {
			[constants.BROTLI_PARAM_QUALITY]: quality,
		},
	});

	await pipeline(
		createReadStream(source),
		compressor,
		createWriteStream(destination),
	);

	const compressedBytes = statSync(destination).size;
	const saved = (1 - compressedBytes / sourceBytes) * 100;
	console.log(`${name}: ${sourceBytes} -> ${compressedBytes} bytes (${saved.toFixed(1)}% smaller)`);
}

console.log("Serve each .br file at the original URL with Content-Encoding: br.");
