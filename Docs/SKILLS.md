# Skills Settings

Administrators can open **Settings > Intelligence > Skills** to import a skill
folder, preview its frozen text and required tools, and install it for Everyone
or Only Me. Select the directory containing `SKILL.md`, not its parent. Local
source files remain untouched. No restart is needed after an import.

The native folder chooser accepts UTF-8 `.md` and `.txt` documents, with at most
32 files, 64 KB each, 512 KB total and a 12,000-character main file. Hidden files
are ignored. Symlinks, scripts and binary files are rejected. The client uploads
file contents and relative names, never a path for the server to open.

**Validate Preview** checks the complete bundle against the current user's MCP
catalog. Missing tools and instruction-budget problems block **Install Skill**.
Changing the folder, visibility or fallback pin invalidates the previous review.
The server recomputes the review hash and revalidates before storing anything.

The installed list supports enable/disable, frozen-document inspection, and
confirmed removal. Removing a skill never deletes its original folder. Reimporting
changed content retains the old installed version as disabled; only one version
can be active for each name and scope. Identical active reimports are idempotent.

This UI requires backend migration `062_skill_bundles` and the `/admin/skill-bundles`
API. Existing plaintext skills still appear and can be managed. Bundles retain
complete main instructions; scoped reference reads are provided by the backend's
`read_skill_file` tool. Skills remain guidance, not extra account permissions.

Validation: a macOS test build plus `SkillBundleTests` exercise folder imports,
symlink/script rejection, size limits, wire casing, and unchanged source files.
Visual acceptance remains user-driven; no working app is restarted by the agent.

## Release Pairing

Native v0.2.6 pairs with backend v0.7.45 and migration `062_skill_bundles`.
The image-card inspector uses the same backend's account-bound preview bridge;
private image display additionally requires ImageLab's read-only resource support.
