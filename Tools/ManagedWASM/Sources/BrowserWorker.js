import { installWorker } from "./WorkerCore.js";
/** Browser-only entry point; no Node/native APIs are included in the compiler worker. */
installWorker(handler => self.addEventListener("message", event => handler(event.data)),
  (message, transfers = []) => self.postMessage(message, transfers));
