import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import { readFileSync } from 'node:fs';

// Source the harness's canonical Diátaxis docs/ tree AND its rendered reports/ outputs
// into the single Starlight `docs` collection. The base is `./src/content/docs` (the
// committed symlink to the repo-root docs/ tree) — the standard content location, which
// the `astro-rehype-relative-markdown-links` plugin relies on to rewrite relative *.md
// cross-links to routes. reports/ is reached via the committed `docs/reports` symlink
// (-> ../reports).
//
// We wrap `glob()` (see `reportsLoader` below) for two reasons docsLoader cannot serve:
//   1. EVERY research deliverable under reports/<topic>/ is a critical, consumer-facing
//      page and must render — the genre report-*.md carry a Starlight `title`, but the
//      README (topic index), the neutral synthesis, the falsification report, and the
//      research-progress log do NOT. Rather than mutate those generated artifacts, the
//      loader DERIVES the required `title` from the file's body `# H1` (falling back to a
//      humanized filename), so they render as-is. Hiding them (the old approach) obfuscated
//      the research; serving the full tree is ADR-0009 (superseded).
//   2. The per-topic README is re-slugged to the topic INDEX route (`reports/<topic>/`)
//      so it is the landing page for the topic, the way a per-directory README reads on GitHub.
//
// We still exclude `reports/_meta/` (the gate fixture), `findings/*.json` (raw MIF data,
// not pages), and the `*-delta.md` / `*-build-spec.md` build logs (no stable page shape).
//
// Routing and the sidebar derive from each entry's id (path relative to base): docs keep
// their root routes, reports route under `reports/`. The leading body H1 of a derived-title
// page is stripped at render by the remark plugin in astro.config.mjs so the heading shows once.

const MD_EXT = /\.(?:markdown|mdown|mkdn|mkd|mdwn|md|mdx)$/i;

function slugifySegment(seg) {
  return seg
    .toLowerCase()
    .replace(/[\s_]+/g, '-')
    .replace(/[^a-z0-9.-]/g, '')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

// Mirror Astro's default path-derived slug for our (kebab-case) content, with one
// override: a topic's README.md becomes the topic index (drop the trailing README
// segment) so it routes at `reports/<topic>/` instead of `reports/<topic>/readme/`.
function generateId({ entry, data }) {
  if (typeof data?.slug === 'string' && data.slug) return data.slug;
  const segs = entry.replace(MD_EXT, '').split('/');
  if (segs.length > 1 && /^README$/i.test(segs[segs.length - 1])) segs.pop();
  return segs.map(slugifySegment).join('/');
}

function humanize(name) {
  return name
    .replace(MD_EXT, '')
    .replace(/[-_]+/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();
}

// Derive a page title from the file's first body `# H1` (after any YAML frontmatter).
function deriveTitleFromH1(filePath) {
  try {
    const text = readFileSync(filePath, 'utf8');
    const body = text.replace(/^﻿?---\r?\n[\s\S]*?\r?\n---\r?\n?/, '');
    const m = body.match(/^[ \t]*#[ \t]+(.+?)[ \t]*$/m);
    if (m) return m[1].trim();
  } catch {
    /* fall through to filename */
  }
  return null;
}

// Wrap glob() so a reports/ entry that lacks a Starlight `title` gets one derived from
// its H1 (or filename) before schema validation — the file itself is never modified.
function reportsLoader(options) {
  const base = glob(options);
  return {
    ...base,
    name: 'reports-derived-title-glob',
    load: (context) => {
      const parseData = context.parseData;
      context.parseData = (props) => {
        const t = props?.data?.title;
        if ((t == null || t === '') && props.filePath) {
          props.data.title =
            deriveTitleFromH1(props.filePath) ?? humanize(props.filePath.split('/').pop() ?? props.id);
        }
        return parseData(props);
      };
      return base.load(context);
    },
  };
}

export const collections = {
  docs: defineCollection({
    loader: reportsLoader({
      base: './src/content/docs',
      generateId,
      pattern: [
        '**/[^_]*.{markdown,mdown,mkdn,mkd,mdwn,md,mdx}',
        '!reports/_meta/**',
        '!reports/**/findings/**',
        // Build logs with no stable page shape — not deliverables.
        '!reports/**/*-delta.md',
        '!reports/**/*-build-spec.md',
      ],
    }),
    schema: docsSchema(),
  }),
};
