import { assertEquals } from "@std/assert";
import { resolveAppStoreListing } from "../src/appStore.ts";

Deno.test("app store listing stays unpublished while the identifier is a placeholder", () => {
  const listing = resolveAppStoreListing({
    PUBLIC_NINA_APP_STORE_ID: "replace_with_the_numeric_app_store_id",
  });

  assertEquals(listing.isPublished, false);
  assertEquals(listing.appStoreURL, undefined);
});

Deno.test("app store listing stays unpublished when the build declares no identifier", () => {
  const listing = resolveAppStoreListing({});

  assertEquals(listing.isPublished, false);
  assertEquals(listing.appStoreURL, undefined);
});

Deno.test("app store listing rejects an identifier that is not a numeric app store id", () => {
  for (const candidate of ["id6470000000", "0470000000", "12345", "6470 000"]) {
    const listing = resolveAppStoreListing({
      PUBLIC_NINA_APP_STORE_ID: candidate,
    });

    assertEquals(listing.isPublished, false);
    assertEquals(listing.appStoreURL, undefined);
  }
});

Deno.test("app store listing publishes the Brazilian store link once the identifier is real", () => {
  const listing = resolveAppStoreListing({
    PUBLIC_NINA_APP_STORE_ID: " 6470000000 ",
  });

  assertEquals(listing.isPublished, true);
  assertEquals(
    listing.appStoreURL,
    "https://apps.apple.com/br/app/id6470000000",
  );
});
