# Nina Website Design QA

## Compared

- Source direction: `web/design-references/landing-conversa-alivio.png`
- Desktop hero: `web/design-references/landing-implementation-hero.png`
- Desktop product: `web/design-references/landing-implementation-product.png`
- Desktop support: `web/design-references/landing-implementation-support.png`
- Mobile hero: `web/design-references/landing-implementation-mobile.png`
- Mobile steps: `web/design-references/landing-implementation-mobile-steps.png`
- Mobile product: `web/design-references/landing-implementation-mobile-product.png`
- Mobile invite: `web/design-references/invite-implementation-mobile.png`

Desktop was checked at 1440 x 900. Mobile was checked at 390 x 844.

## Findings Resolved

- P1: Dynamic invite rewrite looped in Cloudflare Pages. The public route now
  rewrites to a separate `/join/` shell with one valid Pages rule.
- P1: Invite shell leaked its internal route through canonical metadata and the
  sitemap. Canonical now points to `/invite/`; `/join/` is excluded.
- P1: An unavailable invite API could appear to validate arbitrary codes. The
  page now shows an explicit unverified state and defers validation to the app.
- P2: Desktop hero wrapped into too many lines and pushed the primary action
  down. The final composition follows the selected three-line hierarchy.
- P2: Mobile responsive behavior, menu state, horizontal overflow, anchors,
  dialog controls, FAQ disclosure, and invite states were verified.

## Final Checks

- No unresolved P0, P1, or P2 design findings.
- Desktop horizontal overflow: 0 px.
- Mobile horizontal overflow: 0 px.
- Primary desktop action remains inside the first 900 px viewport.
- Real Nina app screens are used instead of copied reference artwork.
- The structure and visual rhythm are inspired by the references while the
  copy, palette, character, screenshots, and product story remain Nina-specific.

Result: passed
