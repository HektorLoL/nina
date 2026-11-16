import { assert } from "@std/assert";

Deno.test("the site pings the database every day so a free Supabase project never pauses", async () => {
  const wrangler = await Deno.readTextFile(
    new URL("../wrangler.toml", import.meta.url),
  );
  const worker = await Deno.readTextFile(
    new URL("../src/worker.ts", import.meta.url),
  );

  assert(/\[triggers\]\s*crons = \["\d+ \d+ \* \* \*"\]/.test(wrangler));
  const scheduled = worker.slice(worker.indexOf("async scheduled("));
  assert(scheduled.length > 0 && worker.includes("async scheduled("));
  assert(scheduled.includes("await checkWaitlistDependencies("));
  assert(scheduled.includes('event: "nina_web_keepalive_pinged"'));
});
