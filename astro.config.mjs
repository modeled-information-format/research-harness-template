import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import astroMermaid from "astro-mermaid";
import rehypeRelativeMarkdownLinks from "astro-rehype-relative-markdown-links";

// The research-harness docs are mounted as a sub-site of the MIF org Pages root,
// the same way doc-site serves /docs. The org Pages shell (…github.io deploy.yml)
// checks this repo out, runs `npm run build`, and mounts dist/ under /research-harness.
export default defineConfig({
  site: "https://modeled-information-format.github.io",
  base: "/research-harness",
  // The harness docs cross-link each other with relative *.md paths (so they render
  // on GitHub too). Rewrite those to the built routes at build time. `collectionBase:
  // false` because the `docs` collection is served at the site root, not under /docs.
  markdown: {
    rehypePlugins: [
      [
        rehypeRelativeMarkdownLinks,
        { collectionBase: false, base: "/research-harness", trailingSlash: "always" },
      ],
    ],
  },
  integrations: [
    astroMermaid(),
    starlight({
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
      sidebar: [
        {
          label: "Tutorials",
          items: [{ autogenerate: { directory: "tutorials" } }],
        },
        {
          label: "How-to guides",
          items: [{ autogenerate: { directory: "how-to" } }],
        },
        {
          label: "Reference",
          items: [{ autogenerate: { directory: "reference" } }],
        },
        {
          label: "Explanation",
          items: [{ autogenerate: { directory: "explanation" } }],
        },
        {
          label: "Decisions (ADRs)",
          items: [{ autogenerate: { directory: "adr" } }],
        },
        {
          // Bidirectional traversal: links OUT of this sub-site back to the org root
          // and the sibling ecosystem surfaces.
          label: "MIF ecosystem",
          items: [
            { label: "MIF home", link: "https://modeled-information-format.github.io/" },
            { label: "Ecosystem docs", link: "https://modeled-information-format.github.io/docs/" },
            { label: "Specification (mif-spec.dev)", link: "https://mif-spec.dev" },
          ],
        },
      ],
    }),
  ],
});
