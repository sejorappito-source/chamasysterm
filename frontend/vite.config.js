import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// In production the built assets are served by the same cowboy process
// that serves /api, so no proxy is needed there. For local `npm run dev`
// (frontend on :5173, backend on :8080), proxy /api so relative fetches
// in src/api.js work without a CORS dance.
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:8080",
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: "dist",
  },
});
