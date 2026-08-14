import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://ninai.app",
  integrations: [
    sitemap({
      filter: (page) =>
        !page.includes("/join/") && !page.includes("/unsubscribe/"),
    }),
  ],
  output: "static",
  build: {
    assets: "_assets",
  },
});
