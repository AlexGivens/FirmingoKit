import { parentPort } from "node:worker_threads";
import { installWorker } from "./Sources/WorkerCore.js";
/** Development-only adapter executes the exact browser-capable worker core on Node. */
if (parentPort === null) { throw new Error("Compiler adapter requires a worker thread"); }
installWorker(handler => parentPort.on("message", handler), (message, transfers = []) => parentPort.postMessage(message, transfers));
