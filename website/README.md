# LOGIT Website

Marketing site for the LOGIT iPhone fitness app.

## Local development

1. Run `npm install`
2. Run `npm run dev`
3. Run `npm run build` for a production build

## GitHub Pages

The project is configured for GitHub Pages with relative asset paths (`base: "./"`), so it can be served from either a user site or a project site.

Deployment workflow:

1. Push this project to GitHub.
2. In the repository settings, open `Pages`.
3. Set the source to `GitHub Actions`.
4. Push to `main` to trigger `.github/workflows/deploy.yml`.
