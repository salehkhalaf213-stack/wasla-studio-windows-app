# Numo — AI Marketing Studio (Standalone MVP)

A standalone Arabic-first marketing workspace, isolated from the WASLA STUDIO application.

## Current MVP
- Independent single-page app under `ai-marketing-platform/`.
- Lead capture and local browser persistence.
- Arabic/English outreach copy templates.
- Poster creative-brief builder with a layout preview.
- Short-form video storyboard builder.
- Weekly content-plan starter.
- Responsive RTL interface.

## Important current limitations
This MVP does **not** yet call a live AI provider, search the web for leads, generate final image/video files, connect social accounts, or publish/schedule posts. Those require backend credentials, provider integrations, and OAuth permissions. The UI labels these boundaries explicitly; no fake AI or publishing success is reported.

## Deploy as a separate Cloudflare Pages project
Create a **new** Cloudflare Pages project (do not change the existing WASLA project):
- Repository: `salehkhalaf213-stack/wasla-studio-windows-app`
- Production branch: `feature/ai-marketing-platform-standalone`
- Root directory: `ai-marketing-platform`
- Build command: leave empty
- Build output directory: `.`

This deploys only this standalone folder. It does not change the WASLA Pages project or its production branch.

## Next implementation stages
1. Provision a dedicated Supabase project/database with authentication, tenant isolation, RLS, and storage.
2. Add authenticated server-side AI endpoints; store provider secrets only in server-side secrets.
3. Connect text generation and image generation; save generated assets to private storage.
4. Integrate a video generation/rendering provider and export MP4 assets.
5. Add official social-platform OAuth integrations, approval workflow, and compliant scheduling/publishing.

No production credentials or customer data are included in this repository.
