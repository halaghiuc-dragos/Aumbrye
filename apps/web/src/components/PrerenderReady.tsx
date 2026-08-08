/**
 * Renders a marker element that the build-time prerenderer waits for before
 * capturing a route's HTML (see `vite.config.ts`'s `renderAfterElementExists`
 * option). Mount it once a page's data has settled — for pages with no async
 * data, that is immediately on first render.
 */
export default function PrerenderReady() {
  return <span data-prerender-ready="" hidden aria-hidden="true" />;
}
