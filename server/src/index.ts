import { loadConfig } from './config.js';
import { createApp } from './app.js';

const config = loadConfig();
const context = createApp(config);
const server = context.app.listen(config.PORT, config.HOST, () => {
  console.log(`JianHuan source service listening on ${config.HOST}:${config.PORT}`);
});

function shutdown(signal: string): void {
  console.log(`Received ${signal}, shutting down`);
  server.close(() => {
    context.close();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
