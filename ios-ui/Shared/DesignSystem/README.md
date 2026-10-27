# Shared design system

Read the [design-system guide](../../../docs/design-system.md) and [UI agent instructions](../../AGENTS.md) before adding visual code here. The guide is the single reference for the supplied palette, Gabarito type scale, layout, native component patterns and accessibility expectations; do not duplicate those tables in instruction files.

This folder currently contains documentation and a placeholder only. It has no Swift theme tokens, registered Gabarito assets or reusable controls. Existing feature screens still use their current native styles.

When an implementation task authorizes visual work, place reusable tokens, text-style helpers and components here as needed. Preserve Dynamic Type, semantic Light/Dark appearance and native control semantics. Keep networking, provider SDKs and business logic outside the design system.

Update [project.yml](../../project.yml) only if the implementation requires a build/resource configuration change, then follow the documented project-generation workflow. Adding this Markdown reference alone does not require regeneration.
