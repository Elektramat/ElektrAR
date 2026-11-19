# Kabelmeter web app

Web version of the iOS app: pick a cable, enter or measure the route, see the length and price
update live, add to the cart, and plan switches and sockets. Same data and pricing rules as the app.
No build step: plain HTML, CSS and ES modules.

## Run

```sh
cd webapp
python3 -m http.server 8000     # or: npm start
```

Open http://localhost:8000. Opening `index.html` as a file does not work (the data is fetched).

## Deploy on Vercel

The folder is a static site, no build step. In the Vercel project: **Settings > Build and
Deployment**: Root Directory `webapp`, Framework Preset **Other**, Build Command and Output
Directory empty (no override). `vercel.json` sets the content type of the `.usdz` models (AR Quick
Look needs `model/vnd.usdz+zip`), turns off caching of the code and data, and allows the camera.
`manifest.webmanifest` and `icons/` make it installable ("Zet op beginscherm").

## What works where

| | iPhone (Safari) | Android (Chrome) | Desktop |
|---|---|---|---|
| Cable picker, live price, reserve, cart | yes | yes | yes |
| Route as segments in meters | yes | yes | yes |
| Live AR measuring with crosshair and "+" | no (no WebXR) | yes | no |
| Switch on your own wall | AR Quick Look (real 3D model) | WebXR (simple 3D frame, anchored) | no |
| "Mijn lijst" with total price | yes | yes | yes |

- iPhone Safari has no WebXR, so live measuring only works in the iOS app. "Bekijk op je muur"
  opens the USDZ model in AR Quick Look, which snaps it to a wall.
- WebXR needs HTTPS (or `localhost`). To test on an Android phone, deploy the folder to any HTTPS
  host, or use Chrome's port forwarding (`chrome://inspect` > Port forwarding, 8000 → localhost:8000).
- three.js 0.160.0 is loaded from cdn.jsdelivr.net only when an AR session starts; everything else
  works offline once the page is loaded.
- Placements in WebXR stay put during the session but not after a reload: browsers cannot save and
  recognise a room the way ARKit's world map can. The list (and the cart) are saved in the browser.

## Data

`webapp/data` is a copy of `Kabelmeter/Resources` (cables, photos, switches, 3D models).
After changing the app's data:

```sh
scripts/sync_webapp_data.sh
```

## Tests

```sh
cd webapp && npm test     # node --test: pricing (incl. ../shared/pricing-cases.json and rolls), formatting, wall pose
```
