# Zen

A calm mobile app for breathing, meditation and journaling. It works **fully offline**.

Zen is a Progressive Web App (PWA). After the first visit it installs to the home screen like a normal app,
and it never needs the internet again. Nothing leaves the phone: no accounts, no servers, no tracking.

## Features

- **Today**: a daily quote, your streak, total minutes, and a 7-day practice view.
- **Breathe**: an animated guide with four patterns (Calm 4-6, Box 4-4-4-4, 4-7-8, Balance 5-5).
- **Meditate**: a timer from 1 to 30 minutes with a singing-bowl bell, an optional bell every minute, and optional
  soft background sound. All sound is generated on the device, so there are no audio files to download.
  The screen stays on while you practice.
- **Journal**: a mood and a short note, saved on the device.
- Light and dark themes follow your phone's setting.

## Run it

No build step or dependencies. Serve the folder over HTTP:

```sh
npx http-server -p 8080 -c-1
# or: python3 -m http.server 8080
```

Open http://localhost:8080. Offline support (the service worker) needs `localhost` or HTTPS.

## Put it on your phone

1. Host the folder on any static HTTPS host (GitHub Pages, Netlify, Cloudflare Pages, …).
2. Open the URL on your phone once.
   - **Android (Chrome):** menu ⋮ → *Install app* / *Add to Home screen*.
   - **iPhone (Safari):** Share → *Add to Home Screen*.
3. Launch it from the home screen. It now works in airplane mode.

## Project layout

| File | Purpose |
| --- | --- |
| `index.html` | App screens and tab bar |
| `styles.css` | Look and feel (light and dark) |
| `app.js` | All app logic: storage, breathing, timer, sound, journal |
| `sw.js` | Service worker that caches the app for offline use |
| `manifest.webmanifest` | Name, icons and colors used when installed |
| `icons/` | App icons |

When you change any file, bump `CACHE_VERSION` in `sw.js` so installed copies pick up the update.

## Data

Everything is stored in the browser's `localStorage` under the key `zen.v1`. Uninstalling the app or clearing
site data deletes it.
