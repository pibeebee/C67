import { defineConfig } from "cf/config";

export default defineConfig({
  worker: {
    name: "travelants-support",
    compatibilityDate: "2026-11-19",
    domains: ["travelants.giovanc.com"],
    workersDev: false,
    previewUrls: false,
    assets: { htmlHandling: "force-trailing-slash" },
  },
});
