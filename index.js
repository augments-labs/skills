// Package entry for the OpenCode (1.x / 2.x) adapter.
//
// OpenCode 1.x scans named function exports as plugin hook factories.
// OpenCode 2.x resolves a configured plugin directory via `index.js` and reads
// `default.id` and `default.setup(ctx)`.

export async function engineeringSkillsPlugin() {
  return {};
}

export async function setup() {
  // Skeleton entrypoint; wired to the generated engineering-skills plugin in Phase 4 (v1.0.0).
}

export default {
  id: "engineering-skills",
  setup,
  server: engineeringSkillsPlugin,
};
