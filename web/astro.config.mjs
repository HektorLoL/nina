import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import icon from "astro-icon";

export default defineConfig({
  site: "https://ninai.app",
  integrations: [
    sitemap({
      filter: (page) =>
        !page.includes("/join/") && !page.includes("/unsubscribe/"),
    }),
    icon(),
  ],
  output: "static",
  build: {
    assets: "_assets",
  },
});
