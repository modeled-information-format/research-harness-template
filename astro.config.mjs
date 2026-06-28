import { readFileSync, existsSync, readdirSync } from "node:fs";
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import starlightLlmsTxt from "starlight-llms-txt";
import starlightImageZoom from "starlight-image-zoom";
import starlightLinksValidator from "starlight-links-validator";
import astroMermaid from "astro-mermaid";
import rehypeRelativeMarkdownLinks from "astro-rehype-relative-markdown-links";

// ---------------------------------------------------------------------------
// Site-projection controls live in harness.config.json `.site` (the one file a
// clone edits) so neither the template nor a clone hand-edits THIS file —
// astro.config.mjs stays byte-identical across instances and `copier update`
// never conflicts on it. We read the manifest at config-eval time and branch on
// it. Absent/partial `.site` falls back to: llms-txt + mermaid ON, the two
// optional plugins OFF, primarySurface "auto".
// ---------------------------------------------------------------------------
const BASE = "/research-harness-template";
const cfg = existsSync("./harness.config.json")
  ? JSON.parse(readFileSync("./harness.config.json", "utf8"))
  : {};
const siteCfg = cfg.site ?? {};
const plugins = {
  llmsTxt: true,
  mermaid: true,
  imageZoom: false,
  linksValidator: false,
  ...(siteCfg.plugins ?? {}),
};

// hasReports: does reports/ hold at least one real rendered report PAGE? Mirror the
// content.config.ts loader negations exactly — a topic dir that is not `_meta`,
// containing a markdown file that the loader turns into a page: a `[^_]*` basename
// with a markdown extension, excluding the continuity log (`research-progress.md`)
// and the topic README (`README.md`, a repo-nav index excluded from the collection).
// The template ships the example-topic report, so this is true there too — which is
// why the template pins primarySurface "docs" rather than relying on "auto".
const REPORT_MD = /\.(?:markdown|mdown|mkdn|mkd|mdwn|md|mdx)$/i;
const NON_PAGE_REPORT_MD = new Set(["research-progress.md", "README.md"]);
function isReportPage(f) {
  return REPORT_MD.test(f) && !f.startsWith("_") && !NON_PAGE_REPORT_MD.has(f);
}
function hasRenderedReports() {
  if (!existsSync("./reports")) return false;
  for (const d of readdirSync("./reports", { withFileTypes: true })) {
    if (!d.isDirectory() || d.name === "_meta") continue;
    if (readdirSync(`./reports/${d.name}`).some(isReportPage)) return true;
  }
  return false;
}
const hasReports = hasRenderedReports();
const primary =
  siteCfg.primarySurface === "reports" ? "reports"
  : siteCfg.primarySurface === "docs" ? "docs"
  : hasReports ? "reports" : "docs"; // "auto" (or unset)

// The harness docs cross-link each other with relative *.md paths (so they render on GitHub
// too). Starlight 0.41 does not resolve those natively, so we keep rewriting them to built
// routes at build time. The plugin's peer range caps at astro <7, but it functions on astro 7
// (verified by build); a package.json `overrides` relaxes the peer to `$astro`. `collectionBase:
// false` because the `docs` collection is served at the site root, not under /docs.
const docContentGroups = [
  { label: "Tutorials", collapsed: true, items: [{ autogenerate: { directory: "tutorials", collapsed: true } }] },
  { label: "How-to guides", collapsed: true, items: [{ autogenerate: { directory: "how-to", collapsed: true } }] },
  { label: "Reference", collapsed: true, items: [{ autogenerate: { directory: "reference", collapsed: true } }] },
  { label: "Explanation", collapsed: true, items: [{ autogenerate: { directory: "explanation", collapsed: true } }] },
  { label: "Decisions (ADRs)", collapsed: true, items: [{ autogenerate: { directory: "adr", collapsed: true } }] },
];
const reportsGroup = {
  label: "Reports",
  collapsed: true,
  items: [
    { label: "Overview", link: "/reports/" },
    { autogenerate: { directory: "reports", collapsed: true } },
  ],
};
const ecosystemGroup = {
  // Bidirectional traversal: links OUT of this sub-site back to the org root
  // and the sibling ecosystem surfaces.
  label: "MIF ecosystem",
  collapsed: true,
  items: [
    { label: "MIF home", link: "https://modeled-information-format.github.io/" },
    { label: "Ecosystem docs", link: "https://modeled-information-format.github.io/docs/" },
    { label: "Specification (mif-spec.dev)", link: "https://mif-spec.dev" },
  ],
};
// Reports lead the sidebar when they are the primary surface; otherwise they sit
// after the docs. The MIF-ecosystem links stay last. When there are no reports the
// group is omitted entirely.
const sidebar = !hasReports
  ? [...docContentGroups, ecosystemGroup]
  : primary === "reports"
    ? [reportsGroup, ...docContentGroups, ecosystemGroup]
    : [...docContentGroups, reportsGroup, ecosystemGroup];

const starlightPlugins = [
  ...(plugins.llmsTxt ? [starlightLlmsTxt()] : []),
  ...(plugins.imageZoom ? [starlightImageZoom()] : []),
  ...(plugins.linksValidator ? [starlightLinksValidator()] : []),
];

// The research-harness docs are mounted as a sub-site of the MIF org Pages root,
// the same way doc-site serves /docs. The org Pages shell (…github.io deploy.yml)
// checks this repo out, runs `npm run build`, and mounts dist/ under /research-harness-template.
export default defineConfig({
  site: "https://modeled-information-format.github.io",
  base: BASE,
  markdown: {
    rehypePlugins: [
      [
        rehypeRelativeMarkdownLinks,
        { collectionBase: false, base: BASE, trailingSlash: "always" },
      ],
    ],
  },
  integrations: [
    ...(plugins.mermaid ? [astroMermaid()] : []),
    starlight({
      plugins: starlightPlugins,
      title: "MIF Research Harness",
      customCss: ["./src/styles/mif-brand.css"],
      logo: {
        light: "./src/assets/logo-light.svg",
        dark: "./src/assets/logo-dark.svg",
        replacesTitle: true,
      },
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/modeled-information-format/research-harness-template",
        },
      ],
      sidebar,
    }),
  ],
});
